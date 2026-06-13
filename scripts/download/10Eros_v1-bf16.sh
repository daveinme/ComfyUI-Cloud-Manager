#!/bin/bash
set -e

# =============================================================================
# 10Eros — solo modello video LTX2.3
# GPU 48GB (A40) — BF16 full precision (~58GB checkpoint)
# =============================================================================

[ -n "$HF_TOKEN" ] || { echo "❌ HF_TOKEN is not set — set it in Settings"; exit 1; }

if   [ -d "/workspace/runpod-slim/ComfyUI" ]; then D="/workspace/runpod-slim/ComfyUI/models"
elif [ -d "/workspace/ComfyUI" ];            then D="/workspace/ComfyUI/models"
elif [ -d "$HOME/ComfyUI" ];                 then D="$HOME/ComfyUI/models"
elif [ -d "/opt/ComfyUI" ];                  then D="/opt/ComfyUI/models"
elif [ -d "/app/ComfyUI" ];                  then D="/app/ComfyUI/models"
else
    read -rp "ComfyUI/models path: " D
    [ -d "$D" ] || { echo "❌ Directory not found"; exit 1; }
fi
echo "📂 Models: $D"

command -v hf &>/dev/null || pip install -q huggingface_hub

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
ok()   { echo -e "${GREEN}✅ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }

dl() {
    local dir="$1" url="$2" name="${3:-$(basename "$2" | cut -d'?' -f1)}"
    local dest="$dir/$name"
    if [ -f "$dest" ]; then warn "already present: $name ($(du -h "$dest" | cut -f1))"; return 0; fi
    info "⬇ $name"
    local repo path_in_repo
    repo=$(echo "$url" | sed 's|https://huggingface.co/||;s|/resolve/main/.*||')
    path_in_repo=$(echo "$url" | sed 's|.*resolve/main/||')
    HUGGING_FACE_HUB_TOKEN="$HF_TOKEN" HF_HUB_DISABLE_XET=1 \
        hf download "$repo" "$path_in_repo" \
        --local-dir "$dir" --token "$HF_TOKEN"
    ok "$name ($(du -h "$dest" | cut -f1))"
}

mkdir -p "$D/checkpoints" "$D/text_encoders" "$D/vae" "$D/loras" "$D/latent_upscale_models"

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║   10Eros v1  ·  LTX2.3  ·  BF16  ·  GPU 48GB (A40)        ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

echo "┌─────────────────────────────────────────────────────────────┐"
echo "│ 1/6  Checkpoint 10Eros BF16  (~58GB)                       │"
echo "└─────────────────────────────────────────────────────────────┘"
dl "$D/checkpoints" \
   "https://huggingface.co/TenStrip/LTX2.3-10Eros/resolve/main/10Eros_v1_bf16.safetensors"

echo ""
echo "┌─────────────────────────────────────────────────────────────┐"
echo "│ 2/6  Text encoder Gemma 3 12B FP4  (~4GB)                  │"
echo "└─────────────────────────────────────────────────────────────┘"
dl "$D/text_encoders" \
   "https://huggingface.co/Comfy-Org/ltx-2/resolve/main/split_files/text_encoders/gemma_3_12B_it_fp4_mixed.safetensors"

echo ""
echo "┌─────────────────────────────────────────────────────────────┐"
echo "│ 3/6  VAE LTX2.3 BF16  (~300MB)                            │"
echo "└─────────────────────────────────────────────────────────────┘"
dl "$D/vae" \
   "https://huggingface.co/Kijai/LTX2.3_comfy/resolve/main/vae/LTX23_video_vae_bf16.safetensors"

echo ""
echo "┌─────────────────────────────────────────────────────────────┐"
echo "│ 4/6  Distilled LoRA 4-step  (~662MB)                       │"
echo "└─────────────────────────────────────────────────────────────┘"
dl "$D/loras" \
   "https://huggingface.co/SulphurAI/Sulphur-2-base/resolve/main/distill_loras/ltx-2.3-22b-distilled-lora-1.1_fro90_ceil72_condsafe.safetensors"

echo ""
echo "┌─────────────────────────────────────────────────────────────┐"
echo "│ 5/6  Upscaler spaziale x2  (~1GB)                          │"
echo "└─────────────────────────────────────────────────────────────┘"
dl "$D/latent_upscale_models" \
   "https://huggingface.co/Lightricks/LTX-2.3/resolve/main/ltx-2.3-spatial-upscaler-x2-1.1.safetensors"

echo ""
echo "┌─────────────────────────────────────────────────────────────┐"
echo "│ 6/6  Sulphur experimental LoRA v1  (experimental)          │"
echo "└─────────────────────────────────────────────────────────────┘"
dl "$D/loras" \
   "https://huggingface.co/SulphurAI/Sulphur-2-base/resolve/main/experimental/sulphur_experimental_lora_v1.safetensors"

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  VERIFY                                                     ║"
echo "╚══════════════════════════════════════════════════════════════╝"
chk() { [ -f "$1" ] && ok "$2  →  $(du -h "$1" | cut -f1)" || warn "$2  →  MISSING"; }
chk "$D/checkpoints/10Eros_v1_bf16.safetensors"                                               "10Eros BF16"
chk "$D/text_encoders/gemma_3_12B_it_fp4_mixed.safetensors"                                   "Gemma 3 12B FP4"
chk "$D/vae/LTX23_video_vae_bf16.safetensors"                                                  "VAE LTX2.3"
chk "$D/loras/ltx-2.3-22b-distilled-lora-1.1_fro90_ceil72_condsafe.safetensors"               "Distilled LoRA 4-step"
chk "$D/latent_upscale_models/ltx-2.3-spatial-upscaler-x2-1.1.safetensors"                   "Upscaler x2"
chk "$D/loras/sulphur_experimental_lora_v1.safetensors"                                       "Sulphur experimental LoRA v1"

# 10S-Comfy-nodes (TenStrip)
CN="${D%/models}/custom_nodes"
mkdir -p "$CN"
NODE_10S="$CN/10S-Comfy-nodes"
if [ -d "$NODE_10S" ]; then
    warn "already present: 10S-Comfy-nodes ($(cd "$NODE_10S" && git log -1 --format='%h %s' 2>/dev/null || echo 'not git'))"
else
    info "⬇ cloning custom nodes: TenStrip/10S-Comfy-nodes"
    git clone "https://github.com/TenStrip/10S-Comfy-nodes.git" "$NODE_10S"
    ok "10S-Comfy-nodes"
fi
if [ -f "$NODE_10S/requirements.txt" ]; then
    info "Installing 10S-Comfy-nodes dependencies..."
    pip install -q -r "$NODE_10S/requirements.txt" && ok "dependencies installed"
fi

# Custom node LTX Aspect Selector
NODE="$CN/ltx_aspect_selector.py"
if [ -f "$NODE" ]; then warn "already present: ltx_aspect_selector.py"
else
    info "⬇ custom node: ltx_aspect_selector.py"
    wget --header="Authorization: Bearer $HF_TOKEN" -O "$NODE" \
        "https://huggingface.co/datasets/daveinme/custom_node/resolve/main/ltx_aspect_selector.py"
    ok "ltx_aspect_selector.py"
fi

echo ""
ok "Estimated total: ~64GB"
echo "  Start: python main.py --normalvram --listen 0.0.0.0 --port 8188"
