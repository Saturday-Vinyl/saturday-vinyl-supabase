#!/bin/bash
# Setup shared docs subtree for a new project
# Run from your project root
#
# Usage:
#   1. Clone this repo locally (once):
#      git clone https://github.com/Saturday-Vinyl/saturday-vinyl-shared-docs.git ~/saturday-vinyl-shared-docs
#
#   2. Run from your project directory:
#      ~/saturday-vinyl-shared-docs/scripts/setup-shared-docs.sh
#
# You can also override the remote URL:
#   SHARED_DOCS_REMOTE_URL=git@github.com:Saturday-Vinyl/saturday-vinyl-shared-docs.git ./setup-shared-docs.sh

set -e

# Configuration - uses HTTPS by default (works with private repos if you have access)
REMOTE_URL="${SHARED_DOCS_REMOTE_URL:-https://github.com/Saturday-Vinyl/saturday-vinyl-shared-docs.git}"
REMOTE_NAME="shared-docs"
PREFIX="shared-docs"
BRANCH="main"

echo "============================================"
echo "Saturday Vinyl Shared Docs Setup"
echo "============================================"
echo ""
echo "Setting up shared docs for $(basename $(pwd))..."
echo "Remote: $REMOTE_URL"
echo ""

# Check we're in a git repo
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "Error: Not in a git repository"
    exit 1
fi

# Add remote if not exists
if ! git remote | grep -q "^${REMOTE_NAME}$"; then
    echo "Adding remote: $REMOTE_NAME"
    git remote add $REMOTE_NAME $REMOTE_URL
else
    echo "Remote '$REMOTE_NAME' already exists"
fi

# Fetch from remote
echo "Fetching from $REMOTE_NAME..."
git fetch $REMOTE_NAME

# Check for uncommitted changes and stash if needed
STASHED=false
if ! git diff --quiet || ! git diff --cached --quiet || [ -n "$(git ls-files --others --exclude-standard)" ]; then
    echo ""
    echo "Stashing uncommitted changes..."
    git stash --include-untracked
    STASHED=true
fi

# Check if subtree already exists
if [ -d "$PREFIX" ]; then
    echo ""
    echo "Directory '$PREFIX/' already exists. Pulling latest..."
    git subtree pull --prefix=$PREFIX $REMOTE_NAME $BRANCH --squash -m "Update shared docs from central repo"
else
    echo ""
    echo "Adding subtree at $PREFIX/..."
    git subtree add --prefix=$PREFIX $REMOTE_NAME $BRANCH --squash
fi

# Restore stashed changes if we stashed them
if [ "$STASHED" = true ]; then
    echo ""
    echo "Restoring stashed changes..."
    git stash pop
fi

# Setup Claude commands
echo ""
echo "Setting up Claude commands..."
mkdir -p .claude/commands

# Copy command templates (won't overwrite existing)
if [ -d "$PREFIX/templates/claude-commands" ]; then
    for template in $PREFIX/templates/claude-commands/*.md; do
        if [ -f "$template" ]; then
            filename=$(basename "$template")
            if [ ! -f ".claude/commands/$filename" ]; then
                cp "$template" ".claude/commands/$filename"
                echo "  Created: .claude/commands/$filename"
            else
                echo "  Skipped: .claude/commands/$filename (already exists)"
            fi
        fi
    done
else
    echo "  Warning: No command templates found in $PREFIX/templates/claude-commands/"
fi

echo ""
echo "============================================"
echo "Setup complete!"
echo "============================================"
echo ""
echo "Available Claude commands:"
echo "  /ble-provisioning  - BLE Provisioning Protocol"
echo "  /service-mode      - Service Mode Protocol"
echo ""
echo "Useful commands:"
echo "  Pull updates:  git subtree pull --prefix=$PREFIX $REMOTE_NAME $BRANCH --squash"
echo "  Push changes:  git subtree push --prefix=$PREFIX $REMOTE_NAME $BRANCH"
echo ""
