ARG BUILD_FROM
FROM $BUILD_FROM
RUN apk add --no-cache aws-cli jq curl ca-certificates coreutils busybox-suid lighttpd dos2unix
COPY www /www
COPY icon.png /www/icon.png
RUN chmod -R a+rx /www \
 && find /www -type f -name "*.sh" -exec dos2unix -q {} +
# S6-Services via rootfs verwenden, keine CMD-Überschreibung mehr
COPY rootfs / 
RUN find /etc/services.d -type f -name "run" -exec dos2unix -q {} + \
 && chmod a+rx /etc/services.d/*/run
COPY run.sh /run.sh
RUN dos2unix -q /run.sh \
 && chmod a+x /run.sh
RUN set -e; \
  for f in /run.sh /etc/services.d/*/run $(find /www -type f -name "*.sh" 2>/dev/null); do \
    [ -f "$f" ] || continue; \
    if [ "$(head -c 3 "$f" | od -An -t x1 | tr -d ' \n')" = "efbbbf" ]; then \
      tail -c +4 "$f" > "$f.tmp" && mv "$f.tmp" "$f"; \
    fi; \
  done
