#!/bin/sh
#
# Escena 4 de la demostración, del lado del servidor (correr en la VM por SSH).
#
#   sudo sh scripts/portero.sh sacar    # quita la PC de la lista admin_db
#   sudo sh scripts/portero.sh log      # muestra los intentos rechazados y el contador
#   sudo sh scripts/portero.sh poner    # la vuelve a agregar (¡no olvidarse!)
#
set -eu
PC="${PC:-192.168.56.1}"

case "${1:-}" in
sacar)
    nft delete element inet lab_filtro admin_db "{ $PC }"
    echo "La PC $PC ya no está en la lista de la base." ;;
poner)
    nft add element inet lab_filtro admin_db "{ $PC }"
    echo "La PC $PC volvió a la lista de la base." ;;
log)
    echo "Intentos rechazados en los últimos 5 minutos:"
    journalctl -k --since "-5 min" --no-pager | grep nft-dnat-drop \
        | sed 's/.*\(SRC=[^ ]*\).*\(DST=[^ ]*\).*\(DPT=[^ ]*\).*/  \1 \2 \3/' || echo "  (ninguno)"
    echo
    echo "Contador de la regla:"
    nft list chain inet lab_filtro hacia_contenedores | grep 'ct status dnat' ;;
*)
    echo "Uso: sudo sh scripts/portero.sh sacar | log | poner"; exit 1 ;;
esac
