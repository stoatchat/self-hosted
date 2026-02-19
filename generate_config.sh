#!/usr/bin/env bash

if test -f "Revolt.toml"; then
    echo "Existing config found, running this script will overwrite your existing config. Are you sure you'd like to reconfigure?"
    select yn in "Yes" "No"; do
        case $yn in
            No ) exit;;
            Yes ) break;;
        esac
    done
fi

# set hostname for Caddy and vite variables
echo "HOSTNAME=https://$1" > .env.web
echo "REVOLT_PUBLIC_URL=https://$1/api" >> .env.web
echo "VITE_API_URL=https://$1/api" >> .env.web
echo "VITE_WS_URL=wss://$1/ws" >> .env.web
echo "VITE_MEDIA_URL=https://$1/autumn" >> .env.web
echo "VITE_PROXY_URL=https://$1/january" >> .env.web

# hostnames
echo "[hosts]" > Revolt.toml
echo "app = \"https://$1\"" >> Revolt.toml
echo "api = \"https://$1/api\"" >> Revolt.toml
echo "events = \"wss://$1/ws\"" >> Revolt.toml
echo "autumn = \"https://$1/autumn\"" >> Revolt.toml
echo "january = \"https://$1/january\"" >> Revolt.toml

# livekit hostname
echo "" >> Revolt.toml
echo "[hosts.livekit]" >> Revolt.toml
echo "worldwide = \"wss://$1/livekit\"" >> Revolt.toml

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

livekit_key=$(openssl rand -hex 6)
livekit_secret=$(openssl rand -hex 24)

# livekit key
echo "" >> livekit.yml
echo "keys:" >> livekit.yml
echo "  $livekit_key: $livekit_secret" >> livekit.yml
echo "" >> livekit.yml
echo "webhook:" >> livekit.yml
echo "  api_key: $livekit_key" >> livekit.yml
echo "  urls:" >> livekit.yml
echo "  - \"https://$1/ingress/worldwide\"" >> livekit.yml

# livekit config
echo "" >> Revolt.toml
echo "[api.livekit.nodes.worldwide]" >> Revolt.toml
echo "url = \"https://$1/livekit\"" >> Revolt.toml
echo "lat = 0.0" >> Revolt.toml
echo "lon = 0.0" >> Revolt.toml
echo "key = \"$livekit_key\"" >> Revolt.toml
echo "secret = \"$livekit_secret\"" >> Revolt.toml