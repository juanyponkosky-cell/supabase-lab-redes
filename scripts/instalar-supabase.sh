#!/bin/sh
#
# Instala la configuración oficial de Supabase autoalojado, fijada en una versión,
# genera todos los secretos y aplica los cambios del laboratorio.
# Equivale a la "instalación manual" de la documentación oficial.
#
# Requisitos: Docker Engine + plugin compose, git, openssl, jq (y node >= 16 o Docker
# para add-new-auth-keys.sh). Ejecutar como un usuario del grupo docker.
#
# Uso: sh scripts/instalar-supabase.sh
#      VERSION=self-hosted/v0.8.4 DIR=/opt/supabase-project sh scripts/instalar-supabase.sh
#
set -eu

VERSION="${VERSION:-self-hosted/v0.8.4}"
DIR="${DIR:-$HOME/supabase-project}"
REPO_LAB="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$(mktemp -d)"
trap 'rm -rf "$SRC"' EXIT

if [ -e "$DIR" ]; then
    echo "ERROR: $DIR ya existe. Elegir otro DIR o borrarlo con reset.sh." >&2
    exit 1
fi

echo "==> Descargando sólo docker/ de supabase/supabase en $VERSION"
git clone --filter=blob:none --no-checkout --depth=1 --quiet --branch "$VERSION" \
    https://github.com/supabase/supabase "$SRC/supabase"
( cd "$SRC/supabase" && git sparse-checkout init --cone && git sparse-checkout set docker && git checkout --quiet )

echo "==> Creando el proyecto en $DIR"
mkdir -p "$DIR"
cp -rf "$SRC/supabase/docker/." "$DIR/"
cd "$DIR"
cp .env.example .env
chmod 600 .env
printf 'ref=%s\n' "$VERSION" > .supabase-version

echo "==> Generando secretos y claves heredadas (HS256)"
sh utils/generate-keys.sh --update-env > /dev/null

echo "==> Generando par EC P-256, JWKS y claves sb_publishable / sb_secret"
sh utils/add-new-auth-keys.sh --update-env > /dev/null

echo "==> Aplicando los cambios del laboratorio (supabase/env.lab.example)"
grep -E '^[A-Z_]+=' "$REPO_LAB/supabase/env.lab.example" | while IFS='=' read -r clave valor; do
    if grep -q "^${clave}=" .env; then
        sed -i "s|^${clave}=.*$|${clave}=${valor}|" .env
    else
        printf '%s=%s\n' "$clave" "$valor" >> .env
    fi
done
rm -f .env.old docker-compose.yml.old

echo "==> Caddyfile del laboratorio (usado en la fase 2)"
cp "$REPO_LAB/supabase/caddy/Caddyfile" volumes/proxy/caddy/Caddyfile
mkdir -p volumes/proxy/caddy/certs

echo "==> Descargando imágenes"
docker compose pull --quiet

echo ""
echo "Listo. Siguientes pasos:"
echo "  cd $DIR"
echo "  sh run.sh secrets      # ver claves y contraseñas generadas"
echo "  sh run.sh start        # fase 1: HTTP en el puerto 8000"
