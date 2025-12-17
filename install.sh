#!/usr/bin/env bash
set -euo pipefail

OS="$(uname -s)"
ENV_FILE=".env.web"

read -p "Would you like to answer setup questions? (y/n): " answerSetup

if [ "$OS" = "Linux" ]; then
    echo "Installing required packages (Git, curl, ca-certificates)..."
    sudo apt-get update
    sudo apt-get install -y git curl ca-certificates
fi

if ! command -v docker >/dev/null 2>&1; then
    echo "Docker not found. Installing."
    case "$OS" in
        Linux)
            curl -fsSL https://get.docker.com | sh
            ;;
        Darwin)
            echo "Please install Docker Desktop for macOS from https://www.docker.com/products/docker-desktop and start it."
            exit 1
            ;;
        MINGW*|MSYS*|CYGWIN*)
            echo "Please install Docker Desktop for Windows and start it."
            exit 1
            ;;
        *)
            echo "Unsupported platform"
            exit 1
            ;;
    esac
else
    echo "Docker already installed"
fi

if [ ! -d .git ]; then
    if command -v git >/dev/null 2>&1; then
        git clone https://github.com/stoatchat/self-hosted
        cd self-hosted || exit 1
        ENV_FILE=".env.web"
    else
        echo "Git not found. Please install Git and re-run the script."
        exit 1
    fi
else
    if [ -f .git/config ]; then
        echo "Git repo already present"
        cd "$(git rev-parse --show-toplevel)" || exit 1
        ENV_FILE=".env.web"
    else
        echo "Git repo already present but not recognized. Check manually."
        exit 1
    fi
fi

if [ ! -f "$ENV_FILE" ]; then
    echo "Creating default $ENV_FILE file"
    touch "$ENV_FILE"

    if [ "$answerSetup" = "y" ] || [ "$answerSetup" = "Y" ]; then
        while true; do
            read -p "Enter the hostname for your instance (e.g., http://local.stoat.chat): " HOSTNAME
            if [[ "$HOSTNAME" == http://* ]] || [[ "$HOSTNAME" == https://* ]]; then
                break
            else
                echo "Invalid input. Please include http:// or https://"
            fi
        done

        while true; do
            read -p "Enter the public URL for your instance API (e.g., http://local.stoat.chat/api): " REVOLT_PUBLIC_URL
            if [[ "$REVOLT_PUBLIC_URL" == http://* ]] || [[ "$REVOLT_PUBLIC_URL" == https://* ]]; then
                break
            else
                echo "Invalid input. Please include http:// or https://"
            fi
        done

        echo "HOSTNAME=$HOSTNAME" > "$ENV_FILE"
        echo "REVOLT_PUBLIC_URL=$REVOLT_PUBLIC_URL" >> "$ENV_FILE"
    fi
else
    echo "$ENV_FILE already exists. Skipping creation."
fi

if [ ! -f Revolt.toml ]; then
    echo "Creating default Revolt.toml file"
    curl -O https://raw.githubusercontent.com/revoltchat/backend/main/crates/core/config/Revolt.toml
    chmod +x ./generate_config.sh
    ./generate_config.sh "$(grep HOSTNAME "$ENV_FILE" | cut -d '=' -f2 | sed 's~http[s]*://~~;s~/api~~')"
else
    echo "Revolt.toml already exists. Skipping creation."
fi


echo
echo "Setup complete!"
echo
if command -v docker >/dev/null 2>&1; then
    echo "Starting Stoat services with 'docker compose up -d'..."
    if docker compose up -d; then
        echo "Stoat is now running in the background."
    else
		echo
        echo "Failed to start Docker services. Please ensure Docker is running and try:"
        echo "  docker compose up -d"
    fi
else
    echo "Docker not detected. Start Docker and then run:"
    echo "  docker compose up -d"
fi
echo
if [ "$OS" = "Linux" ]; then
    echo "You might need to run:"
    echo "  sudo usermod -aG docker \$USER"
    echo "and then log out and back in to use Docker without sudo."
fi

