FROM php:7.3-fpm-alpine

RUN apk add --no-cache $PHPIZE_DEPS imagemagick-dev \
  && pecl install apcu imagick xdebug \
  && docker-php-ext-enable apcu \
  && docker-php-ext-enable imagick \
  && docker-php-ext-enable xdebug \
  && apk del $PHPIZE_DEPS \
  && rm -rf /tmp/*

EXPOSE 9000
