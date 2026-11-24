#!/bin/sh
#
# Demostración en vivo de la presentación, en cuatro escenas.
# Corre en la PC cliente (Git Bash en Windows) con curl, websocat y psql.
#
# Antes de presentar, sin el proyector conectado:
#   cp scripts/demo.env.example demo.env     # completar con las claves reales
#   . ./demo.env                             # carga las variables (no muestra nada)
#
# Escenas:
#   sh scripts/demo.sh registro      # 1. Una familia se registra
#   sh scripts/demo.sh login         # variante: pide correo y contraseña de un usuario creado en Studio
#   sh scripts/demo.sh publicar      # 2. Quién puede publicar
#   sh scripts/demo.sh familia       # 3. El aviso llega solo (dejar abierta)
#   DEBUG=1 sh scripts/demo.sh familia   # igual, mostrando cada mensaje crudo de Realtime
#   sh scripts/demo.sh base          # 4. La base tiene portero (antes y después)
#
set -eu
: "${SB_URL:?Falta cargar demo.env}"
: "${SB_PUB:?Falta cargar demo.env}"

ESTADO="${TMPDIR:-/tmp}/demo-supabase"
mkdir -p "$ESTADO"
JSON='Content-Type: application/json'
PASS="${DEMO_PASS:-Laboratorio-2026}"

titulo() { printf '\n\033[1;32m== %s ==\033[0m\n\n' "$*"; }

case "${1:-}" in

registro)
    titulo "Escena 1: una familia se registra"
    EMAIL="mama.$(date +%H%M%S)@lab.internal"
    printf '%s' "$EMAIL" > "$ESTADO/email"

    curl -sS -o /dev/null "$SB_URL/auth/v1/signup" -H "apikey: $SB_PUB" -H "$JSON" \
        -d "{\"email\":\"$EMAIL\",\"password\":\"$PASS\"}"
    echo "Cuenta creada: $EMAIL"

    curl -sS "$SB_URL/auth/v1/token?grant_type=password" -H "apikey: $SB_PUB" -H "$JSON" \
        -d "{\"email\":\"$EMAIL\",\"password\":\"$PASS\"}" > "$ESTADO/login.json"
    sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p' "$ESTADO/login.json" > "$ESTADO/token"
    VENCE=$(sed -n 's/.*"expires_in":\([0-9]*\).*/\1/p' "$ESTADO/login.json")

    if [ -s "$ESTADO/token" ]; then
        echo "Inició sesión: recibió su pase (JWT)."
        echo "El pase vence en $VENCE segundos (una hora)."
    else
        echo "No se pudo iniciar sesión."
    fi
    ;;

login)
    titulo "Inicio de sesión de un usuario creado en Studio"
    EMAIL="${2:-}"
    CLAVE="${3:-}"
    if [ -z "$EMAIL" ]; then
        printf 'Correo: '
        IFS= read -r EMAIL
    fi
    if [ -z "$CLAVE" ]; then
        printf 'Contraseña: '
        stty -echo 2>/dev/null || true
        IFS= read -r CLAVE
        stty echo 2>/dev/null || true
        echo
    fi
    printf '%s' "$EMAIL" > "$ESTADO/email"

    curl -sS "$SB_URL/auth/v1/token?grant_type=password" -H "apikey: $SB_PUB" -H "$JSON" \
        -d "{\"email\":\"$EMAIL\",\"password\":\"$CLAVE\"}" > "$ESTADO/login.json"
    sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p' "$ESTADO/login.json" > "$ESTADO/token"
    VENCE=$(sed -n 's/.*"expires_in":\([0-9]*\).*/\1/p' "$ESTADO/login.json")
    ID=$(sed -n 's/.*"user":{"id":"\([^"]*\)".*/\1/p' "$ESTADO/login.json")

    if [ -s "$ESTADO/token" ]; then
        echo "Inició sesión: $EMAIL"
        [ -n "$ID" ] && echo "Su id de usuario: $ID"
        echo "Recibió su pase (JWT), que vence en $VENCE segundos (una hora)."
    else
        echo "No se pudo iniciar sesión. ¿El correo y la contraseña son los de Studio?"
        echo "¿Marcaste \"Auto Confirm User\" al crearlo?"
    fi
    ;;

publicar)
    titulo "Escena 2: quién puede publicar"
    [ -s "$ESTADO/token" ] || { echo "Primero correr: sh scripts/demo.sh registro"; exit 1; }
    TOKEN=$(cat "$ESTADO/token")
    AVISO="${2:-Mañana se suspenden las clases}"

    echo "Alguien SIN cuenta intenta publicar..."
    COD=$(curl -sS -o /dev/null -w '%{http_code}' "$SB_URL/rest/v1/mensajes" \
        -H "apikey: $SB_PUB" -H "$JSON" -d "{\"texto\":\"Aviso falso\"}")
    echo "  Respuesta: $COD  ->  rechazado"

    echo
    QUIEN=$(cat "$ESTADO/email" 2>/dev/null || echo "la usuaria")
    echo "$QUIEN, CON su sesión, publica: \"$AVISO\""
    COD=$(curl -sS -o /dev/null -w '%{http_code}' "$SB_URL/rest/v1/mensajes" \
        -H "apikey: $SB_PUB" -H "Authorization: Bearer $TOKEN" -H "$JSON" \
        -d "{\"texto\":\"$AVISO\"}")
    echo "  Respuesta: $COD  ->  publicado"
    ;;

familia)
    titulo "Escena 3: el celular de la familia"
    WS="$(printf '%s' "$SB_URL" | sed 's/^http/ws/')/realtime/v1/websocket?apikey=$SB_PUB&vsn=1.0.0"
    JOIN='{"topic":"realtime:mensajes","event":"phx_join","payload":{"config":{"postgres_changes":[{"event":"INSERT","schema":"public","table":"mensajes"}]}},"ref":"1","join_ref":"1"}'
    LATIDO='{"topic":"phoenix","event":"heartbeat","payload":{},"ref":"hb"}'
    echo "Conectando..."

    # Se manda la suscripción y un "latido" cada 25 s para que la conexión no se cierre.
    # Se muestran sólo la confirmación y el texto de cada aviso nuevo.
    { printf '%s\n' "$JOIN"; while :; do sleep 25; printf '%s\n' "$LATIDO"; done; } \
    | "${WEBSOCAT:-websocat}" ${WS_OPCIONES:-} "$WS" \
    | while IFS= read -r linea; do
        if [ -n "${DEBUG:-}" ]; then printf 'RAW: %s\n' "$linea"; fi
        case "$linea" in
            *"Subscribed to PostgreSQL"*) echo "Conectado: esperando avisos..." ;;
            *'"postgres_changes"'*)
                texto=$(printf '%s' "$linea" | sed -n 's/.*"texto": *"\([^"]*\)".*/\1/p')
                if [ -n "$texto" ]; then printf '\n  \033[1mNuevo aviso:\033[0m %s\n' "$texto"; fi ;;
            *'"status":"error"'*) echo "Error de Realtime: $linea" ;;
        esac
    done
    ;;

base)
    titulo "Escena 4: la base tiene portero"
    : "${PGPASSWORD:?Falta PGPASSWORD en demo.env}"
    export PGPASSWORD
    HOST=$(printf '%s' "$SB_URL" | sed 's#^[a-z]*://##; s#[:/].*##')
    echo "La compu de administración se conecta a la base..."
    if psql "postgresql://postgres.${TENANT:-labredes}@$HOST:5432/postgres?connect_timeout=5" \
         -At -c "select 'Conectada. Avisos guardados: ' || count(*) from public.mensajes;" 2>/dev/null
    then :
    else
        echo "Sin respuesta después de 5 segundos: el portero no la deja pasar."
    fi
    ;;

*)
    echo "Uso: sh scripts/demo.sh registro | login | publicar [\"texto\"] | familia | base"
    exit 1 ;;
esac
