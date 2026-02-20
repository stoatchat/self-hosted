#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f "compose.yml" || ! -f "Revolt.toml" ]]; then
    echo "Error: This script needs to be run from your stoat config directory." >&2
    exit 1
fi

run_mongosh() {
    sudo docker compose exec -T database mongosh --quiet --eval "$1"
}

create_invite() {
    local code
    code="$(openssl rand -hex 16)"

    if run_mongosh "use(\"revolt\"); db.invites.insertOne({ _id: \"${code}\" });" > /dev/null 2>&1; then
        echo "Successfully created invite: ${code}"
    else
        echo "Error: Failed to create invite" >&2
    fi
}

view_invites() {
    local output
    output="$(run_mongosh "use(\"revolt\"); db.invites.find().forEach(doc => print(doc._id));")"

    if [[ -z "$output" ]]; then
        echo "No active invites found"
    else
        echo "Active invites:"
        while IFS= read -r line; do
            echo "  - ${line}"
        done <<< "$output"
    fi
}

delete_invite() {
    local output
    output="$(run_mongosh "use(\"revolt\"); db.invites.find().forEach(doc => print(doc._id));")"

    if [[ -z "$output" ]]; then
        echo "No active invites to delete"
        return
    fi

    local invites=()
    while IFS= read -r line; do
        invites+=("$line")
    done <<< "$output"

    echo "Active invites:"
    for i in "${!invites[@]}"; do
        echo "  $((i + 1))) ${invites[$i]}"
    done

    local choice
    read -rp "Enter the number of the invite to delete (1-${#invites[@]}, or 'c' to cancel): " choice

    if [[ "$choice" =~ ^[Cc](ancel)?$ ]]; then
        echo "Delete cancelled"
        return
    fi

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#invites[@]} )); then
        echo "Error: Invalid selection" >&2
        return
    fi

    local target="${invites[$((choice - 1))]}"

    if run_mongosh "use(\"revolt\"); db.invites.deleteOne({ _id: \"${target}\" });" > /dev/null 2>&1; then
        echo "Successfully deleted invite: ${target}"
    else
        echo "Error: Failed to delete invite" >&2
    fi
}

while true; do
    echo ""
    echo "Stoat Invite Manager"
    echo "1) Create a new invite"
    echo "2) View active invites"
    echo "3) Delete a pending invite"
    echo "4) Exit"
    read -rp "Choose an option: " option

    case "$option" in
        1) create_invite ;;
        2) view_invites ;;
        3) delete_invite ;;
        4) exit 0 ;;
        *) echo "Invalid option." ;;
    esac
done
