#!/bin/sh
#
# Capturas de tráfico en el servidor (tcpdump). Ejecutar con sudo.
# Los .pcap se abren después en Wireshark.
#
# Uso: sudo sh capturas.sh externa   # tráfico del cliente por la red del laboratorio
#      sudo sh capturas.sh interna   # tráfico entre contenedores (bridge de Docker)
#      sudo sh capturas.sh db        # protocolo de PostgreSQL hacia Supavisor
#
# Cortar cada captura con Ctrl+C después de correr la prueba en el cliente.
#
set -eu

IF_LAB="${IF_LAB:-enp0s8}"
CLIENTE="${CLIENTE:-192.168.56.20}"

# Con sudo, $HOME pasa a ser /root: se usa la carpeta del usuario que llamó a sudo
USUARIO="${SUDO_USER:-$(id -un)}"
DEST="${DEST:-$(getent passwd "$USUARIO" | cut -d: -f6)/capturas}"
mkdir -p "$DEST"
FECHA=$(date +%Y%m%d-%H%M%S)

# Al cortar con Ctrl+C, los .pcap quedan a nombre del usuario (para copiarlos con scp)
trap 'chown -R "$USUARIO": "$DEST"' EXIT INT TERM

# -Z root: en Ubuntu tcpdump baja a un usuario sin privilegios antes de crear
# el archivo y falla con "Permission denied"; así lo crea como root.
TCPDUMP="tcpdump -Z root -s 0"

case "${1:-}" in
    externa)
        # DNS + HTTP (8000) + HTTPS (80/443) entre el cliente y el servidor
        $TCPDUMP -i "$IF_LAB" -w "$DEST/externa-$FECHA.pcap" \
            "host $CLIENTE and (port 53 or port 80 or port 443 or port 8000)"
        ;;
    interna)
        # Bridge de la red supabase_default: Caddy/Envoy hacia los servicios y servicios hacia Postgres
        BR="br-$(docker network inspect -f '{{.Id}}' supabase_default | cut -c1-12)"
        echo "Capturando en $BR"
        $TCPDUMP -i "$BR" -w "$DEST/interna-$FECHA.pcap" \
            "tcp port 8000 or tcp port 3000 or tcp port 9999 or tcp port 4000 or tcp port 5000 or tcp port 5432"
        ;;
    db)
        # Protocolo de PostgreSQL entre el cliente y Supavisor (sesión 5432, transacción 6543)
        $TCPDUMP -i "$IF_LAB" -w "$DEST/db-$FECHA.pcap" \
            "host $CLIENTE and (tcp port 5432 or tcp port 6543)"
        ;;
    *)
        echo "Uso: sudo sh $0 externa|interna|db" >&2
        exit 1
        ;;
esac
