FROM ruby:2.7-alpine

ENV BUILD_PACKAGES ruby-dev build-base sqlite-dev

RUN apk update \
  && apk add --no-cache $BUILD_PACKAGES sqlite-libs \
  && gem install mailcatcher \
  && apk del $BUILD_PACKAGES \
  && rm -rf /tmp/*

EXPOSE 1025 1080

COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/bin/sh", "/entrypoint.sh"]
