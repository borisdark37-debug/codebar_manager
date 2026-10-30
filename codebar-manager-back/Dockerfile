# ==============================================================================
# Dockerfile Production Multi-Plateforme - CodeBar Manager Backend (Laravel 11)
# Optimisé pour Aiven PostgreSQL, Render.com, Koyeb, Docker Compose & VPS
# ==============================================================================
FROM php:8.4-fpm-alpine

LABEL maintainer="CodeBar Manager Team"
LABEL description="Production Docker image for CodeBar Manager Laravel Backend"

# Installation des dépendances système requises (Nginx, Supervisor, PostgreSQL, GD, Zip)
RUN apk add --no-cache \
    nginx \
    supervisor \
    curl \
    bash \
    zip \
    unzip \
    libzip-dev \
    postgresql-dev \
    libpng-dev \
    libjpeg-turbo-dev \
    freetype-dev \
    oniguruma-dev \
    icu-dev

# Configuration et installation des extensions PHP
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) \
        pdo_pgsql \
        pgsql \
        mbstring \
        bcmath \
        zip \
        opcache \
        pcntl \
        gd \
        intl

# Configuration OPcache recommandée pour Laravel en production
RUN { \
        echo 'opcache.memory_consumption=128'; \
        echo 'opcache.interned_strings_buffer=8'; \
        echo 'opcache.max_accelerated_files=10000'; \
        echo 'opcache.revalidate_freq=0'; \
        echo 'opcache.validate_timestamps=0'; \
        echo 'opcache.save_comments=1'; \
        echo 'opcache.fast_shutdown=1'; \
    } > /usr/local/etc/php/conf.d/opcache-recommended.ini

# Copie de Composer depuis l'image officielle
COPY --from=composer:2.7 /usr/bin/composer /usr/bin/composer

# Répertoire de travail
WORKDIR /var/www/html

# Optimisation du cache Docker pour Composer
COPY composer.json composer.lock ./
RUN composer install --no-dev --no-scripts --no-autoloader --prefer-dist --no-interaction --ignore-platform-reqs

# Copie intégrale de l'application
COPY . .

# Finalisation de l'autoloader optimisé
RUN composer dump-autoload --optimize --no-dev --no-interaction --ignore-platform-reqs

# Configurations Nginx, Supervisor et Entrypoint
COPY docker/nginx.conf /etc/nginx/nginx.conf
COPY docker/nginx.conf /etc/nginx/nginx.conf.template
COPY docker/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY docker/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN sed -i 's/\r$//' /usr/local/bin/docker-entrypoint.sh \
    && chmod +x /usr/local/bin/docker-entrypoint.sh

# Permissions d'écriture pour Nginx et PHP-FPM
RUN chown -R www-data:www-data /var/www/html/storage /var/www/html/bootstrap/cache \
    && chmod -R 775 /var/www/html/storage /var/www/html/bootstrap/cache

# Port par défaut exposé
EXPOSE 8080

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
