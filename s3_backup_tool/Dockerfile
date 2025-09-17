ARG BUILD_FROM
FROM $BUILD_FROM
RUN apk add --no-cache aws-cli jq curl ca-certificates coreutils busybox-suid lighttpd
COPY www /www
COPY icon.png /www/icon.png
RUN chmod -R a+rx /www && find /www/cgi-bin -type f -name "*.sh" -exec chmod a+rx {} +
COPY run.sh /run.sh
RUN sed -i 's/\r$//' /run.sh \
 && sed -i '1s/^\xEF\xBB\xBF//' /run.sh \
 && chmod a+x /run.sh
CMD [ "/run.sh" ]
