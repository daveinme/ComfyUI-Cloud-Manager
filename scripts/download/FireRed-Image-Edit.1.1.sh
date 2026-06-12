#!/bin/bash

# =============================================================================
# Script download modelli FireRed-Image-Edit 1.1 per ComfyUI
# Totale: ~20GB
# =============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warn()    { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error()   { echo -e "${RED}❌ $1${NC}"; }

if [ -d "/workspace/runpod-slim/ComfyUI" ]; then
    COMFYUI_DIR="/workspace/runpod-slim/ComfyUI"
elif [ -d "/workspace/ComfyUI" ]; then
    COMFYUI_DIR="/workspace/ComfyUI"
elif [ -d "$HOME/ComfyUI" ]; then
    COMFYUI_DIR="$HOME/ComfyUI"
elif [ -d "/opt/ComfyUI" ]; then
    COMFYUI_DIR="/opt/ComfyUI"
elif [ -d "/app/ComfyUI" ]; then
    COMFYUI_DIR="/app/ComfyUI"
else
    read -rp "ComfyUI path: " COMFYUI_DIR
    [ -d "$COMFYUI_DIR" ] || { log_error "Directory $COMFYUI_DIR not found!"; exit 1; }
fi

log_info "ComfyUI found at: $COMFYUI_DIR"
[ -n "$HF_TOKEN" ] || { echo "❌ HF_TOKEN is not set — set it in Settings"; exit 1; }
export HF_TOKEN

check_dependencies() {
    log_info "Checking dependencies..."
    if ! command -v pip &> /dev/null; then
        log_error "pip not found."; exit 1
    fi
    if ! command -v huggingface-cli &> /dev/null; then
        log_info "Installing huggingface_hub..."
        pip install -q huggingface_hub
    fi
    log_success "Dependencies OK"
}

create_directories() {
    log_info "Creating model directories..."
    mkdir -p "${COMFYUI_DIR}/models/diffusion_models"
    mkdir -p "${COMFYUI_DIR}/models/text_encoders"
    mkdir -p "${COMFYUI_DIR}/models/vae"
    mkdir -p "${COMFYUI_DIR}/models/loras"
    log_success "Directories ready"
}

download_model() {
    local repo=$1
    local file=$2
    local dest_dir=$3
    local filename=$(basename "$file")
    local dest="${dest_dir}/${filename}"

    if [ -f "$dest" ]; then
        log_warn "$filename already exists ($(du -h "$dest" | cut -f1))"
        return 0
    fi

    log_info "Downloading $filename..."
    huggingface-cli download "$repo" "$file" \
        --local-dir "$dest_dir" \
        --local-dir-use-symlinks False

    if [ -f "$dest" ]; then
        log_success "$filename downloaded ($(du -h "$dest" | cut -f1))"
    else
        log_error "Download failed for $filename"; return 1
    fi
}

download_all_models() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║      FireRed-Image-Edit 1.1 model download (ComfyUI)        ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""

    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│ 1/4 - VAE qwen_image_vae - ~254MB                          │"
    echo "└─────────────────────────────────────────────────────────────┘"
    download_model "FireRedTeam/FireRed-Image-Edit-1.0-ComfyUI" \
        "qwen_image_vae.safetensors" \
        "${COMFYUI_DIR}/models/vae"

    echo ""
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│ 2/4 - Text Encoder Qwen 2.5 VL 7B FP8 - ~6GB              │"
    echo "└─────────────────────────────────────────────────────────────┘"
    download_model "Comfy-Org/HunyuanVideo_1.5_repackaged" \
        "split_files/text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors" \
        "${COMFYUI_DIR}/models/text_encoders"

    echo ""
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│ 3/4 - Lightning LoRa 8-steps v1.0 - ~1GB                  │"
    echo "└─────────────────────────────────────────────────────────────┘"
    download_model "FireRedTeam/FireRed-Image-Edit-1.0-ComfyUI" \
        "FireRed-Image-Edit-1.0-Lightning-8steps-v1.0.safetensors" \
        "${COMFYUI_DIR}/models/loras"

    echo ""
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│ 4/4 - FireRed 1.1 Transformer - ~13GB                      │"
    echo "└─────────────────────────────────────────────────────────────┘"
    download_model "FireRedTeam/FireRed-Image-Edit-1.1-ComfyUI" \
        "FireRed-Image-Edit-1.1-transformer.safetensors" \
        "${COMFYUI_DIR}/models/diffusion_models"
}

verify_installation() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║           INSTALLATION VERIFY                                ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""

    local all_ok=true

    chk() {
        [ -f "$1" ] \
            && log_success "$2: $(du -h "$1" | cut -f1)" \
            || { log_error "$2: MISSING"; all_ok=false; }
    }

    chk "${COMFYUI_DIR}/models/vae/qwen_image_vae.safetensors"                                    "VAE"
    chk "${COMFYUI_DIR}/models/text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors"              "Text Encoder Qwen 2.5 VL 7B"
    chk "${COMFYUI_DIR}/models/loras/FireRed-Image-Edit-1.0-Lightning-8steps-v1.0.safetensors"   "Lightning LoRa 8-steps"
    chk "${COMFYUI_DIR}/models/diffusion_models/FireRed-Image-Edit-1.1-transformer.safetensors"  "FireRed 1.1 Transformer"

    echo ""
    if [ "$all_ok" = true ]; then
        log_success "All models installed successfully!"
    else
        log_error "Some models are missing. Re-run the script."; return 1
    fi
}

main() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║    FireRed-Image-Edit 1.1 model download for COMFYUI        ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""

    check_dependencies
    create_directories
    download_all_models
    verify_installation
}

main "$@"
