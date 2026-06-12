#!/usr/bin/env bash
# ============================================================
#  ComfyUI Cloud Manager — one-click install & launch
#  Works on Linux and macOS
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✅ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
err()  { echo -e "${RED}❌ $1${NC}"; exit 1; }

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║        ComfyUI Cloud Manager — Setup                ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# ── 1. Check Node.js ─────────────────────────────────────────
if ! command -v node &>/dev/null; then
    warn "Node.js not found."
    echo ""
    echo "  Please install Node.js (v18 or newer) from:"
    echo "  https://nodejs.org/en/download"
    echo ""
    if command -v xdg-open &>/dev/null; then
        xdg-open "https://nodejs.org/en/download" &>/dev/null &
    elif command -v open &>/dev/null; then
        open "https://nodejs.org/en/download"
    fi
    err "Install Node.js and re-run this script."
fi

NODE_VER=$(node -e "process.stdout.write(process.versions.node)")
MAJOR=$(echo "$NODE_VER" | cut -d. -f1)
if [ "$MAJOR" -lt 18 ]; then
    warn "Node.js $NODE_VER found — v18 or newer required."
    echo "  Download a newer version from: https://nodejs.org/en/download"
    err "Please upgrade Node.js and re-run."
fi
ok "Node.js $NODE_VER"

# ── 2. Install dependencies ───────────────────────────────────
FIRST_RUN=false
if [ ! -d "node_modules" ]; then
    FIRST_RUN=true
    echo ""
    echo "Installing dependencies (first run, may take a minute)..."
    npm install --prefer-offline 2>&1 | tail -5
    ok "Dependencies installed"
else
    ok "Dependencies already present"
fi

# ── 3. Desktop shortcut (Linux, first run only) ───────────────
if [ "$FIRST_RUN" = true ] && [ "$(uname)" = "Linux" ]; then
    echo ""
    bash "$SCRIPT_DIR/create-shortcut.sh" && ok "Desktop shortcut created — use start.sh next time"
fi

# ── 4. Launch app ─────────────────────────────────────────────
echo ""
ok "Launching ComfyUI Cloud Manager..."
echo ""
npm start
