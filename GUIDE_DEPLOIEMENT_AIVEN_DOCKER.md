# Guide Complet de Déploiement : Aiven PostgreSQL, Docker & CI/CD GitHub Actions

Ce guide vous accompagne pas à pas pour déployer l'architecture de production complète de **CodeBar Manager** :
1. **Base de données cloud managée PostgreSQL (Plan Gratuit 1 Go / Free Tier)** sur **Aiven.io**.
2. **Backend Laravel 11 conteneurisé (Docker)** déployé sur **Render.com** (ou **Koyeb** / VPS).
3. **Exécution automatique des migrations** et synchronisation en direct avec l'application Flutter.
4. **Génération automatisée des applications Android (.apk) et Windows (.exe + DLLs)** via **GitHub Actions**.

---

## Sommaire

1. [Étape 1 : Création de la Base PostgreSQL sur Aiven.io](#étape-1--création-de-la-base-postgresql-sur-aivenio)
2. [Étape 2 : Déploiement du Backend Conteneurisé sur Render.com](#étape-2--déploiement-du-backend-conteneurisé-sur-rendercom)
3. [Étape 3 : Alternative Déploiement sur Koyeb ou VPS Docker](#étape-3--alternative-déploiement-sur-koyeb-ou-vps-docker)
4. [Étape 4 : Configuration de l'Application Flutter](#étape-4--configuration-de-lapplication-flutter)
5. [Étape 5 : Compilation & Récupération des Binaires (.apk & .exe) via GitHub Actions](#étape-5--compilation--récupération-des-binaires-apk--exe-via-github-actions)
6. [Maintenance, Sauvegardes & Diagnostic](#maintenance-sauvegardes--diagnostic)

---

## Étape 1 : Création de la Base PostgreSQL sur Aiven.io

Aiven propose un plan gratuit à vie (**Free Plan**) pour PostgreSQL incluant 1 Go de stockage SSD, 1 vCPU et 1 Go de RAM, avec sauvegardes automatiques et chiffrement TLS/SSL obligatoire.

### 1.1 Inscription et initialisation
1. Rendez-vous sur [console.aiven.io](https://console.aiven.io) et créez un compte (gratuit, aucune carte bancaire requise pour le plan Free).
2. Cliquez sur **"Create Service"**.
3. Choisissez **PostgreSQL**.
4. Dans la sélection du plan, sélectionnez **Free Plan** (1 CPU, 1 GB RAM, 1 GB storage).
5. Sélectionnez le fournisseur de cloud et la région la plus proche de vos utilisateurs (ex: `AWS - Frankfurt / eu-central-1` ou `GCP - Belgium`).
6. Nommez votre service (ex: `codebar-postgres`) et validez par **"Create Service"**.
7. Patientez environ 2 à 3 minutes jusqu'à ce que le statut passe à **"RUNNING"**.

### 1.2 Récupération des identifiants de connexion
Sur la page **Overview** de votre service Aiven :
- Repérez la section **Connection information**.
- Vous disposez de deux formats :
  
  **Format 1 : Service URI complète**
  ```text
  postgres://avnadmin:VOTRE_MOT_DE_PASSE@codebar-postgres-mon-projet.aivencloud.com:12345/defaultdb?sslmode=require
  ```

  **Format 2 : Paramètres individuels**
  - **Host** : `codebar-postgres-mon-projet.aivencloud.com`
  - **Port** : `12345`
  - **User** : `avnadmin`
  - **Password** : `(Cliquez sur afficher le mot de passe)`
  - **Database** : `defaultdb`
  - **SSL Mode** : `require`

> [!TIP]
> Conservez ces identifiants de côté. Le backend Laravel supporte nativement la variable globale `DATABASE_URL` ou les variables découpées (`DB_HOST`, `DB_PORT`, etc.).

---

## Étape 2 : Déploiement du Backend Conteneurisé sur Render.com

Render.com offre l'hébergement de conteneurs Docker avec gestion TLS automatique (HTTPS gratuit) et déploiement continu à chaque `git push`.

### 2.1 Préparation du dépôt Git
Assurez-vous que votre projet est poussé sur votre compte GitHub (public ou privé).
Le dossier `codebar-manager-back` contient :
- Le fichier `Dockerfile` de production (PHP 8.3 FPM + Nginx + OPcache + extensions PostgreSQL).
- Le script `docker/docker-entrypoint.sh` qui exécute automatiquement `php artisan migrate --force` et met en cache la configuration.

### 2.2 Création du Web Service sur Render
1. Connectez-vous sur [dashboard.render.com](https://dashboard.render.com).
2. Cliquez sur **"New +"** puis sélectionnez **"Web Service"**.
3. Connectez votre dépôt GitHub contenant le projet.
4. Configurez les paramètres :
   - **Name** : `codebar-manager-backend`
   - **Region** : Choisissez la même région qu'Aiven (ex: Frankfurt EU) pour minimiser la latence réseau.
   - **Branch** : `main` ou `master`
   - **Root Directory** : `codebar-manager-back` *(si vous avez poussé le monorepo `codebar_manager_full`)*, ou laissez vide si vous avez poussé le dossier backend directement.
   - **Runtime** : **Docker**
   - **Instance Type** : `Free` ou `Starter`

### 2.3 Définition des Variables d'Environnement
Dans l'onglet **"Environment"** du Web Service sur Render, ajoutez les variables suivantes :

| Clé | Valeur d'exemple | Commentaire |
| :--- | :--- | :--- |
| `APP_NAME` | `CodeBar Manager` | Nom de l'application |
| `APP_ENV` | `production` | Mode production |
| `APP_DEBUG` | `false` | Désactive les traces d'erreur sensibles |
| `APP_KEY` | `base64:AbCdEfGh...` | Clé générée via `php artisan key:generate` |
| `APP_URL` | `https://codebar-manager-backend.onrender.com` | L'URL fournie par Render |
| `DATABASE_URL` | `postgres://avnadmin:...@...aivencloud.com:PORT/defaultdb?sslmode=require` | L'URI Aiven complète |
| `DB_CONNECTION` | `pgsql` | Pilote PostgreSQL |
| `DB_SSLMODE` | `require` | Chiffrement SSL imposé par Aiven |
| `AUTO_MIGRATE` | `true` | Exécute les migrations automatiquement au démarrage |
| `SESSION_DRIVER` | `database` | Stocke les sessions en base de données |
| `CACHE_STORE` | `database` | Cache applicatif en base de données |
| `LOG_CHANNEL` | `stderr` | Émission des logs sur la console Render |

> [!NOTE]
> Render configure automatiquement la variable `PORT`. Le script `docker-entrypoint.sh` s'adapte automatiquement pour faire écouter Nginx sur ce port dynamique.

### 2.4 Lancement & Validation
1. Cliquez sur **"Create Web Service"**.
2. Suivez le flux de logs dans la console Render :
   - Construction de l'image Docker (téléchargement PHP 8.3, compilation pdo_pgsql, installation de composer).
   - Lancement de `docker-entrypoint.sh`.
   - Exécution des migrations : `Running database migrations... Migrating: 2026_10_24_... done`.
   - Démarrage de PHP-FPM et Nginx via Supervisord.
3. Dès que le statut affiche **"Live"**, testez l'endpoint de diagnostic santé dans votre navigateur :
   ```text
   https://codebar-manager-backend.onrender.com/api/health
   ```
   Vous devez obtenir la réponse JSON suivante :
   ```json
   {
     "status": "ok",
     "timestamp": "2026-10-28T...",
     "database": "connected"
   }
   ```

---

## Étape 3 : Alternative Déploiement sur Koyeb ou VPS Docker

### 3.1 Déploiement sur Koyeb
1. Connectez-vous sur [app.koyeb.com](https://app.koyeb.com).
2. Créez une nouvelle application **"GitHub"** ou **"Docker"**.
3. Définissez `codebar-manager-back` en racine.
4. Renseignez les variables d'environnement listées dans le tableau précédent.
5. Koyeb mappe automatiquement le port 8080 exposé par le conteneur.

### 3.2 Déploiement sur un VPS avec Docker Compose
Si vous disposez d'un serveur Linux (Ubuntu/Debian) avec Docker installé :
```bash
# 1. Cloner le projet
git clone https://github.com/votre-nom/codebar_manager.git
cd codebar_manager/codebar-manager-back

# 2. Configurer le fichier .env
cp .env.production.example .env
nano .env # Renseignez vos identifiants Aiven et générez APP_KEY

# 3. Lancer le conteneur en arrière-plan
docker compose up -d --build

# 4. Vérifier les logs et les migrations
docker compose logs -f backend
```

---

## Étape 4 : Configuration de l'Application Flutter

Une fois votre backend déployé et joignable publiquement, configurez l'application cliente Flutter pour synchroniser les données avec le cloud.

### 4.1 Configuration de l'URL d'API dans Flutter
Deux options s'offrent à vous :

**Option A (Recommandée - Sans modifier le code source) : Injection à la compilation**
Passez l'URL publique de votre backend via le drapeau `--dart-define` :
```bash
# Pour Android APK :
flutter build apk --release --dart-define=API_BASE_URL=https://codebar-manager-backend.onrender.com/api

# Pour Windows :
flutter build windows --release --dart-define=API_BASE_URL=https://codebar-manager-backend.onrender.com/api
```

**Option B : Modification du fichier centralisé `api_config.dart`**
Ouvrez le fichier `lib/core/config/api_config.dart` et adaptez l'URL par défaut :
```dart
// lib/core/config/api_config.dart
static String get baseUrl {
  const envUrl = String.fromEnvironment('API_BASE_URL');
  if (envUrl.isNotEmpty) return envUrl;

  return 'https://codebar-manager-backend.onrender.com/api';
}
```

### 4.2 Compression automatique des images intégrée
- Dès l'import d'une photo de produit (via caméra ou galerie) ou lors de l'enregistrement en base locale Isar, l'utilitaire `ImageCompressionService` :
  - Redimensionne la résolution à **1024x1024 px max**.
  - Compresse la qualité à **JPEG 75%**.
  - Réduit le poids d'environ **70% à 85%** (une image de 4 Mo passe à ~80 Ko).
- L'empreinte de la base de données Aiven (1 Go gratuit) est ainsi préservée : vous pouvez stocker plus de **12 000 produits avec photos** sur le quota gratuit sans saturation.

---

## Étape 5 : Compilation & Récupération des Binaires (.apk & .exe) via GitHub Actions

Le workflow automatisé `.github/workflows/build_apps.yml` compile simultanément les versions Android et Windows à chaque validation de code.

### 5.1 Déclenchement du build
Le pipeline se déclenche automatiquement dans deux cas :
1. **À chaque push sur `main` ou `master`** : génération des artefacts de test.
2. **Sur création d'un tag Git de version (ex: `git tag v1.0.0 && git push origin v1.0.0`)** : création automatique d'une **Release GitHub** avec fichiers joints prêts au téléchargement.
3. **Manuellement** : depuis l'onglet **"Actions"** sur GitHub, sélectionnez le workflow `Build & Package Flutter Apps` et cliquez sur **"Run workflow"**.

### 5.2 Structure du Pipeline CI/CD

```mermaid
graph TD
    A[Git Push / Tag v*] --> B[Job 1: Ubuntu - Build Android]
    A --> C[Job 2: Windows - Build Windows]
    B --> D[flutter build apk --release]
    C --> E[flutter build windows --release]
    E --> F[Compress-Archive -> codebar_manager_windows.zip]
    D --> G[Upload Artifacts: codebar_manager_android_apk]
    F --> H[Upload Artifacts: codebar_manager_windows_exe]
    G --> I{Est-ce un Tag v* ?}
    H --> I
    I -- Oui --> J[Création automatique GitHub Release]
```

### 5.3 Récupération des binaires compilés
1. Rendez-vous sur votre dépôt GitHub, onglet **"Actions"**.
2. Cliquez sur la dernière exécution du workflow.
3. En bas de la page, dans la section **Artifacts** :
   - `codebar_manager_android_apk` : Contient `codebar_manager_app_release.apk` installable directement sur tout smartphone ou terminal Android.
   - `codebar_manager_windows_exe` : Contient l'archive `codebar_manager_windows.zip` regroupant l'exécutable `codebar_manager_app.exe` et l'ensemble de ses bibliothèques DLL Windows nécessaires.
4. Si vous avez poussé un tag `v1.0.0`, rendez-vous directement dans la section **Releases** de votre dépôt pour télécharger les fichiers en un clic.

---

## Maintenance, Sauvegardes & Diagnostic

### Consultation des logs en direct
- **Render** : Rendez-vous dans le tableau de bord de votre Web Service > Onglet **Logs**.
- **Docker CLI** :
  ```bash
  docker logs -f codebar_manager_backend
  ```

### Réinitialisation ou re-migration manuelle
Si vous souhaitez forcer une ré-exécution des migrations :
```bash
# Dans le shell Render ou en conteneur Docker
php artisan migrate:status
php artisan migrate --force
```

### Sauvegardes Aiven
- Aiven effectue des sauvegardes automatiques en continu (Point-in-Time Recovery).
- Depuis la console Aiven, accédez à l'onglet **Backups** pour restaurer la base à n'importe quelle minute des derniers jours.
