#!/bin/bash
set -eo pipefail

log() { echo "[claude-code-gh] $1" >&2; }

### -------- check if we need to install the cli

[[ "$CLAUDE_CODE_REMOTE" == "true" ]] || { log "Not remote, skipping"; exit 0; }

LOCAL_BIN="$HOME/.local/bin"
mkdir -p "$LOCAL_BIN"
export PATH="$LOCAL_BIN:$PATH"

if command -v gh &>/dev/null; then
    log "gh already available"
    echo "GitHub CLI available: $(gh --version | head -1)"
    exit 0
fi

### -------- check network access

if ! curl -sL --connect-timeout 5 -o /dev/null https://release-assets.githubusercontent.com 2>/dev/null; then
    log "Cannot download gh CLI: release-assets.githubusercontent.com is not reachable."
    log "Fix: Use 'Full' network access, or add release-assets.githubusercontent.com to your Custom allowlist."
    exit 2
fi

### -------- prepare to install CLI

log "Installing gh CLI..."

ARCH=$(uname -m)
case "$ARCH" in
    x86_64) GH_ARCH="amd64" ;;
    aarch64|arm64) GH_ARCH="arm64" ;;
    *) log "Failed to install gh CLI: unsupported architecture '$ARCH'. Only x86_64 and arm64 are supported."; exit 2 ;;
esac

# Fetch latest version from GitHub API
RELEASE_JSON=$(curl -sL --retry 2 "https://api.github.com/repos/cli/cli/releases/latest") || { log "Failed to fetch release info from GitHub API"; exit 2; }
if command -v jq &>/dev/null; then
    VERSION=$(echo "$RELEASE_JSON" | jq -r '.tag_name | ltrimstr("v")')
else
    VERSION=$(echo "$RELEASE_JSON" | sed -n 's/.*"tag_name": *"v\([^"]*\)".*/\1/p' | head -1)
fi
[[ -n "$VERSION" && "$VERSION" != "null" ]] || { log "Failed to install gh CLI: could not parse version from GitHub API response."; exit 2; }

log "Downloading v$VERSION..."
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

### -------- fetch and unpack the tarball

TAR_NAME="gh_${VERSION}_linux_${GH_ARCH}"
TAR_URL="https://github.com/cli/cli/releases/download/v${VERSION}/${TAR_NAME}.tar.gz"

curl -sL --retry 2 "$TAR_URL" | tar -xz -C "$TEMP_DIR" || { log "Failed to download/extract gh CLI"; exit 2; }

### -------- mv the binary to local bin

mv "$TEMP_DIR/${TAR_NAME}/bin/gh" "$LOCAL_BIN/" && chmod +x "$LOCAL_BIN/gh"
[[ -n "$CLAUDE_ENV_FILE" ]] && echo "export PATH=\"$LOCAL_BIN:\$PATH\"" >> "$CLAUDE_ENV_FILE"

log "Installed $(gh --version | head -1)"
echo "GitHub CLI installed: $(gh --version | head -1) - use gh for GitHub operations"
