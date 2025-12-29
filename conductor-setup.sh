#!/bin/bash

# Conductor workspace setup script
# This script runs in the newly created workspace directory

# Copy .env file from the repository root if it exists
if [ -f "$CONDUCTOR_ROOT_PATH/.env" ]; then
    cp "$CONDUCTOR_ROOT_PATH/.env" "$CONDUCTOR_WORKSPACE_PATH/.env"
    echo "Copied .env file from root to workspace"
else
    echo "Warning: No .env file found at $CONDUCTOR_ROOT_PATH/.env"
fi
