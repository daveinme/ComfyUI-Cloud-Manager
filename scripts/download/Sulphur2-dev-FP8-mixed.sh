#!/bin/bash
set -e

# =============================================================================
# Sulphur-2 — solo modello video LTX2.3
# GPU 24GB (VastAI) — FP8-mixed (~29.2GB checkpoint)
# Totale stimato: ~43GB storage
# =============================================================================

[ -n "$HF_TOKEN" ]      || { echo "❌ HF_TOKEN is not set — set it in Settings"; exit 1; }
[ -n "$CIVITAI_TOKEN" ] || { echo "❌ CIVITAI_TOKEN is not set — set it in Settings"; exit 1; }

if   [ -d "/workspace/runpod-slim/ComfyUI" ]; then D="/workspace/runpod-slim/ComfyUI/models"
elif [ -d "/workspace/ComfyUI" ]; then D="/workspace/ComfyUI/models"
elif [ -d "$HOME/ComfyUI" ];      then D="$HOME/ComfyUI/models"
elif [ -d "/opt/ComfyUI" ];       then D="/opt/ComfyUI/models"
elif [ -d "/app/ComfyUI" ];       then D="/app/ComfyUI/models"
else
    read -rp "ComfyUI/models path: " D
    [ -d "$D" ] || { echo "❌ Directory not found"; exit 1; }
fi
echo "📂 Models: $D"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
ok()   { echo -e "${GREEN}✅ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }

dl() {
    local dir="$1" url="$2" name="${3:-$(basename "$2" | cut -d'?' -f1)}"
    local dest="$dir/$name"
    if [ -f "$dest" ]; then warn "already present: $name ($(du -h "$dest" | cut -f1))"; return 0; fi
    info "⬇ $name"
    wget --header="Authorization: Bearer $HF_TOKEN" \
         --progress=bar:force --show-progress --timeout=300 --tries=3 \
         -O "$dest.tmp" "$url" && mv "$dest.tmp" "$dest"
    ok "$name ($(du -h "$dest" | cut -f1))"
}

mkdir -p "$D/checkpoints" "$D/text_encoders" "$D/vae" "$D/loras" "$D/latent_upscale_models"

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║   Sulphur-2  ·  LTX2.3  ·  Solo Video  ·  GPU 24GB        ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

echo "┌─────────────────────────────────────────────────────────────┐"
echo "│ 1/5  Checkpoint Sulphur-2 dev FP8-mixed  (~29.2GB)         │"
echo "└─────────────────────────────────────────────────────────────┘"
dl "$D/checkpoints" \
   "https://huggingface.co/SulphurAI/Sulphur-2-base/resolve/main/sulphur_dev_fp8mixed.safetensors"

echo ""
echo "┌─────────────────────────────────────────────────────────────┐"
echo "│ 2/5  Text encoder Gemma 3 12B FP4  (~9.45GB)               │"
echo "└─────────────────────────────────────────────────────────────┘"
dl "$D/text_encoders" \
   "https://huggingface.co/Comfy-Org/ltx-2/resolve/main/split_files/text_encoders/gemma_3_12B_it_fp4_mixed.safetensors"

echo ""
echo "┌─────────────────────────────────────────────────────────────┐"
echo "│ 3/5  VAE LTX2.3 BF16  (~1.45GB)                           │"
echo "└─────────────────────────────────────────────────────────────┘"
dl "$D/vae" \
   "https://huggingface.co/Kijai/LTX2.3_comfy/resolve/main/vae/LTX23_video_vae_bf16.safetensors"

echo ""
echo "┌─────────────────────────────────────────────────────────────┐"
echo "│ 4/5  LoRA distillata 4-step  (~662MB)                      │"
echo "└─────────────────────────────────────────────────────────────┘"
dl "$D/loras" \
   "https://huggingface.co/SulphurAI/Sulphur-2-base/resolve/main/distill_loras/ltx-2.3-22b-distilled-lora-1.1_fro90_ceil72_condsafe.safetensors"

echo ""
echo "┌─────────────────────────────────────────────────────────────┐"
echo "│ 5/5  Upscaler spaziale x2  (~1GB)                          │"
echo "└─────────────────────────────────────────────────────────────┘"
dl "$D/latent_upscale_models" \
   "https://huggingface.co/Lightricks/LTX-2.3/resolve/main/ltx-2.3-spatial-upscaler-x2-1.1.safetensors"

echo ""
echo "┌─────────────────────────────────────────────────────────────┐"
echo "│ 6/9  LoRA VBVR I2V 390K R32  (~554MB)                     │"
echo "│      LiconStudio — fisica avanzata, causalità, motion      │"
echo "└─────────────────────────────────────────────────────────────┘"
dl "$D/loras" \
   "https://huggingface.co/LiconStudio/Ltx2.3-VBVR-lora-I2V/resolve/main/Ltx2.3-Licon-VBVR-I2V-390K-R32.safetensors"

echo ""
echo "┌─────────────────────────────────────────────────────────────┐"
echo "│ 7/10 IC-LoRA Union Control ref0.5  (~1GB)                  │"
echo "│      Lightricks — conditioning I2V (pose/depth/canny)      │"
echo "└─────────────────────────────────────────────────────────────┘"
dl "$D/loras" \
   "https://huggingface.co/Lightricks/LTX-2.3-22b-IC-LoRA-Union-Control/resolve/main/ltx-2.3-22b-ic-lora-union-control-ref0.5.safetensors"

echo ""
echo "┌─────────────────────────────────────────────────────────────┐"
echo "│ 8/10 BFS Face Swap — rank adaptive fro 098  (~1GB)         │"
echo "│      Alissonerdx — face swap LTX-2.3, primaria             │"
echo "└─────────────────────────────────────────────────────────────┘"
dl "$D/loras" \
   "https://huggingface.co/Alissonerdx/BFS-Best-Face-Swap-Video/resolve/main/ltx-2.3/head_swap_v3_rank_adaptive_fro_098.safetensors"

echo ""
echo "┌─────────────────────────────────────────────────────────────┐"
echo "│ 9/10 BFS Face Swap — rank 64  (~1GB)                       │"
echo "│      Alissonerdx — face swap LTX-2.3, alternativa          │"
echo "└─────────────────────────────────────────────────────────────┘"
dl "$D/loras" \
   "https://huggingface.co/Alissonerdx/BFS-Best-Face-Swap-Video/resolve/main/ltx-2.3/head_swap_v3_rank_64.safetensors"

echo ""
echo "┌─────────────────────────────────────────────────────────────┐"
echo "│ +1  Audio VAE (LTXV Audio VAE Loader)  (~29.6GB)           │"
echo "│     checkpoint ufficiale Lightricks FP8                    │"
echo "└─────────────────────────────────────────────────────────────┘"
dl "$D/checkpoints" \
   "https://huggingface.co/Lightricks/LTX-2.3-fp8/resolve/main/ltx-2.3-22b-dev-fp8.safetensors"

echo ""
echo "┌─────────────────────────────────────────────────────────────┐"
echo "│ +1  LTX 2.3 Enhancers (CivitAI)                            │"
echo "└─────────────────────────────────────────────────────────────┘"
REDIRECT_URL=$(curl -sI -L -H "Authorization: Bearer ${CIVITAI_TOKEN}" -H "User-Agent: Mozilla/5.0" -w "%{url_effective}" -o /dev/null "https://civitai.red/api/download/models/2849716?type=Model&format=SafeTensor")
dest="$D/loras/ltx23-enhancers.safetensors"
if [ -f "$dest" ]; then warn "already present: ltx23-enhancers.safetensors"; else curl -L --progress-bar -o "$dest" "$REDIRECT_URL" && ok "ltx23-enhancers.safetensors"; fi

echo ""
echo "┌─────────────────────────────────────────────────────────────┐"
echo "│ Sulphur experimental LoRA v1  (experimental)               │"
echo "└─────────────────────────────────────────────────────────────┘"
dl "$D/loras" \
   "https://huggingface.co/SulphurAI/Sulphur-2-base/resolve/main/experimental/sulphur_experimental_lora_v1.safetensors"

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  VERIFY                                                     ║"
echo "╚══════════════════════════════════════════════════════════════╝"
chk() { [ -f "$1" ] && ok "$2  →  $(du -h "$1" | cut -f1)" || warn "$2  →  MISSING"; }
chk "$D/checkpoints/sulphur_dev_fp8mixed.safetensors"                                          "Sulphur-2 FP8-mixed"
chk "$D/text_encoders/gemma_3_12B_it_fp4_mixed.safetensors"                                   "Gemma 3 12B FP4"
chk "$D/vae/LTX23_video_vae_bf16.safetensors"                                                  "VAE LTX2.3"
chk "$D/loras/ltx-2.3-22b-distilled-lora-1.1_fro90_ceil72_condsafe.safetensors"               "LoRA distillata 4-step"
chk "$D/loras/sulphur_experimental_lora_v1.safetensors"                                       "Sulphur experimental LoRA v1"
chk "$D/latent_upscale_models/ltx-2.3-spatial-upscaler-x2-1.1.safetensors"                   "Upscaler x2"
chk "$D/loras/Ltx2.3-Licon-VBVR-I2V-390K-R32.safetensors"                                   "LoRA VBVR 390K"
chk "$D/loras/ltx-2.3-22b-ic-lora-union-control-ref0.5.safetensors"                          "IC-LoRA Union Control"
chk "$D/loras/head_swap_v3_rank_adaptive_fro_098.safetensors"                                 "BFS Face Swap rank adaptive"
chk "$D/loras/head_swap_v3_rank_64.safetensors"                                               "BFS Face Swap rank 64"
chk "$D/checkpoints/ltx-2.3-22b-dev-fp8.safetensors"                                         "Audio VAE (Lightricks FP8)"
# Nodo custom LTX Aspect Selector
CN="${D%/models}/custom_nodes"
mkdir -p "$CN"
NODE="$CN/ltx_aspect_selector.py"
if [ -f "$NODE" ]; then warn "already present: ltx_aspect_selector.py"
else
    info "⬇ custom node: ltx_aspect_selector.py"
    wget --header="Authorization: Bearer $HF_TOKEN" -O "$NODE" \
        "https://huggingface.co/datasets/daveinme/custom_node/resolve/main/ltx_aspect_selector.py"
    ok "ltx_aspect_selector.py"
fi

echo ""
ok "Estimated total: ~68GB"
echo "  Start: python main.py --normalvram --listen 0.0.0.0 --port 8188"
