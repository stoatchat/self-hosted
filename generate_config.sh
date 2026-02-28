#!/usr/bin/env bash

SECRETS_FOUND=0
IS_OVERWRITING=0

loadSecrets() {
    SECRETS_FOUND=1
    set -a && source secrets.env && set +a
}

if test -f "secrets.env"; then
    loadSecrets
fi

if test -f "Revolt.toml"; then
    if [[ \ $*\  = *\ --overwrite\ * ]]; then
        IS_OVERWRITING=1
        if [ "$SECRETS_FOUND" -eq "0" ]; then
            echo "Overwrite flag passed, but secrets.env not found. This script will refuse to execute an overwrite without secrets.env."
            echo "If you are absolutely sure you want to overwrite your secrets with new secrets, copy the secrets.env.example file without modifying it's contents using command 'cp secrets.env.example secrets.env'."
            echo "If you do not copy your existing secrets into secrets.env you WILL lose access to ALL of your files store in your Stoat instance."
            exit 1
        fi
        echo "Overwriting existing config."
        echo "Renaming Revolt.toml to Revolt.toml.old"
        mv Revolt.toml Revolt.toml.old
        echo "Renaming livekit.yml to livekit.yml.old"
        mv livekit.yml livekit.yml.old
        echo "Renaming compose.override.yml to compose.override.yml.old"
        mv compose.override.yml compose.override.yml.old
    else
        echo "Existing config found, in caution, this script will refuse to execute if you have existing config."
        if [ "$SECRETS_FOUND" -eq "0" ]; then
            echo "Please configure secrets.env with your existing secrets to prevent losing access to your saved files in your Stoat instance. You can see instructions on how to configure it by reading the file secrets.env.example. You can do this by running the command 'cat secrets.env.example'."
            echo "Overwriting your existing config will result in you losing access to all current files stored on your Stoat instance unless you copy your old secrets into secrets.env."
        else
            echo "secrets.env found, please ensure it matches what is currently in your Revolt.toml."
        fi
        echo "This script will back up your old config if you choose to overwrite."
        echo "To overwrite the existing config, run the script again with the --overwrite flag"
        echo "$0 $* --overwrite"
        exit 1
    fi
fi

if [ "$SECRETS_FOUND" -eq "0" ]; then
    cp secrets.env.example secrets.env
    loadSecrets
fi

STOAT_HOSTNAME="https://$1"

read -rp "Would you like to place Stoat behind another reverse proxy? [y/N]: "
if [ "$REPLY" = "y" ] || [ "$REPLY" = "Y" ]; then
    echo "Yes received. Configuring for reverse proxy."
    STOAT_HOSTNAME=':80'
    echo "Writing compose.override.yml..."
    echo "services:" > compose.override.yml
    echo "  caddy:" >> compose.override.yml
    echo "    ports: !override" >> compose.override.yml
    echo "     - \"8880:80\"" >> compose.override.yml
    echo "caddy is configured to host on :8880. If you need a different port, modify the compose.override.yml."
else
    echo "No received. Configuring with built in caddy as primary reverse proxy."
fi

# Generate secrets
echo "Generating secrets..."
if [ "$PUSHD_VAPID_PRIVATEKEY" = "" ]; then 
    if [ "$PUSHD_VAPID_PUBLICKEY" != "" ]; then
        echo "VAPID public key is defined when private key isn't?"
        echo "Did you forget to copy the PUSHD_VAPID_PRIVATEKEY secret?"
        echo "Try removing PUSHD_VAPID_PUBLICKEY if you do not have a private key."
        exit 1
    fi
    echo "Generating Pushd VAPID secrets..."
    openssl ecparam -name prime256v1 -genkey -noout -out vapid_private.pem
    PUSHD_VAPID_PRIVATEKEY=$(base64 -i vapid_private.pem | tr -d '\n' | tr -d '=')
    PUSHD_VAPID_PUBLICKEY=$(openssl ec -in vapid_private.pem -outform DER|tail --bytes 65|base64|tr '/+' '_-'|tr -d '\n'|tr -d '=')
    rm vapid_private.pem
    echo "" >> secrets.env
    printf "PUSHD_VAPID_PRIVATEKEY='%s'\n" $PUSHD_VAPID_PRIVATEKEY >> secrets.env
    printf "PUSHD_VAPID_PUBLICKEY='%s'\n" $PUSHD_VAPID_PUBLICKEY >> secrets.env
elif [ "$PUSHD_VAPID_PUBLICKEY" = "" ]; then
    echo "VAPID private key is defined when public key isn't?"
    echo "Did you forget to copy the PUSHD_VAPID_PUBLICKEY secret?"
    echo "Try removing PUSHD_VAPID_PRIVATEKEY if you do not have a public key."
    exit 1
else
    echo "Using old Pushd VAPID secrets..."
fi

if [ "$FILES_ENCRYPTION_KEY" = "" ]; then
    echo "Generating files encryption secret..."
    FILES_ENCRYPTION_KEY=$(openssl rand -base64 32)
    echo "" >> secrets.env
    printf "FILES_ENCRYPTION_KEY='%s'\n" $FILES_ENCRYPTION_KEY >> secrets.env
else
    echo "Using old files encryption secret..."
fi

if [ "$LIVEKIT_WORLDWIDE_SECRET" = "" ]; then 
    if [ "$LIVEKIT_WORLDWIDE_KEY" != "" ]; then
        echo "Livekit public key is defined when secret isn't?"
        echo "Did you forget to copy the LIVEKIT_WORLDWIDE_SECRET secret?"
        echo "Try removing LIVEKIT_WORLDWIDE_KEY if you do not have a secret."
        exit 1
    fi
    echo "Generating Livekit secrets..."
    LIVEKIT_WORLDWIDE_SECRET=$(openssl rand -hex 24)
    LIVEKIT_WORLDWIDE_KEY=$(openssl rand -hex 6)
    echo "" >> secrets.env
    printf "LIVEKIT_WORLDWIDE_SECRET='%s'\n" $LIVEKIT_WORLDWIDE_SECRET >> secrets.env
    printf "LIVEKIT_WORLDWIDE_KEY='%s'\n" $LIVEKIT_WORLDWIDE_KEY >> secrets.env
elif [ "$LIVEKIT_WORLDWIDE_KEY" = "" ]; then
    echo "Livekit secret is defined when public key isn't?"
    echo "Did you forget to copy the LIVEKIT_WORLDWIDE_KEY secret?"
    echo "Try removing LIVEKIT_WORLDWIDE_SECRET if you do not have a public key."
    exit 1
else
    echo "Using old Livekit secrets..."
fi

# set hostname for Caddy and vite variables
echo "HOSTNAME=$STOAT_HOSTNAME" > .env.web
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

echo "private_key = \"$PUSHD_VAPID_PRIVATEKEY\"" >> Revolt.toml
echo "public_key = \"$PUSHD_VAPID_PUBLICKEY\"" >> Revolt.toml

# encryption key for files
echo "" >> Revolt.toml
echo "[files]" >> Revolt.toml
echo "encryption_key = \"$FILES_ENCRYPTION_KEY\"" >> Revolt.toml

# livekit yml
echo "rtc:" > livekit.yml
echo "  use_external_ip: true" >> livekit.yml
echo "  port_range_start: 50000" >> livekit.yml
echo "  port_range_end: 50100" >> livekit.yml
echo "  tcp_port: 7881" >> livekit.yml
echo "" >> livekit.yml
echo "redis:" >> livekit.yml
echo "  address: redis:6379" >> livekit.yml
echo "" >> livekit.yml
echo "turn:" >> livekit.yml
echo "  enabled: false" >> livekit.yml
echo "" >> livekit.yml
echo "keys:" >> livekit.yml
echo "  $LIVEKIT_WORLDWIDE_KEY: $LIVEKIT_WORLDWIDE_SECRET" >> livekit.yml
echo "" >> livekit.yml
echo "webhook:" >> livekit.yml
echo "  api_key: $LIVEKIT_WORLDWIDE_KEY" >> livekit.yml
echo "  urls:" >> livekit.yml
echo "  - \"http://voice-ingress:8500/worldwide\"" >> livekit.yml

# livekit config
echo "" >> Revolt.toml
echo "[api.livekit.nodes.worldwide]" >> Revolt.toml
echo "url = \"http://livekit:7880\"" >> Revolt.toml
echo "lat = 0.0" >> Revolt.toml
echo "lon = 0.0" >> Revolt.toml
echo "key = \"$LIVEKIT_WORLDWIDE_KEY\"" >> Revolt.toml
echo "secret = \"$LIVEKIT_WORLDWIDE_SECRET\"" >> Revolt.toml

if [ "$IS_OVERWRITING" -eq "1" ]; then
    echo "Overwrote existing config. If any custom configuration was present in old Revolt.toml, you may now copy it over from Revolt.toml.old."
fi