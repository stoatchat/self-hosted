#!/usr/bin/env bash

SECRETS_FOUND=0
IS_OVERWRITING=0
DOMAIN=
VIDEO_ENABLED=

usage() {
    echo "Usage: ./generate_config.sh [--overwrite] DOMAIN"
    exit 1
}

loadSecrets() {
    SECRETS_FOUND=1
    set -a && source secrets.env && set +a
}

# Check args to ensure correct usage
# No args is not valid
if [[ $# -eq 1 ]]; then
    if [[ $1 = --* ]]; then
        usage
    fi
    DOMAIN=$1
elif [[ $# -eq 2 ]]; then
    if [[ $1 != --overwrite ]]; then
        usage
    fi
    if [[ $2 = --* ]]; then
        usage
    fi
    DOMAIN=$2
    IS_OVERWRITING=1
else
    usage
fi

if test -f "secrets.env"; then
    loadSecrets
fi

if test -f "Revolt.toml"; then
    if [[ $IS_OVERWRITING -eq 1 ]]; then
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
        usage
    fi
fi

if [ "$SECRETS_FOUND" -eq "0" ]; then
    cp secrets.env.example secrets.env
    loadSecrets
else
    echo "Checking if secrets file needs to be updated..."
    if [ "$PUSHD_VAPID_PRIVATEKEY" != "" ] || [ "$PUSHD_VAPID_PUBLICKEY" != "" ] || [ "$FILES_ENCRYPTION_KEY" != "" ] || [ "$LIVEKIT_WORLDWIDE_SECRET" != "" ] || [ "$LIVEKIT_WORLDWIDE_KEY" != "" ]; then
        echo "Old secrets found. Your secrets will be rewritten in the new format. If you have any custom secrets not managed by this file, you will need to convert them to the new format."
        echo "See https://github.com/stoatchat/stoatchat/pull/576"
        echo "Renaming secrets.env to secrets.env.old"
        mv secrets.env secrets.env.old
        echo "Copying old secrets to new format..."
        cp secrets.env.example secrets.env
        printf "REVOLT__PUSHD__VAPID__PRIVATE_KEY='%s'\n" $PUSHD_VAPID_PRIVATEKEY >> secrets.env
        printf "REVOLT__PUSHD__VAPID__PUBLIC_KEY='%s'\n" $PUSHD_VAPID_PUBLICKEY >> secrets.env
        echo "" >> secrets.env
        printf "REVOLT__FILES__ENCRYPTION_KEY='%s'\n" $FILES_ENCRYPTION_KEY >> secrets.env
        echo "" >> secrets.env
        printf "REVOLT__API__LIVEKIT__NODES__WORLDWIDE__SECRET='%s'\n" $LIVEKIT_WORLDWIDE_SECRET >> secrets.env
        printf "REVOLT__API__LIVEKIT__NODES__WORLDWIDE__KEY='%s'\n" $LIVEKIT_WORLDWIDE_KEY >> secrets.env
        loadSecrets
    fi
fi

echo "Configuring Stoat with hostname $DOMAIN"

STOAT_HOSTNAME="https://$DOMAIN"

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
    echo "STOAT_DOMAIN=" > .env
else
    echo "No received. Configuring with built in caddy as primary reverse proxy."
    echo "STOAT_DOMAIN=$DOMAIN" > .env
fi

read -rp "Would you like to enable camera and screen sharing? [Y/n]: "
if [ "$REPLY" = "n" ] || [ "$REPLY" = "N" ]; then
    echo "No received. Not configuring video."
else
    echo "Yes received. Configuring video."
    VIDEO_ENABLED=true
fi

# Generate secrets
echo "Generating secrets..."
if [ "$REVOLT__PUSHD__VAPID__PRIVATE_KEY" = "" ]; then 
    if [ "$REVOLT__PUSHD__VAPID__PUBLIC_KEY" != "" ]; then
        echo "VAPID public key is defined when private key isn't?"
        echo "Did you forget to copy the REVOLT__PUSHD__VAPID__PRIVATE_KEY secret?"
        echo "Try removing REVOLT__PUSHD__VAPID__PUBLIC_KEY if you do not have a private key."
        exit 1
    fi
    echo "Generating Pushd VAPID secrets..."
    openssl ecparam -name prime256v1 -genkey -noout -out vapid_private.pem
    REVOLT__PUSHD__VAPID__PRIVATE_KEY=$(base64 -i vapid_private.pem | tr -d '\n' | tr -d '=')
    REVOLT__PUSHD__VAPID__PUBLIC_KEY=$(openssl ec -in vapid_private.pem -outform DER|tail --bytes 65|base64|tr '/+' '_-'|tr -d '\n'|tr -d '=')
    rm vapid_private.pem
    echo "" >> secrets.env
    printf "REVOLT__PUSHD__VAPID__PRIVATE_KEY='%s'\n" $REVOLT__PUSHD__VAPID__PRIVATE_KEY >> secrets.env
    printf "REVOLT__PUSHD__VAPID__PUBLIC_KEY='%s'\n" $REVOLT__PUSHD__VAPID__PUBLIC_KEY >> secrets.env
elif [ "$REVOLT__PUSHD__VAPID__PUBLIC_KEY" = "" ]; then
    echo "VAPID private key is defined when public key isn't?"
    echo "Did you forget to copy the REVOLT__PUSHD__VAPID__PUBLIC_KEY secret?"
    echo "Try removing REVOLT__PUSHD__VAPID__PRIVATE_KEY if you do not have a public key."
    exit 1
else
    echo "Using old Pushd VAPID secrets..."
fi

if [ "$REVOLT__FILES__ENCRYPTION_KEY" = "" ]; then
    echo "Generating files encryption secret..."
    REVOLT__FILES__ENCRYPTION_KEY=$(openssl rand -base64 32)
    echo "" >> secrets.env
    printf "REVOLT__FILES__ENCRYPTION_KEY='%s'\n" $REVOLT__FILES__ENCRYPTION_KEY >> secrets.env
else
    echo "Using old files encryption secret..."
fi

if [ "$REVOLT__API__LIVEKIT__NODES__WORLDWIDE__SECRET" = "" ]; then 
    if [ "$REVOLT__API__LIVEKIT__NODES__WORLDWIDE__KEY" != "" ]; then
        echo "Livekit public key is defined when secret isn't?"
        echo "Did you forget to copy the REVOLT__API__LIVEKIT__NODES__WORLDWIDE__SECRET secret?"
        echo "Try removing REVOLT__API__LIVEKIT__NODES__WORLDWIDE__KEY if you do not have a secret."
        exit 1
    fi
    echo "Generating Livekit secrets..."
    REVOLT__API__LIVEKIT__NODES__WORLDWIDE__SECRET=$(openssl rand -hex 24)
    REVOLT__API__LIVEKIT__NODES__WORLDWIDE__KEY=$(openssl rand -hex 6)
    echo "" >> secrets.env
    printf "REVOLT__API__LIVEKIT__NODES__WORLDWIDE__SECRET='%s'\n" $REVOLT__API__LIVEKIT__NODES__WORLDWIDE__SECRET >> secrets.env
    printf "REVOLT__API__LIVEKIT__NODES__WORLDWIDE__KEY='%s'\n" $REVOLT__API__LIVEKIT__NODES__WORLDWIDE__KEY >> secrets.env
elif [ "$REVOLT__API__LIVEKIT__NODES__WORLDWIDE__KEY" = "" ]; then
    echo "Livekit secret is defined when public key isn't?"
    echo "Did you forget to copy the REVOLT__API__LIVEKIT__NODES__WORLDWIDE__KEY secret?"
    echo "Try removing REVOLT__API__LIVEKIT__NODES__WORLDWIDE__SECRET if you do not have a public key."
    exit 1
else
    echo "Using old Livekit secrets..."
fi

# set hostname for Caddy and vite variables
echo "HOSTNAME=$STOAT_HOSTNAME" > .env.web
echo "REVOLT_PUBLIC_URL=https://$DOMAIN/api" >> .env.web
echo "VITE_API_URL=https://$DOMAIN/api" >> .env.web
echo "VITE_WS_URL=wss://$DOMAIN/ws" >> .env.web
echo "VITE_MEDIA_URL=https://$DOMAIN/autumn" >> .env.web
echo "VITE_PROXY_URL=https://$DOMAIN/january" >> .env.web
echo "VITE_CFG_ENABLE_VIDEO=$VIDEO_ENABLED" >> .env.web

# hostnames
echo "[hosts]" > Revolt.toml
echo "app = \"https://$DOMAIN\"" >> Revolt.toml
echo "api = \"https://$DOMAIN/api\"" >> Revolt.toml
echo "events = \"wss://$DOMAIN/ws\"" >> Revolt.toml
echo "autumn = \"https://$DOMAIN/autumn\"" >> Revolt.toml
echo "january = \"https://$DOMAIN/january\"" >> Revolt.toml

# livekit hostname
echo "" >> Revolt.toml
echo "[hosts.livekit]" >> Revolt.toml
echo "worldwide = \"wss://$DOMAIN/livekit\"" >> Revolt.toml

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
echo "  $REVOLT__API__LIVEKIT__NODES__WORLDWIDE__KEY: $REVOLT__API__LIVEKIT__NODES__WORLDWIDE__SECRET" >> livekit.yml
echo "" >> livekit.yml
echo "webhook:" >> livekit.yml
echo "  api_key: $REVOLT__API__LIVEKIT__NODES__WORLDWIDE__KEY" >> livekit.yml
echo "  urls:" >> livekit.yml
echo "  - \"http://voice-ingress:8500/worldwide\"" >> livekit.yml

# livekit config
echo "" >> Revolt.toml
echo "[api.livekit.nodes.worldwide]" >> Revolt.toml
echo "url = \"http://livekit:7880\"" >> Revolt.toml
echo "lat = 0.0" >> Revolt.toml
echo "lon = 0.0" >> Revolt.toml

# Video config
# We'll enable 1080p video by default, that should be high enough for most users.
if [[ -n "$VIDEO_ENABLED" ]]; then
    echo "" >> Revolt.toml
    echo "[features.limits.new_user]" >> Revolt.toml
    echo "video_resolution = [1920, 1080]" >> Revolt.toml
    echo "video_aspect_ratio = [0.3, 10]" >> Revolt.toml
    echo "" >> Revolt.toml
    echo "[features.limits.default]" >> Revolt.toml
    echo "video_resolution = [1920, 1080]" >> Revolt.toml
    echo "video_aspect_ratio = [0.3, 10]" >> Revolt.toml
fi

if [[ $IS_OVERWRITING -eq 1 ]]; then
    echo "Overwrote existing config. If any custom configuration was present in old Revolt.toml, you may now copy it over from Revolt.toml.old."
fi