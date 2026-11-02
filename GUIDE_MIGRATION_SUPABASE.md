# Guide de Migration Supabase Cloud - CodeBar Manager

Ce document récapitule l'architecture, la configuration et le déploiement complets de **CodeBar Manager** sur **Supabase**.

---

## 1. Informations du Projet Supabase

- **Tableau de bord Supabase :** [https://supabase.com/dashboard/project/mpcpofrzuifoqcqrqlke](https://supabase.com/dashboard/project/mpcpofrzuifoqcqrqlke)
- **Supabase Project URL :** `https://mpcpofrzuifoqcqrqlke.supabase.co`
- **Supabase Anon / Publishable API Key :** `sb_publishable_LxlHgIMSNTlCF3Q31C8GAA_1aHzFLHW`

---

## 2. Comptes Super Administrateurs Initiaux

Les deux comptes super administrateurs ont été initialisés dans Supabase Auth :

1. **Capucine Bolo**
   - **Email :** `capucine@gmail.com`
   - **Mot de passe :** `Password123!`
   - **Rôle :** `super_admin`
   - **Auth UID :** `a31c80ce-ad5b-4773-abe6-342d8575c28c`

2. **Boris Dark**
   - **Email :** `borisdark37@gmail.com`
   - **Mot de passe :** `Password123!`
   - **Rôle :** `super_admin`
   - **Auth UID :** `4a5a94c3-cf2c-448c-8887-af16e1152ca5`

> **Note importante sur la confirmation des emails :**
> Dans l'éditeur SQL de votre Dashboard Supabase, l'exécution du script `supabase/schema.sql` exécute automatiquement :
> ```sql
> UPDATE auth.users SET email_confirmed_at = timezone('utc'::text, now()) WHERE email_confirmed_at IS NULL;
> ```
> Vous pouvez également désactiver l'option **"Confirm email"** dans `Dashboard -> Authentication -> Providers -> Email` pour permettre la connexion directe par mot de passe sans validation de lien par courriel.

---

## 3. Schéma PostgreSQL et Sécurité (RLS)

Le script de migration complet est disponible dans :
- [`supabase/schema.sql`](supabase/schema.sql)
- [`supabase/migrations/20261102000000_init_codebar_manager.sql`](supabase/migrations/20261102000000_init_codebar_manager.sql)

### 3.1 Tables créées
1. **`public.profiles` :**
   - Liée à `auth.users(id)` via clé étrangère ON DELETE CASCADE.
   - Attributs : `id`, `email`, `full_name`, `role` (`super_admin`, `admin`, `operator`, `manager`), `is_active`, `created_by`, `disabled_at`, `created_at`, `updated_at`.
   - Trigger `on_auth_user_created` créant automatiquement le profil correspondant lors de chaque inscription.
2. **`public.products` :**
   - Attributs : `id` (UUID), `uuid` (colonne synchronisée), `internal_code` (unique, format `CAP-%04d`), `name`, `category`, `format`, `containment`, `price`, `stock`, `quantity`, `code_type`, `barcode_svg`, `image_url`, `image_base64`, `created_at`, `updated_at`, `deleted_at`.
   - Séquence `public.product_internal_code_seq` avec trigger auto-générant les codes `CAP-XXXX` ou recalibrant la séquence en cas d'insertion d'un code plus élevé venant d'un client déconnecté.
3. **`public.activity_logs` :**
   - Audit trail des actions utilisateurs avec horodatage UTC et métadonnées JSONB.

### 3.2 Buckets de Stockage Supabase Storage
- **`product-images`** : Images des produits (JPEG, PNG, WebP) avec accès public en lecture.
- **`barcode-svgs`** : Fichiers vectoriels SVG des codes-barres et QR codes.

### 3.3 Politiques de Sécurité Row Level Security (RLS)
- RLS activé sur l'ensemble des tables (`profiles`, `products`, `activity_logs`).
- Politiques configurées pour permettre la synchronisation fluide en mode connecté (Supabase JWT) et hors-ligne/anonyme (Anon Key).

---

## 4. Intégration de l'Application Flutter

L'application `codebar_manager_app` intègre désormais le SDK officiel `supabase_flutter: ^2.8.0` :
1. **Initialisation :** Effectuée dans `lib/main.dart` avec `SupabaseConfig.url` et `SupabaseConfig.publishableKey`.
2. **Authentification Supabase (`AuthService`) :**
   - Connexion directe via `client.auth.signInWithPassword`.
   - Détection des rôles super administrateur.
   - Repli transparent sur la base locale Isar en l'absence de réseau (mode Offline-first résilient).
3. **Synchronisation Hybride (`SyncService` & `ProductRepository`) :**
   - Push direct des mutations locales vers les tables Supabase `products` et `profiles`.
   - Pull delta descendant et mise à jour de la séquence interne `CAP-XXXX`.
   - Conservation intégrale de la base locale Isar et de la file d'attente Outbox (`SyncMutation`).
4. **Validation Qualité :**
   - 80 tests unitaires et d'intégration validés (`flutter test`).
   - Analyse statique sans aucun avertissement (`dart analyze`).

---

## 5. Déploiement et CI/CD GitHub Actions

Le workflow `.github/workflows/build_apps.yml` génère automatiquement les binaires de production :
- **Android APK Release :** `dist/codebar_manager_app_release.apk`
- **Windows Release Bundle :** `codebar_manager_windows.zip`
- **Publication automatique :** Déclenchée lors de la création d'un tag git `v*` (ex: `v1.0.2`).
