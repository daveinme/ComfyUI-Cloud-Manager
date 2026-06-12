#!/bin/bash

# =============================================================================
# Script download modelli Wan 2.2 I2V per ComfyUI già installato
# Versioni ottimizzate Comfy-Org (FP8)
#
# MODELLI E DIMENSIONI STIMATE:
#   Diffusion High Noise 14B FP8  ~14.0 GB  (diffusion_models/)
#   Diffusion Low Noise  14B FP8  ~14.0 GB  (diffusion_models/)
#   LoRA LightX2V Low Noise        ~0.3 GB  (loras/)
#   LoRA LightX2V High Noise       ~0.3 GB  (loras/)
#   VAE Wan 2.1                    ~0.4 GB  (vae/)
#   Text Encoder UMT5-XXL FP8     ~10.0 GB  (text_encoders/)
#   -----------------------------------------
#   TOTALE                        ~39.0 GB
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

if   [ -d "/workspace/runpod-slim/ComfyUI" ]; then MODELS_DIR="/workspace/runpod-slim/ComfyUI/models"
elif [ -d "/workspace/ComfyUI" ]; then MODELS_DIR="/workspace/ComfyUI/models"
elif [ -d "$HOME/ComfyUI" ];      then MODELS_DIR="$HOME/ComfyUI/models"
elif [ -d "/opt/ComfyUI" ];       then MODELS_DIR="/opt/ComfyUI/models"
elif [ -d "/app/ComfyUI" ];       then MODELS_DIR="/app/ComfyUI/models"
else
    read -rp "ComfyUI/models path: " MODELS_DIR
    [ -d "$MODELS_DIR" ] || { echo "❌ Directory not found"; exit 1; }
fi
echo "📂 Models: $MODELS_DIR"
[ -n "$HF_TOKEN" ] || { echo "❌ HF_TOKEN is not set — set it in Settings"; exit 1; }

log_info "Models directory: $MODELS_DIR"

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

    if [ -f "$dest" ]; then
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

download_all_models() {
    echo ""
    echo "=============================="
    echo " DOWNLOADING Wan 2.2 I2V models"
    echo "=============================="
    echo ""
    log_info "Total to download: ~39GB (FP8 optimized)"
    echo ""

    echo "--- 1/6 - Wan 2.2 I2V High Noise 14B FP8 ---"
    download_model "Comfy-Org/Wan_2.2_ComfyUI_Repackaged" \
        "split_files/diffusion_models/wan2.2_i2v_high_noise_14B_fp8_scaled.safetensors" \
        "${MODELS_DIR}/diffusion_models"

    echo ""
    echo "--- 2/6 - Wan 2.2 I2V Low Noise 14B FP8 ---"
    download_model "Comfy-Org/Wan_2.2_ComfyUI_Repackaged" \
        "split_files/diffusion_models/wan2.2_i2v_low_noise_14B_fp8_scaled.safetensors" \
        "${MODELS_DIR}/diffusion_models"

    echo ""
    echo "--- 3/6 - LightX2V LoRA Low Noise 4steps ---"
    download_model "Comfy-Org/Wan_2.2_ComfyUI_Repackaged" \
        "split_files/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_low_noise.safetensors" \
        "${MODELS_DIR}/loras"

    echo ""
    echo "--- 4/6 - LightX2V LoRA High Noise 4steps ---"
    download_model "Comfy-Org/Wan_2.2_ComfyUI_Repackaged" \
        "split_files/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_high_noise.safetensors" \
        "${MODELS_DIR}/loras"

    echo ""
    echo "--- 5/6 - Wan 2.1 VAE ---"
    download_model "Comfy-Org/Wan_2.2_ComfyUI_Repackaged" \
        "split_files/vae/wan_2.1_vae.safetensors" \
        "${MODELS_DIR}/vae"

    echo ""
    echo "--- 6/6 - UMT5 XXL FP8 Text Encoder ---"
    download_model "Comfy-Org/Wan_2.1_ComfyUI_repackaged" \
        "split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors" \
        "${MODELS_DIR}/text_encoders"
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

    chk "${MODELS_DIR}/diffusion_models/wan2.2_i2v_high_noise_14B_fp8_scaled.safetensors" "Diffusion High Noise 14B FP8"
    chk "${MODELS_DIR}/diffusion_models/wan2.2_i2v_low_noise_14B_fp8_scaled.safetensors"  "Diffusion Low Noise 14B FP8"
    chk "${MODELS_DIR}/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_low_noise.safetensors"    "LoRA LightX2V Low Noise"
    chk "${MODELS_DIR}/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_high_noise.safetensors"   "LoRA LightX2V High Noise"
    chk "${MODELS_DIR}/vae/wan_2.1_vae.safetensors"                                        "VAE Wan 2.1"
    chk "${MODELS_DIR}/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors"              "Text Encoder UMT5 XXL FP8"

    echo ""
    if [ "$all_ok" = true ]; then
        log_success "All models installed successfully!"
    else
        log_error "Some models are missing. Re-run the script."; return 1
    fi
}

main() {
    echo ""
    echo "=============================="
    echo " Wan 2.2 I2V model download"
    echo " Comfy-Org FP8 ~39GB"
    echo "=============================="
    echo ""

    check_dependencies
    create_directories
    download_all_models
    verify_installation
}

main "$@"
