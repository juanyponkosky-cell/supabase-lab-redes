#!/bin/sh
#
# Restauración completa desde una carpeta generada por backup.sh. Ejecutar con sudo:
#   sudo sh restaurar.sh /home/<usuario>/supabase-project /ruta/al/backup/20261120-103000
#
# Requisitos: el proyecto debe tener la MISMA versión de Supabase (y por lo tanto
# la misma versión mayor de Postgres, 17) que cuando se hizo el respaldo.
#
# Para restaurar sólo los datos de la aplicación (sin tocar el resto):
#   docker compose exec -T db pg_restore -U postgres -d postgres --clean --if-exists < public.dump
#
set -eu

PROY="$1"
BK="$(cd "$2" && pwd)"
cd "$PROY"

echo "==> Verificando sumas"
( cd "$BK" && sha256sum -c SHA256SUMS )

echo "==> Deteniendo el stack"
docker compose down

echo "==> Guardando los datos actuales por las dudas"
ANTES="volumes/db/data.antes-$(date +%Y%m%d-%H%M%S)"
[ -d volumes/db/data ] && mv volumes/db/data "$ANTES"
[ -d volumes/storage ] && mv volumes/storage "volumes/storage.antes-$(date +%Y%m%d-%H%M%S)"

echo "==> Restaurando datos de Postgres, Storage y volumen db-config"
tar -xzf "$BK/db-data.tgz"
tar -xzf "$BK/storage.tgz"
docker volume create supabase_db-config > /dev/null
VOL_CFG=$(docker volume inspect -f '{{.Mountpoint}}' supabase_db-config)
tar -xzf "$BK/db-config.tgz" -C "$VOL_CFG"

echo "==> Restaurando .env (pide la contraseña del respaldo)"
cp .env ".env.antes-$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
gpg --decrypt --output .env "$BK/env.gpg"
chmod 600 .env

echo "==> Iniciando"
sh run.sh start
docker compose ps
