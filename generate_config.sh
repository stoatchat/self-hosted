#!/usr/bin/env bash

# Usage: ./generate_config.sh --domain your.domain [--http port] [--https port]
#
# Options:
#   --domain    Required. The domain name for this instance.
#   --http      Optional. Non-standard HTTP port (default: 80).
#   --https     Optional. Non-standard HTTPS port (default: 443).
#
# Examples:
#   ./generate_config.sh --domain chat.example.com
#   ./generate_config.sh --domain chat.example.com --https 9443
#   ./generate_config.sh --domain chat.example.com --http 9080 --https 9443

DOMAIN=""
HTTP_PORT=""
HTTPS_PORT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain)  DOMAIN="$2";     shift 2 ;;
    --http)    HTTP_PORT="$2";  shift 2 ;;
    --https)   HTTPS_PORT="$2"; shift 2 ;;
    *)
      # Support legacy positional usage: ./generate_config.sh domain
      if [ -z "$DOMAIN" ]; then
        DOMAIN="$1"; shift
      else
        echo "Unknown option: $1" >&2; exit 1
      fi
      ;;
  esac
done

if [ -z "$DOMAIN" ]; then
  echo "Usage: $0 --domain <domain> [--http <port>] [--https <port>]"
  echo "       $0 <domain>  (legacy positional usage)"
  exit 1
fi

# Build the public-facing host (domain with optional HTTPS port)
if [ -n "$HTTPS_PORT" ] && [ "$HTTPS_PORT" != "443" ]; then
  HOST="${DOMAIN}:${HTTPS_PORT}"
else
  HOST="${DOMAIN}"
fi

# set hostname for Caddy
# When using non-standard ports, Caddy needs the port in the site address
echo "HOSTNAME=${HOST}" > .env.web
echo "REVOLT_PUBLIC_URL=https://${HOST}/api" >> .env.web

# hostnames
echo "[hosts]" >> Revolt.toml
echo "app = \"https://${HOST}\"" >> Revolt.toml
echo "api = \"https://${HOST}/api\"" >> Revolt.toml
echo "events = \"wss://${HOST}/ws\"" >> Revolt.toml
echo "autumn = \"https://${HOST}/autumn\"" >> Revolt.toml
echo "january = \"https://${HOST}/january\"" >> Revolt.toml

# VAPID keys
echo "" >> Revolt.toml
echo "[pushd.vapid]" >> Revolt.toml
openssl ecparam -name prime256v1 -genkey -noout -out vapid_private.pem
echo "private_key = \"$(base64 -i vapid_private.pem | tr -d '\n' | tr -d '=')\"" >> Revolt.toml
echo "public_key = \"$(openssl ec -in vapid_private.pem -outform DER|tail --bytes 65|base64|tr '/+' '_-'|tr -d '\n'|tr -d '=')\"" >> Revolt.toml
rm vapid_private.pem

# encryption key for files
echo "" >> Revolt.toml
echo "[files]" >> Revolt.toml
echo "encryption_key = \"$(openssl rand -base64 32)\"" >> Revolt.toml

# Print port configuration hints if non-standard ports are used
if [ -n "$HTTP_PORT" ] || [ -n "$HTTPS_PORT" ]; then
  echo ""
  echo "Non-standard port(s) configured."
  echo "Update compose.yml caddy ports to match:"
  [ -n "$HTTP_PORT" ]  && echo "  - \"${HTTP_PORT}:80\""
  [ -n "$HTTPS_PORT" ] && echo "  - \"${HTTPS_PORT}:${HTTPS_PORT}\""
  echo ""
  echo "See README.md 'Placing Behind Another Reverse-Proxy or Another Port' for details."
fi
