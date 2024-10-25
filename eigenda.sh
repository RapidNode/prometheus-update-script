#!/bin/bash

# Parse arguments
CLIENT_ID="$1"
USERNAME="$2"
PASSWORD="$3"
PROMETHEUS_SERVER_URL="$4"
TARGET_LABEL="client_id"

if [ -z "$CLIENT_ID" ] || [ -z "$USERNAME" ] || [ -z "$PASSWORD" ] || [ -z "$PROMETHEUS_SERVER_URL" ]; then
    echo "Usage: $0 <client_id> <username> <password> <prometheus_server_url>"
    exit 1
fi

if [ ! -f ".env" ]; then
    echo "No .env file found in current directory."
    echo "Please navigate to your eigenda-operator-setup/monitoring directory first."
    exit 1
fi

# Extract the Prometheus config path
PROMETHEUS_CONFIG_PATH=$(grep PROMETHEUS_CONFIG_FILE_HOST .env | cut -d '=' -f2)

if [ -z "$PROMETHEUS_CONFIG_PATH" ]; then
    echo "Could not find PROMETHEUS_CONFIG_FILE_HOST in .env file"
    exit 1
fi

# Remove any quotes and expand environment variables
PROMETHEUS_CONFIG_PATH=$(echo "$PROMETHEUS_CONFIG_PATH" | tr -d '"' | tr -d "'")
PROMETHEUS_CONFIG_PATH=$(eval echo "$PROMETHEUS_CONFIG_PATH")

if [ ! -f "$PROMETHEUS_CONFIG_PATH" ]; then
    echo "Prometheus config file not found at: $PROMETHEUS_CONFIG_PATH"
    exit 1
fi

# Create the remote write config with proper indentation
NEW_REMOTE_WRITE="  - url: '$PROMETHEUS_SERVER_URL'
    basic_auth:
      username: $USERNAME
      password: $PASSWORD
    write_relabel_configs:
      - target_label: $TARGET_LABEL
        replacement: $CLIENT_ID
        action: replace"

# Backup the existing config
backup_file="${PROMETHEUS_CONFIG_PATH}.backup.$(date +%Y%m%d_%H%M%S)"
cp "$PROMETHEUS_CONFIG_PATH" "$backup_file"
echo "Created backup at $backup_file"

# Create a temporary file
temp_file=$(mktemp)

# Process the file
awk -v new_config="$NEW_REMOTE_WRITE" '
BEGIN { in_remote_write = 0; printed = 0 }
/^remote_write:/ {
    in_remote_write = 1
    print $0
    print new_config
    printed = 1
    next
}
{
    if (!in_remote_write) {
        print $0
    } else if ($0 ~ /^[^ ]/) {
        in_remote_write = 0
        if (!printed) {
            print new_config
            printed = 1
        }
        print $0
    } else {
        print $0
    }
}
END {
    if (!printed) {
        print "remote_write:"
        print new_config
    }
}' "$PROMETHEUS_CONFIG_PATH" > "$temp_file"

# Replace the original file with our updated version
mv "$temp_file" "$PROMETHEUS_CONFIG_PATH"

# Permission isssues fix
chmod 644 "$PROMETHEUS_CONFIG_PATH"
chown 65534:65534 "$PROMETHEUS_CONFIG_PATH" 2>/dev/null || true

# Check if docker compose exists in the current directory
if [ -f "docker-compose.yml" ] || [ -f "compose.yml" ]; then
    echo "Restarting containers..."
    docker compose down
    docker compose up -d
    docker network connect eigenda-network prometheus
else
    echo "No docker-compose.yml found in current directory"
    echo "Please restart your containers manually"
fi

echo "Configuration complete!"
echo "Verify your containers are running with: docker ps"
echo "If you encounter any issues, you can restore the backup from: $backup_file"
