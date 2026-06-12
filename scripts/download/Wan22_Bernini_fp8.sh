#!/bin/bash

# =============================================================================
# Script download modelli Wan 2.2 Bernini per ComfyUI già installato
# Versioni FP8 e4m3fn scaled (Kijai/WanVideo_comfy_fp8_scaled)
#
# MODELLI E DIMENSIONI STIMATE:
#   Bernini HIGH  14B FP8   ~15.6 GB  (diffusion_models/)
#   Bernini LOW   14B FP8   ~15.6 GB  (diffusion_models/)
#   VAE Wan 2.1              ~0.4 GB  (vae/)
#   Text Encoder UMT5 FP8  ~10.0 GB  (text_encoders/)
#   Lightning LoRA HIGH FP16 ~0.7 GB  (loras/)
#   Lightning LoRA LOW  FP16 ~0.7 GB  (loras/)
#   -----------------------------------------
#   TOTALE                  ~43.0 GB
#
# COMPATIBILITÀ:
#   - Vast.ai  (ComfyUI su /workspace o $HOME)
#   - RunPod   (ComfyUI su /workspace/runpod-slim/ComfyUI o /workspace/ComfyUI)
#
# RICHIEDE: ComfyUI installato + ComfyUI-Bernini custom node
#   https://github.com/AIMixer/ComfyUI-Bernini
# =============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO] $1${NC}"; }
log_success() { echo -e "${GREEN}[OK]   $1${NC}"; }
log_warn()    { echo -e "${YELLOW}[WARN] $1${NC}"; }
log_error()   { echo -e "${RED}[ERR]  $1${NC}"; }

# --- Auto-detect percorso ComfyUI/models ---
if   [ -d "/workspace/runpod-slim/ComfyUI" ]; then MODELS_DIR="/workspace/runpod-slim/ComfyUI/models"
elif [ -d "/workspace/ComfyUI" ];             then MODELS_DIR="/workspace/ComfyUI/models"
elif [ -d "$HOME/ComfyUI" ];                  then MODELS_DIR="$HOME/ComfyUI/models"
elif [ -d "/opt/ComfyUI" ];                   then MODELS_DIR="/opt/ComfyUI/models"
elif [ -d "/app/ComfyUI" ];                   then MODELS_DIR="/app/ComfyUI/models"
else
    read -rp "ComfyUI/models path: " MODELS_DIR
    [ -d "$MODELS_DIR" ] || { echo "❌ Directory not found"; exit 1; }
fi
echo "📂 Models: $MODELS_DIR"

[ -n "$HF_TOKEN" ] || { echo "❌ HF_TOKEN is not set — set it in Settings"; exit 1; }

# --- Funzioni ---

check_dependencies() {
    log_info "Checking dependencies..."
    if ! command -v wget &> /dev/null; then
        log_error "wget not found."; exit 1
    fi
    log_success "Dependencies OK"
}

create_directories() {
    log_info "Creating model directories..."
    mkdir -p "${MODELS_DIR}/diffusion_models"
    mkdir -p "${MODELS_DIR}/text_encoders"
    mkdir -p "${MODELS_DIR}/vae"
    mkdir -p "${MODELS_DIR}/loras"
    log_success "Directories ready"
}

download_model() {
    local repo=$1
    local file=$2
    local dest_dir=$3
    local filename=$(basename "$file")
    local dest="${dest_dir}/${filename}"
    local url="https://huggingface.co/${repo}/resolve/main/${file}"

    if [ -f "$dest" ] && [ "$(stat -c%s "$dest")" -gt 1000000 ]; then
        log_warn "$filename already exists ($(du -h "$dest" | cut -f1))"
        return 0
    fi

    log_info "Downloading $filename..."
    curl -L --progress-bar \
        -H "Authorization: Bearer ${HF_TOKEN}" \
        -o "$dest" "$url"

    local size=$(stat -c%s "$dest" 2>/dev/null || echo 0)
    if [ "$size" -gt 1000000 ]; then
        log_success "$filename downloaded ($(du -h "$dest" | cut -f1))"
    else
        log_error "Download failed for $filename (file too small: ${size} bytes)"
        rm -f "$dest"
        return 1
    fi
}

clone_or_update() {
    local name=$1
    local url=$2
    local dir=$3

    if [ -d "$dir" ]; then
        log_warn "${name} already installed, updating..."
        git -C "$dir" pull --ff-only || log_warn "git pull failed for ${name}, skipping update"
    else
        log_info "Installing ${name}..."
        git clone "$url" "$dir"
        log_success "${name} installed in $dir"
    fi
}

install_custom_nodes() {
    local COMFYUI_DIR
    COMFYUI_DIR="$(dirname "$MODELS_DIR")"
    local NODES_DIR="${COMFYUI_DIR}/custom_nodes"

    if ! command -v git &> /dev/null; then
        log_error "git not found — install custom nodes manually"
        return 1
    fi

    mkdir -p "$NODES_DIR"

    echo ""
    echo "=============================="
    echo " INSTALLING CUSTOM NODES"
    echo "=============================="
    echo ""

    clone_or_update "ComfyUI-BerniniTaskPrefix" \
        "https://github.com/daveinme/ComfyUI-BerniniTaskPrefix.git" \
        "${NODES_DIR}/ComfyUI-BerniniTaskPrefix"

    clone_or_update "ComfyUI-Bernini" \
        "https://github.com/AIMixer/ComfyUI-Bernini.git" \
        "${NODES_DIR}/ComfyUI-Bernini"

    clone_or_update "ComfyUI-VideoHelperSuite" \
        "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git" \
        "${NODES_DIR}/ComfyUI-VideoHelperSuite"

    clone_or_update "ComfyUI-KJNodes" \
        "https://github.com/kijai/ComfyUI-KJNodes.git" \
        "${NODES_DIR}/ComfyUI-KJNodes"
}

download_all_models() {
    echo ""
    echo "=============================="
    echo " DOWNLOAD MODELLI Wan 2.2 Bernini"
    echo "=============================="
    echo ""
    log_info "Total to download: ~43.0 GB (FP8 e4m3fn scaled + Lightning LoRA)"
    echo ""

    echo "--- 1/4 - Bernini HIGH 14B FP8 (~15.6 GB) ---"
    download_model "Kijai/WanVideo_comfy_fp8_scaled" \
        "Bernini/Wan22_Bernini_HIGH_fp8_e4m3fn_scaled.safetensors" \
        "${MODELS_DIR}/diffusion_models"

    echo ""
    echo "--- 2/4 - Bernini LOW 14B FP8 (~15.6 GB) ---"
    download_model "Kijai/WanVideo_comfy_fp8_scaled" \
        "Bernini/Wan22_Bernini_LOW_fp8_e4m3fn_scaled.safetensors" \
        "${MODELS_DIR}/diffusion_models"

    echo ""
    echo "--- 3/4 - Wan 2.1 VAE (~0.4 GB) ---"
    download_model "Comfy-Org/Wan_2.2_ComfyUI_Repackaged" \
        "split_files/vae/wan_2.1_vae.safetensors" \
        "${MODELS_DIR}/vae"

    echo ""
    echo "--- 4/4 - UMT5 XXL FP8 Text Encoder (~10 GB) ---"
    download_model "Comfy-Org/Wan_2.1_ComfyUI_repackaged" \
        "split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors" \
        "${MODELS_DIR}/text_encoders"

    echo ""
    echo "--- 5/6 - Lightning LoRA HIGH FP16 (~0.7 GB) ---"
    download_model "Kijai/WanVideo_comfy" \
        "LoRAs/Wan22-Lightning/old/Wan2.2-Lightning_I2V-A14B-4steps-lora_HIGH_fp16.safetensors" \
        "${MODELS_DIR}/loras"

    echo ""
    echo "--- 6/6 - Lightning LoRA LOW FP16 (~0.7 GB) ---"
    download_model "Kijai/WanVideo_comfy" \
        "LoRAs/Wan22-Lightning/old/Wan2.2-Lightning_I2V-A14B-4steps-lora_LOW_fp16.safetensors" \
        "${MODELS_DIR}/loras"
}

verify_installation() {
    echo ""
    echo "=============================="
    echo " INSTALLATION VERIFY"
    echo "=============================="
    echo ""

    local all_ok=true

    chk() {
        [ -f "$1" ] \
            && log_success "$2: $(du -h "$1" | cut -f1)" \
            || { log_error "$2: MISSING"; all_ok=false; }
    }

    chk "${MODELS_DIR}/diffusion_models/Wan22_Bernini_HIGH_fp8_e4m3fn_scaled.safetensors"              "Bernini HIGH FP8"
    chk "${MODELS_DIR}/diffusion_models/Wan22_Bernini_LOW_fp8_e4m3fn_scaled.safetensors"               "Bernini LOW FP8"
    chk "${MODELS_DIR}/vae/wan_2.1_vae.safetensors"                                                     "VAE Wan 2.1"
    chk "${MODELS_DIR}/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors"                           "Text Encoder UMT5 XXL FP8"
    chk "${MODELS_DIR}/loras/Wan2.2-Lightning_I2V-A14B-4steps-lora_HIGH_fp16.safetensors"              "Lightning LoRA HIGH FP16"
    chk "${MODELS_DIR}/loras/Wan2.2-Lightning_I2V-A14B-4steps-lora_LOW_fp16.safetensors"               "Lightning LoRA LOW FP16"

    echo ""
    if [ "$all_ok" = true ]; then
        log_success "All models installed successfully!"
        echo ""
        echo "  Next: restart ComfyUI and load a Bernini workflow."
        echo "  Example workflow: https://github.com/AIMixer/ComfyUI-Bernini"
    else
        log_error "Some models are missing. Re-run the script."; return 1
    fi
}

main() {
    echo ""
    echo "=============================="
    echo " Wan 2.2 BERNINI FP8 model download"
    echo " Kijai fp8_e4m3fn_scaled + Lightning LoRA ~43GB"
    echo "=============================="
    echo ""

    check_dependencies
    create_directories
    install_custom_nodes
    download_all_models
    verify_installation
}

main "$@"
