FROM postgres:17.9-alpine

# restic для бэкапа, bash для скрипта, tini для PID-1 reaping.
# crond уже в busybox (часть alpine base), отдельно ставить не нужно.
RUN apk add --no-cache restic bash tini

COPY --chmod=0755 backup-now /usr/local/bin/backup-now
COPY --chmod=0644 crontab /var/spool/cron/crontabs/root

# crond -f (foreground) + -L /dev/stdout (log в stdout для docker logs).
# Запускаем как root (по дефолту в этом stage'е) — иначе busybox crond
# не найдёт /var/spool/cron/crontabs/root.
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["crond", "-f", "-L", "/dev/stdout"]
