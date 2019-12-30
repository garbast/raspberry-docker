FROM php:7.3-fpm-alpine

RUN apk add --no-cache $PHPIZE_DEPS freetype libpng libjpeg-turbo freetype-dev libjpeg-turbo-dev libpng-dev imagemagick-dev \
  && pecl install apcu imagick xdebug \
  && docker-php-ext-configure gd \
       --with-gd \
       --with-freetype-dir=/usr/include/ \
       --with-png-dir=/usr/include/ \
       --with-jpeg-dir=/usr/include/ \
  && docker-php-ext-install mysqli gd \
  && apk del $PHPIZE_DEPS freetype-dev libjpeg-turbo-dev libpng-dev imagemagick-dev \
  && rm -rf /tmp/*

# DO NOT add docker-php-ext-enable calls here, because the conf.d folder is overridden with a volumn

EXPOSE 9000
