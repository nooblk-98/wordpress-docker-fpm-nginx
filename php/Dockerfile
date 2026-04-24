ARG PHP_VERSION=8.3
FROM wordpress:php${PHP_VERSION}-fpm-alpine

ADD https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions /usr/local/bin/

RUN chmod +x /usr/local/bin/install-php-extensions \
    && install-php-extensions imagick redis

RUN docker-php-ext-install \
    mysqli \
    pdo \
    pdo_mysql \
    exif \
    opcache

COPY php.ini /usr/local/etc/php/conf.d/custom.ini

RUN chown -R www-data:www-data /var/www/html

EXPOSE 9000
