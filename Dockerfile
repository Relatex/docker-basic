FROM php:8.4-fpm

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Europe/Berlin

# ============================================
# System-Pakete und Build-Abhaengigkeiten
# ============================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Basis-Tools
    git \
    unzip \
    nano \
    curl \
    wget \
    # Supervisor fuer Queue-Worker
    supervisor \
    # Node.js Voraussetzung
    gnupg \
    # ImageMagick
    imagemagick \
    libmagickwand-dev \
    # wkhtmltopdf Abhaengigkeiten
    fontconfig \
    libxrender1 \
    xfonts-75dpi \
    xfonts-base \
    # Build-Abhaengigkeiten fuer PHP-Extensions
    libldap2-dev \
    libzip-dev \
    libpng-dev \
    libjpeg62-turbo-dev \
    libfreetype6-dev \
    libwebp-dev \
    libicu-dev \
    libxml2-dev \
    libcurl4-openssl-dev \
    libonig-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ============================================
# wkhtmltopdf (nicht in Trixie Repos, manuell installieren)
# ============================================
RUN curl -fsSL -o /tmp/wkhtmltox.deb \
        https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.bookworm_amd64.deb \
    && apt-get update \
    && apt-get install -y --no-install-recommends /tmp/wkhtmltox.deb \
    && rm /tmp/wkhtmltox.deb \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ============================================
# Node.js 20 LTS
# ============================================
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ============================================
# PHP-Extensions (via docker-php-ext)
# ============================================
RUN docker-php-ext-configure gd \
        --with-freetype \
        --with-jpeg \
        --with-webp \
    && docker-php-ext-install -j$(nproc) \
        pdo_mysql \
        mysqli \
        ldap \
        gd \
        mbstring \
        xml \
        curl \
        zip \
        bcmath \
        intl \
        opcache \
        pcntl \
        exif

# ============================================
# PHP-Extensions (via PECL)
# ============================================
RUN pecl install imagick redis \
    && docker-php-ext-enable imagick redis

# ============================================
# Composer
# ============================================
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# ============================================
# User-Setup (WSL-Kompatibilitaet)
# Wird durch setup.sh dynamisch gesetzt
# ============================================
ARG WWWUSER=1000
ARG WWWGROUP=1000
RUN usermod -u ${WWWUSER} www-data \
    && groupmod -g ${WWWGROUP} www-data

# ============================================
# Supervisor-Konfiguration
# ============================================
RUN mkdir -p /var/log/supervisor \
    && chown -R ${WWWUSER}:${WWWGROUP} /var/log/supervisor \
    && chown -R ${WWWUSER}:${WWWGROUP} /var/run
COPY supervisor/laravel-worker.conf /etc/supervisor/conf.d/laravel-worker.conf

# ============================================
# Arbeitsverzeichnis
# ============================================
WORKDIR /var/www/html

EXPOSE 9000

# Supervisor startet php-fpm + queue worker
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf"]
