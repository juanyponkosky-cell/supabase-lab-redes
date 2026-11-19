#!/bin/sh
#
# PKI del laboratorio (mismo esquema que el TP6): CA raíz -> CA intermedia -> certificado del servidor.
# Genera en ./salida:
#   ca-raiz.crt            -> se instala como confiable en los clientes
#   ca-intermedia.crt
#   servidor.key           -> clave privada del servidor (no se versiona)
#   servidor.crt
#   fullchain.pem          -> servidor.crt + ca-intermedia.crt (lo que entrega Caddy)
#
# Uso: sh crear-pki.sh [nombre-dns] [ip]
#      sh crear-pki.sh supabase.lab.internal 192.168.56.10
#
set -eu

DNS_NAME="${1:-supabase.lab.internal}"
IP_ADDR="${2:-192.168.56.10}"
OUT="$(dirname "$0")/salida"

mkdir -p "$OUT"
cd "$OUT"
umask 077   # las claves privadas quedan sólo legibles por el dueño

# Extensiones X.509 v3 de la intermedia y del servidor
# (las de la raíz se pasan con -addext más abajo)
cat > ext-intermedia.cnf <<'EOF'
basicConstraints       = critical, CA:TRUE, pathlen:0
keyUsage               = critical, keyCertSign, cRLSign
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid:always
EOF

cat > ext-servidor.cnf <<EOF
basicConstraints       = critical, CA:FALSE
keyUsage               = critical, digitalSignature
extendedKeyUsage       = serverAuth
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid:always
subjectAltName         = DNS:${DNS_NAME}, IP:${IP_ADDR}
EOF

echo "==> CA raíz (EC P-384, 10 años)"
openssl ecparam -name secp384r1 -genkey -noout -out ca-raiz.key
openssl req -new -x509 -sha384 -days 3650 -key ca-raiz.key \
    -subj "/C=AR/ST=La Pampa/O=UNLPam - Lab Redes/CN=Lab Redes CA Raiz" \
    -extensions v3_ca -addext "basicConstraints=critical,CA:TRUE" \
    -addext "keyUsage=critical,keyCertSign,cRLSign" \
    -out ca-raiz.crt

echo "==> CA intermedia (EC P-384, 5 años)"
openssl ecparam -name secp384r1 -genkey -noout -out ca-intermedia.key
openssl req -new -sha384 -key ca-intermedia.key \
    -subj "/C=AR/ST=La Pampa/O=UNLPam - Lab Redes/CN=Lab Redes CA Intermedia" \
    -out ca-intermedia.csr
openssl x509 -req -sha384 -days 1825 -in ca-intermedia.csr \
    -CA ca-raiz.crt -CAkey ca-raiz.key -CAcreateserial \
    -extfile ext-intermedia.cnf -out ca-intermedia.crt

echo "==> Certificado del servidor ${DNS_NAME} / ${IP_ADDR} (EC P-256, 1 año)"
openssl ecparam -name prime256v1 -genkey -noout -out servidor.key
openssl req -new -sha256 -key servidor.key \
    -subj "/C=AR/O=UNLPam - Lab Redes/CN=${DNS_NAME}" \
    -out servidor.csr
openssl x509 -req -sha256 -days 365 -in servidor.csr \
    -CA ca-intermedia.crt -CAkey ca-intermedia.key -CAcreateserial \
    -extfile ext-servidor.cnf -out servidor.crt

cat servidor.crt ca-intermedia.crt > fullchain.pem
chmod 644 ca-raiz.crt ca-intermedia.crt servidor.crt fullchain.pem

echo "==> Verificación de la cadena"
openssl verify -CAfile ca-raiz.crt -untrusted ca-intermedia.crt servidor.crt
openssl x509 -in servidor.crt -noout -subject -issuer -dates -ext subjectAltName
