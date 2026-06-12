#!/usr/bin/env bash
# Crea un'icona nella cartella dell'app e nel menu applicazioni (Linux)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESKTOP_FILE="$HOME/.local/share/applications/comfy-cloud-manager.desktop"
LOCAL_LINK="$SCRIPT_DIR/ComfyUI Cloud Manager.desktop"

cat > "$LOCAL_LINK" <<EOF
[Desktop Entry]
Name=ComfyUI Cloud Manager
Comment=Deploy scripts and manage ComfyUI on cloud GPU servers
Exec=bash "$SCRIPT_DIR/start.sh"
Icon=$SCRIPT_DIR/assets/icon.png
Terminal=false
Type=Application
Categories=Utility;
EOF

chmod +x "$LOCAL_LINK"

# Aggiunge anche al menu applicazioni di sistema
mkdir -p "$HOME/.local/share/applications"
cp "$LOCAL_LINK" "$DESKTOP_FILE"

echo "Shortcut created in app folder: $LOCAL_LINK"
echo "You can move it anywhere — it will keep working."
echo "Also added to application menu."
