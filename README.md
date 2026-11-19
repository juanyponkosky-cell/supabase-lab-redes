# Supabase autoalojado con Docker — Laboratorio de Redes y Comunicaciones (UNLPam)

Archivos de configuración y scripts del prototipo descripto en el informe final.
**No contiene credenciales reales**: todos los secretos se generan en el servidor y el `.env` nunca se versiona.

Versión de Supabase usada: `self-hosted/v0.8.4` (5 de noviembre de 2026).

## Topología

| Equipo | IP (red host-only 192.168.56.0/24) | Nombre |
| --- | --- | --- |
| srv-supabase | 192.168.56.10 | supabase.lab.internal, ns1.lab.internal |
| cliente | 192.168.56.20 | cliente.lab.internal |

## Contenido

| Ruta | Qué es | Dónde va |
| --- | --- | --- |
| `servidor/netplan/60-lab.yaml` | IP fija del servidor | `/etc/netplan/` (permisos 600) |
| `cliente/netplan/60-lab.yaml` | IP fija del cliente | `/etc/netplan/` del cliente |
| `servidor/bind/` | BIND9: opciones, zonas `lab.internal` e inversa | `/etc/bind/` |
| `servidor/pki/crear-pki.sh` | CA raíz, CA intermedia y certificado del servidor | se ejecuta en el servidor |
| `servidor/firewall/supabase-lab.nft` | Reglas nftables (host y puertos publicados por Docker) | `/etc/nftables.d/` |
| `supabase/env.lab.example` | Cambios del laboratorio sobre el `.env` (sin secretos) | lo aplica `instalar-supabase.sh` |
| `supabase/caddy/Caddyfile` | Proxy HTTPS con el certificado de la CA propia | `volumes/proxy/caddy/Caddyfile` |
| `supabase/sql/01-demo.sql` | Tabla `mensajes` con RLS, Realtime y bucket de Storage | se ejecuta una vez |
| `scripts/instalar-supabase.sh` | Descarga v0.8.4, genera secretos, aplica cambios | servidor |
| `scripts/pruebas-api.sh` | Pruebas de Auth, REST, RLS, Functions | cliente |
| `scripts/capturas.sh` | Capturas tcpdump externa, interna y de base | servidor |
| `scripts/backup.sh` / `restaurar.sh` | Respaldo y restauración completos | servidor |

## Orden de uso

1. Red: copiar los netplan, `sudo chmod 600 /etc/netplan/60-lab.yaml`, `sudo netplan apply`.
2. DNS: `sudo apt install bind9 bind9-utils`, copiar `servidor/bind/*` a `/etc/bind/`, `sudo named-checkconf -z && sudo systemctl restart named`.
3. Supabase, fase 1: `sh scripts/instalar-supabase.sh`, luego `cd ~/supabase-project && sh run.sh start`.
4. Datos de demo: ejecutar `supabase/sql/01-demo.sql`.
5. Pruebas en HTTP: `scripts/pruebas-api.sh` con `SB_URL=http://supabase.lab.internal:8000`, capturando con `scripts/capturas.sh`.
6. PKI: `sh servidor/pki/crear-pki.sh`, copiar `fullchain.pem` y `servidor.key` a `~/supabase-project/volumes/proxy/caddy/certs/`.
7. Fase 2: cambiar las URLs del `.env` a `https://`, `sh run.sh config add caddy`, `sh run.sh recreate`.
8. Firewall: copiar `supabase-lab.nft` a `/etc/nftables.d/`, incluirlo desde `/etc/nftables.conf` **sin** `flush ruleset`, `sudo nft -f /etc/nftables.d/supabase-lab.nft`.
9. Respaldo: `sudo sh scripts/backup.sh ~/supabase-project`.

## Qué no se sube nunca

`.env`, claves privadas (`*.key`), la carpeta `servidor/pki/salida/`, `backups/` y las capturas `.pcap` que contengan claves o JWT.
