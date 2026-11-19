#!/bin/sh
#
# Pruebas funcionales de la API desde el equipo cliente (requiere curl y jq).
#
# Uso:
#   export SB_PUB=sb_publishable_...                      # en el servidor: sh run.sh secrets
#   export SB_URL=http://supabase.lab.internal:8000       # fase 1
#   export SB_URL=https://supabase.lab.internal           # fase 2 (con la CA raíz instalada)
#   sh pruebas-api.sh
#
set -eu
: "${SB_URL:?Definir SB_URL}"
: "${SB_PUB:?Definir SB_PUB (clave publishable)}"

EMAIL="${EMAIL:-alumno$(date +%s)@lab.internal}"
PASS="${PASS:-Laboratorio-2026}"
JSON='Content-Type: application/json'

paso() { printf '\n==> %s\n' "$*"; }

# Decodifica una parte Base64URL de un JWT
b64url() {
    s=$(printf '%s' "$1" | tr '_-' '/+')
    case $(( ${#s} % 4 )) in
        2) s="${s}==" ;;
        3) s="${s}=" ;;
    esac
    printf '%s' "$s" | base64 -d 2>/dev/null
}

paso "1. Sin apikey: el gateway Envoy corta con 401"
curl -sS -o /dev/null -w 'HTTP %{http_code}\n' "$SB_URL/rest/v1/mensajes"

paso "2. Estado de Auth (GoTrue)"
curl -sS "$SB_URL/auth/v1/health" -H "apikey: $SB_PUB"; echo

paso "3. Registro de $EMAIL"
curl -sS "$SB_URL/auth/v1/signup" -H "apikey: $SB_PUB" -H "$JSON" \
    -d "{\"email\":\"$EMAIL\",\"password\":\"$PASS\"}" \
    | jq '{usuario: (.user.id // .id), devuelve_sesion: (.access_token != null)}'

paso "4. Login con contraseña (grant_type=password)"
TOKEN=$(curl -sS "$SB_URL/auth/v1/token?grant_type=password" -H "apikey: $SB_PUB" -H "$JSON" \
    -d "{\"email\":\"$EMAIL\",\"password\":\"$PASS\"}" | jq -r .access_token)
echo "Encabezado del JWT:"; b64url "$(echo "$TOKEN" | cut -d. -f1)" | jq .
echo "Carga (claims):";     b64url "$(echo "$TOKEN" | cut -d. -f2)" | jq '{iss, sub, aud, role, exp, iat, email, aal, session_id}'

paso "5. Insertar un mensaje como usuario autenticado (esperado: 201)"
curl -sS -w '\nHTTP %{http_code}\n' "$SB_URL/rest/v1/mensajes" \
    -H "apikey: $SB_PUB" -H "Authorization: Bearer $TOKEN" -H "$JSON" \
    -H 'Prefer: return=representation' \
    -d "{\"texto\":\"Hola desde $(hostname) a las $(date +%H:%M:%S)\"}"

paso "6. Leer como anon, sin sesión (esperado: 200 con la lista)"
curl -sS "$SB_URL/rest/v1/mensajes?select=id,texto,creado_en&order=id.desc&limit=3" \
    -H "apikey: $SB_PUB" | jq .

paso "7. Insertar como anon (esperado: 401, permiso denegado por GRANT)"
curl -sS -w '\nHTTP %{http_code}\n' "$SB_URL/rest/v1/mensajes" \
    -H "apikey: $SB_PUB" -H "$JSON" -d '{"texto":"no deberia entrar"}'

paso "8. Edge Function hello"
curl -sS "$SB_URL/functions/v1/hello" -H "apikey: $SB_PUB"; echo

paso "9. JWKS público (clave EC con la que se verifican las sesiones)"
curl -sS "$SB_URL/auth/v1/.well-known/jwks.json" | jq '.keys[] | {kty, crv, alg, kid}'
