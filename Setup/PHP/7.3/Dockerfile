FROM php:7.3-fpm-alpine

RUN apk add --no-cache $PHPIZE_DEPS \
  && pecl install xdebug apcu \
  && docker-php-ext-enable xdebug \
  && docker-php-ext-enable apcu \
  && apk del $PHPIZE_DEPS \
  && rm -rf /tmp/*

EXPOSE 9000
