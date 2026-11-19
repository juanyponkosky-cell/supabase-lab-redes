#!/bin/sh
#
# Respaldo del proyecto Supabase autoalojado. Ejecutar con sudo en el servidor:
#   sudo sh backup.sh /home/<usuario>/supabase-project
#
# Genera en <proyecto>/backups/<fecha>/ (carpeta ignorada por git):
#   public.dump      respaldo lógico en caliente del esquema public (pg_dump -Fc)
#   db-data.tgz      copia física en frío del directorio de datos de Postgres
#   db-config.tgz    volumen db-config (clave raíz de pgsodium; sin él no se descifra Vault)
#   storage.tgz      archivos subidos a Storage
#   env.gpg          .env cifrado con una contraseña (AES-256)
#   SHA256SUMS       sumas de verificación
#
# La copia física detiene el stack unos segundos. Llevar la carpeta resultante
# fuera del servidor (regla 3-2-1: 3 copias, 2 medios, 1 fuera del sitio).
#
set -eu

PROY="${1:-$PWD}"
cd "$PROY"
[ -f docker-compose.yml ] || { echo "ERROR: $PROY no es un proyecto Supabase" >&2; exit 1; }

FECHA=$(date +%Y%m%d-%H%M%S)
DEST="backups/$FECHA"
mkdir -p "$DEST"
chmod 700 backups "$DEST"

echo "==> 1/4 Respaldo lógico del esquema public (en caliente)"
docker compose exec -T db pg_dump -U postgres -d postgres -n public -Fc > "$DEST/public.dump"

echo "==> 2/4 Copia física en frío: se detiene el stack"
docker compose stop
tar -czf "$DEST/db-data.tgz" volumes/db/data
tar -czf "$DEST/storage.tgz" volumes/storage
VOL_CFG=$(docker volume inspect -f '{{.Mountpoint}}' supabase_db-config)
tar -czf "$DEST/db-config.tgz" -C "$VOL_CFG" .
docker compose start

echo "==> 3/4 Configuración: .env cifrado (pide una contraseña)"
gpg --symmetric --cipher-algo AES256 --output "$DEST/env.gpg" .env

echo "==> 4/4 Sumas de verificación"
( cd "$DEST" && sha256sum public.dump db-data.tgz db-config.tgz storage.tgz env.gpg > SHA256SUMS )

echo "Respaldo completo en $PROY/$DEST"
ls -lh "$DEST"
