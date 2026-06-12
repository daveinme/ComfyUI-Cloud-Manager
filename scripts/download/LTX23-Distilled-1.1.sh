#!/bin/bash
set -e

[ -n "$HF_TOKEN" ]      || { echo "❌ HF_TOKEN is not set — set it in Settings"; exit 1; }
[ -n "$CIVITAI_TOKEN" ] || { echo "❌ CIVITAI_TOKEN is not set — set it in Settings"; exit 1; }
export HF_TOKEN
HF="https://huggingface.co"
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

mkdir -p "$D/diffusion_models" "$D/vae" "$D/text_encoders" "$D/latent_upscale_models" "$D/loras"

dl() {
    local dest_dir="$1"
    local url="$2"
    local filename=$(basename "$url" | cut -d'?' -f1)
    local dest="${dest_dir}/${filename}"
    if [ -f "$dest" ]; then
        echo "⏭ already present: $filename"
        return 0
    fi
    echo "⬇ downloading: $filename"
    wget --progress=bar:force --header="Authorization: Bearer $HF_TOKEN" -O "$dest" "$url"
}

dl_civitai() {
    local dest_dir="$1" url="$2" name="$3"
    local dest="$dest_dir/$name"
    if [ -f "$dest" ]; then echo "⏭ already present: $name"; return 0; fi
    echo "⬇ downloading: $name"
    REDIRECT_URL=$(curl -sI -L -H "Authorization: Bearer ${CIVITAI_TOKEN}" -H "User-Agent: Mozilla/5.0" -w "%{url_effective}" -o /dev/null "$url")
    curl -L --progress-bar -o "$dest" "$REDIRECT_URL"
}

# Modello principale 22B Distilled 1.1 (VAE incluso)
dl "$D/diffusion_models" "$HF/Lightricks/LTX-2.3/resolve/main/ltx-2.3-22b-distilled-1.1.safetensors"

# Modello dev FP8 base (~29.6GB)
dl "$D/checkpoints" "$HF/Lightricks/LTX-2.3-fp8/resolve/main/ltx-2.3-22b-dev-fp8.safetensors"

# Text encoder Gemma 3 12B (fp4 mixed, versione leggera per ComfyUI)
dl "$D/loras" "$HF/Comfy-Org/ltx-2/resolve/main/split_files/loras/gemma-3-12b-it-abliterated_heretic_lora_rank64_bf16.safetensors"
dl "$D/text_encoders" "$HF/Comfy-Org/ltx-2/resolve/main/split_files/text_encoders/gemma_3_12B_it_fp4_mixed.safetensors"

# Upscaler spaziale
dl "$D/latent_upscale_models" "$HF/Lightricks/LTX-2.3/resolve/main/ltx-2.3-spatial-upscaler-x2-1.1.safetensors"

# LoRA distilled 1.1
dl "$D/loras" "$HF/Lightricks/LTX-2.3/resolve/main/ltx-2.3-22b-distilled-lora-384-1.1.safetensors"
dl "$D/loras" "$HF/Kijai/LTX2.3_comfy/resolve/main/loras/ltx-2.3-22b-distilled-lora-dynamic_fro09_avg_rank_105_bf16.safetensors"

# VAE separati (audio + video) e tiny VAE
dl "$D/vae" "$HF/Kijai/LTX2.3_comfy/resolve/main/vae/LTX23_video_vae_bf16.safetensors"
dl "$D/vae" "$HF/unsloth/LTX-2.3-GGUF/resolve/main/vae/ltx-2.3-22b-dev_audio_vae.safetensors"
dl "$D/vae" "$HF/Kijai/LTX2.3_comfy/resolve/main/vae/taeltx2_3.safetensors"

# Text projection
dl "$D/text_encoders" "$HF/Kijai/LTX2.3_comfy/resolve/main/text_encoders/ltx-2.3_text_projection_bf16.safetensors"

# IC-LoRA per preservazione identità e motion tracking
dl "$D/loras" "$HF/Lightricks/LTX-2.3-22b-IC-LoRA-Union-Control/resolve/main/ltx-2.3-22b-ic-lora-union-control-ref0.5.safetensors?download=true"

# ID-LoRA per coerenza viso
dl "$D/loras" "https://huggingface.co/AviadDahan/LTX-2.3-ID-LoRA-CelebVHQ-3K/resolve/main/lora_weights.safetensors"

# LTX 2.3 Enhancers (CivitAI)
dl_civitai "$D/loras" "https://civitai.red/api/download/models/2849716?type=Model&format=SafeTensor" "ltx23-enhancers.safetensors"

# Nodo custom WhatDreamsCost
CN="${D%/models}/custom_nodes"
mkdir -p "$CN"
if [ -d "$CN/WhatDreamsCost-ComfyUI" ]; then
    echo "⏭ already present: WhatDreamsCost-ComfyUI"
else
    echo "⬇ cloning: WhatDreamsCost-ComfyUI"
    git clone https://github.com/WhatDreamscost/WhatDreamsCost-ComfyUI "$CN/WhatDreamsCost-ComfyUI"
fi

# Nodo custom LTX Aspect Selector
CN="${D%/models}/custom_nodes"
mkdir -p "$CN"
NODE="$CN/ltx_aspect_selector.py"
if [ -f "$NODE" ]; then
    echo "⏭ already present: ltx_aspect_selector.py"
else
    echo "⬇ custom node: ltx_aspect_selector.py"
    wget --header="Authorization: Bearer $HF_TOKEN" -O "$NODE" \
        "https://huggingface.co/datasets/daveinme/custom_node/resolve/main/ltx_aspect_selector.py"
fi

echo ""
echo "✓ Download complete. All files are in $D"
