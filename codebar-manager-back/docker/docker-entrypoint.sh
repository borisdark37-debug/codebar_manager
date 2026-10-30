#!/bin/sh
set -e

echo "=== Démarrage du conteneur CodeBar Manager Backend ==="

# Configuration dynamique du port d'écoute (Crucial pour Render, Koyeb, Cloud Run, VPS)
LISTEN_PORT="${PORT:-8080}"
echo "Configuration de Nginx pour écouter sur le port: $LISTEN_PORT"
if [ -f /etc/nginx/nginx.conf.template ]; then
    sed "s/__PORT__/$LISTEN_PORT/g" /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf
else
    sed -i "s/__PORT__/$LISTEN_PORT/g" /etc/nginx/nginx.conf
fi

# Permissions sur les répertoires d'écriture
echo "Application des permissions sur storage et bootstrap/cache..."
mkdir -p /var/www/html/storage/framework/sessions \
         /var/www/html/storage/framework/views \
         /var/www/html/storage/framework/cache \
         /var/www/html/storage/logs \
         /var/www/html/bootstrap/cache

chown -R www-data:www-data /var/www/html/storage /var/www/html/bootstrap/cache
chmod -R 775 /var/www/html/storage /var/www/html/bootstrap/cache

# S'assurer de la présence d'un fichier .env pour persister la clé si non injectée
if [ ! -f /var/www/html/.env ]; then
    touch /var/www/html/.env
fi

# Génération automatique d'une clé d'application si absente
if [ -z "$APP_KEY" ]; then
    echo "APP_KEY n'est pas définie. Génération d'une nouvelle clé d'application..."
    php artisan key:generate --force || true
fi

# Exécution des migrations si activé (par défaut: activé)
if [ "${AUTO_MIGRATE:-true}" != "false" ]; then
    echo "Exécution des migrations de base de données (PostgreSQL Aiven)..."
    php artisan migrate --force || echo "Avertissement: Impossible d'exécuter les migrations (vérifiez les identifiants BD)."
fi

# Optimisations du cache en production
if [ "${APP_ENV:-production}" = "production" ]; then
    echo "Mise en cache des configurations, routes et vues..."
    php artisan config:cache || true
    php artisan route:cache || true
    php artisan view:cache || true
fi

echo "Lancement des services via Supervisord..."
exec supervisord -c /etc/supervisor/conf.d/supervisord.conf
