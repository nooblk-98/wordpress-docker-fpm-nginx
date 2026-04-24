FROM wordpress:php8.3-fpm-alpine

RUN apk add --no-cache \
    imagemagick \
    imagemagick-dev \
    $PHPIZE_DEPS \
    && pecl install imagick \
    && docker-php-ext-enable imagick \
    && apk del $PHPIZE_DEPS

RUN docker-php-ext-install \
    mysqli \
    pdo \
    pdo_mysql \
    exif \
    opcache

COPY php.ini /usr/local/etc/php/conf.d/custom.ini

RUN chown -R www-data:www-data /var/www/html

EXPOSE 9000
