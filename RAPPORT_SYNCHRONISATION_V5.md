# Rapport d'Architecture & Moteur de Synchronisation Online/Offline (v5)

## 1. Contexte & Objectif
L'application CodeBar Manager a été conçue pour fonctionner avec une résilience maximale en environnement déconnecté (Offline-first) tout en offrant une synchronisation complète et sans accro lorsqu'une connexion au serveur central Laravel 11 (avec Sanctum et base PostgreSQL/SQLite) est disponible.

Ce document présente l'évaluation comparative des architectures de synchronisation possibles, les détails techniques du moteur implémenté, les résultats de vérification et les consignes d'utilisation.

---

## 2. Comparaison des Architectures de Synchronisation

| Approche | Principes Clés | Avantages | Inconvénients / Faiblesses | Décision |
| :--- | :--- | :--- | :--- | :--- |
| **1. Bulk Dump / Vidage REST périodique** | Le client envoie l'intégralité de sa base ou des tables au serveur à intervalles réguliers. | Très simple à concevoir initialement. | • Bande passante explosive.<br>• Risque élevé d'écrasement des modifications concurrentes.<br>• Aucune garantie d'ordonnancement en cas de coupure réseau en cours d'envoi. | ❌ Rejeté |
| **2. CRDTs (Conflict-free Replicated Data Types)** | Types de données mathématiques garantissant la convergence sans coordination (LWW-Element-Set, PN-Counters). | Résolution mathématique des conflits sans autorité centrale. | • Complexité conceptuelle et mathématique disproportionnée pour un catalogue produits et une gestion utilisateurs.<br>• Overhead mémoire important (conservation indéfinie des métadonnées de tombstones et vector clocks).<br>• Incompatibilité avec les contraintes d'unicité relationnelles (codes internes uniques `CAP-XXXX`). | ❌ Rejeté |
| **3. Transactionnel Outbox + Synchronisation Delta Incrémentale avec Clés d'Idempotence** | • Journal local persistant des mutations ordonnées (`SyncMutation`).<br>• Clés d'idempotence UUIDv4 pour éliminer les doublons en cas de réémission.<br>• Push transactionnel atomique côté serveur.<br>• Pull incrémental via timestamp serveur `since` et tombstones.<br>• Résolution Last-Write-Wins (LWW) basée sur l'horloge faisant autorité du serveur. | • **Résilience hors-ligne totale** : aucune opération bloquante pour l'utilisateur.<br>• **Zéro doublon** : l'idempotence protège contre les coupures réseau.<br>• **Performance optimale** : seuls les deltas depuis `last_synced_at` transitent sur le réseau.<br>• **Intégrité stricte** : respecte les contraintes d'unicité des codes internes. | ✅ **Solution Optimale Adoptée** |

---

## 3. Détails Techniques de l'Implémentation

### 3.1. Backend Laravel 11 (`codebar-manager-back`)
1. **Migration & Table `sync_idempotency_keys`** :
   - Table dédiée stockant chaque clé d'idempotence reçue (`key`, `entity_type`, `entity_id`, `status`, `created_at`).
   - Permet d'ignorer en toute sécurité les requêtes rejouées suite à un timeout réseau sans réappliquer les effets de bord.
2. **Endpoints API** :
   - `POST /api/v1/sync/push` (avec alias rétrocompatible `/api/sync/push` et `/api/sync`) :
     - Reçoit un lot ordonné de mutations : `{ "mutations": [ { "idempotency_key": "...", "entity_type": "product|user", "action": "...", "data": {...}, "client_timestamp": "..." } ] }`.
     - Transaction DB atomique : en cas d'erreur fatale, rollback global.
     - Contrôle d'unicité du code interne `internal_code` et arbitrage LWW intégrant `updated_at` et `deleted_at`.
     - Protection contre le décalage d'horloge dans le futur lointain.
     - Prise en charge des mutations utilisateurs (création, mise à jour de mot de passe / statut sans rétrogradation de rôle, suppression) avec traçabilité complète dans `ActivityLog`.
     - Prise en charge des suppressions logiques (`delete`) et physiques (`permanent_delete`).
   - `GET /api/v1/sync/pull` (avec alias `/api/sync/pull`) :
     - Paramètre optionnel `since` (ISO 8601) pour ne récupérer que le différentiel.
     - Retourne `{ "server_time": "...", "products": [...], "users": [...], "tombstones": { "products": [...], "force_deleted_products": [...], "users": [...] } }`.
3. **Réconciliation Super Admin** :
   - `POST /api/migrate-super-admin` : Permet la migration et la synchronisation du compte Super Administrateur créé en local hors-ligne vers le serveur dès que celui-ci est joignable.

### 3.2. Frontend Flutter (`codebar_manager_app`)
1. **Collection Isar `SyncMutation` (Transactional Outbox)** :
   - Toute modification sur `ProductRepository` ou `UserRepository` (`create`, `update`, `softDelete`, `restore`, `deletePermanently`, `updatePassword`) enregistre dans la même transaction Isar l'entité locale ET une entrée dans l'Outbox `SyncMutation`.
2. **Moteur `SyncService` & `SyncController`** :
   - `pushPending()` : Envoie les mutations en attente vers le serveur avec clés d'idempotence, met à jour le statut des mutations, produits et utilisateurs dans Isar (effacement sécurisé des mots de passe en clair après sync).
   - `pullDelta()` / `pullAll()` : Récupère les deltas distants depuis `last_synced_at`, traite les tombstones distants (suppressions logiques et physiques), résout les collisions éventuelles de code interne en réattribuant automatiquement un code au produit local pending, aligne la séquence locale `AppSequence` pour éviter les collisions futures, et enregistre le nouveau `last_synced_at`.
   - `synchronize()` : Orchestre le cycle complet (Push Outbox -> Pull Delta -> Sauvegarde horodatage).
   - `reconcileSuperAdmin()` : Détecte l'absence de token Sanctum et migre automatiquement le Super Admin local sur le serveur.
3. **Expérience Utilisateur & UI** :
   - `SyncStatusBanner` : Indicateur dynamique multi-états (Synchronisation en cours avec loader, Erreur avec bouton Réessayer, Modifications en attente avec bouton Synchroniser, et Synchronisé).
   - `SyncPage` : Page dédiée avec bascule Mode En ligne / Hors-ligne forcé, horodatage du dernier sync, état du serveur et boutons de push/pull/synchro globale.
   - `ProfilePage` : Bouton actif "Synchroniser mes données" et changement de mot de passe journalisé dans l'outbox.
   - `UserListPage` : Bouton AppBar "Tout synchroniser", boutons individuels de synchronisation par utilisateur et réinitialisation de mot de passe journalisée.
   - `LoginPage` : Authentification hybride en ligne avec repli automatique sur la base locale en cas d'absence de réseau.

---

## 4. Bilan des Tests et Vérification

### 4.1. Tests Backend Laravel (`php artisan test`)
- `Tests\Feature\SyncEngineTest` :
  - `test_v1_sync_push_creates_product_with_idempotency_key` : **PASSED**
  - `test_v1_sync_push_idempotent_replay_does_not_duplicate_side_effects` : **PASSED**
  - `test_v1_sync_push_rejects_duplicate_internal_code` : **PASSED**
  - `test_v1_sync_push_detects_last_write_wins_conflict` : **PASSED**
  - `test_v1_sync_pull_returns_deltas_and_tombstones_since_timestamp` : **PASSED**
  - `test_v1_sync_push_user_mutation_creates_and_updates_without_demoting_role` : **PASSED**
  - `test_v1_sync_push_lww_protects_deleted_product_from_stale_update` : **PASSED**
  - `test_v1_sync_pull_includes_force_deleted_products_and_deleted_users_in_tombstones` : **PASSED**
- `Tests\Feature\ApiTest` (tests existants rétrocompatibles) : **6/6 PASSED**
- **Résultat global backend** : 16 tests passés, 71 assertions, 0 échec.

### 4.2. Tests Frontend Flutter (`flutter test`)
- `test/online_sync_test.dart` (tests du moteur en ligne et Outbox) :
  - `SyncMutation Outbox Model Tests` (initialisation, copyWith, sérialisation) : **PASSED**
  - `SyncResult Computation Tests` (isFullSuccess, hasErrors) : **PASSED**
  - `Online SyncController & StateNotifier Tests` (synchronize, pushPending, pullAll, forceOnline, gestion erreurs) : **PASSED**
  - `User mutation serialization and password update outbox payload` : **PASSED**
  - `SyncItemResult tracks conflict and error messages properly` : **PASSED**
- `test/offline_first_test.dart` (tests existants de résilience hors-ligne conservés intacts) : **7/7 PASSED**
- `test/barcode_service_test.dart` : **4/4 PASSED**
- `test/export_controller_test.dart` : **9/9 PASSED**
- `test/export_file_service_test.dart` : **7/7 PASSED**
- **Résultat global frontend** : 35 tests passés, 0 échec.
- **Analyse statique (`flutter analyze`)** : 0 erreur, 0 avertissement.

---

## 5. Guide d'Utilisation

1. **Démarrage du Backend Laravel** :
   ```bash
   cd codebar-manager-back
   php artisan migrate
   php artisan serve --port=8000
   ```
2. **Lancement de l'Application Flutter** :
   ```bash
   cd codebar_manager_app
   flutter run -d windows
   ```
3. **Comportement Réseau & Synchronisation** :
   - **En ligne** : Toutes les créations, éditions et suppressions sont immédiatement consignées dans l'Outbox Isar locale puis transmises au serveur de façon ordonnée avec dédoublonnage d'idempotence.
   - **Hors-ligne** : En cas de coupure de liaison ou de serveur indisponible, l'application fonctionne avec une fluidité totale sans bloquer l'opérateur. Les données sont conservées en local et synchronisées dès que la liaison est rétablie.
   - **Résolution des conflits** : La règle Last-Write-Wins (LWW) basée sur l'horodatage serveur arbitre les écritures concurrentes. Les tombstones garantissent la purge ordonnée des produits et utilisateurs supprimés.
