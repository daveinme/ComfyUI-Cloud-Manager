#!/bin/bash

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
    [ -d "$COMFYUI_DIR" ] || { echo "❌ Directory not found"; exit 1; }
fi
log_info "ComfyUI found at: $COMFYUI_DIR"
[ -n "$HF_TOKEN" ] || { echo "❌ HF_TOKEN is not set — set it in Settings"; exit 1; }
export HF_TOKEN

DIFFUSION_REPO="Comfy-Org/z_image_turbo"
DIFFUSION_FILE="split_files/diffusion_models/z_image_turbo_bf16.safetensors"
TEXTENC_REPO="Comfy-Org/z_image_turbo"
TEXTENC_FILE="split_files/text_encoders/qwen_3_4b_fp8_mixed.safetensors"
VAE_REPO="Comfy-Org/z_image_turbo"
VAE_FILE="split_files/vae/ae.safetensors"
LIGHTNING_REPO="tarn59/pixel_art_style_lora_z_image_turbo"
LIGHTNING_FILE="pixel_art_style_z_image_turbo.safetensors"

check_dependencies() {
    log_info "Checking dependencies..."
    if ! command -v wget &> /dev/null; then
        log_error "wget not found."; exit 1
    fi
    log_success "Dependencies OK"
}

create_directories() {
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
    wget --header="Authorization: Bearer ${HF_TOKEN}" \
        "https://huggingface.co/${repo}/resolve/main/${file}" \
        -O "$dest" --show-progress

    if [ -f "$dest" ]; then
        log_success "$filename downloaded ($(du -h "$dest" | cut -f1))"
    else
        log_error "Download failed for $filename"; return 1
    fi
}

download_all_models() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║        DOWNLOAD MODELLI Z-Image-Turbo (Comfy-Org)           ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    log_info "Total to download: ~20GB (FP8 optimized)"
    echo ""

    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│ 1/4 - Z Image Turbo Diffusion BF16 - ~13GB                 │"
    echo "└─────────────────────────────────────────────────────────────┘"
    download_model "$DIFFUSION_REPO" "$DIFFUSION_FILE" "${COMFYUI_DIR}/models/diffusion_models"

    echo ""
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│ 2/4 - Qwen 3.4B FP8 Mixed Text Encoder - ~6GB              │"
    echo "└─────────────────────────────────────────────────────────────┘"
    download_model "$TEXTENC_REPO" "$TEXTENC_FILE" "${COMFYUI_DIR}/models/text_encoders"

    echo ""
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│ 3/4 - VAE - ~254MB                                         │"
    echo "└─────────────────────────────────────────────────────────────┘"
    download_model "$VAE_REPO" "$VAE_FILE" "${COMFYUI_DIR}/models/vae"

    echo ""
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│ 4/4 - Pixel Art Style LoRA (optional)                      │"
    echo "└─────────────────────────────────────────────────────────────┘"
    download_model "$LIGHTNING_REPO" "$LIGHTNING_FILE" "${COMFYUI_DIR}/models/loras"
}

verify_installation() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║           INSTALLATION VERIFY                                ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""

    local all_ok=true

    [ -f "${COMFYUI_DIR}/models/diffusion_models/z_image_turbo_bf16.safetensors" ] \
        && log_success "Diffusion Model BF16: $(du -h "${COMFYUI_DIR}/models/diffusion_models/z_image_turbo_bf16.safetensors" | cut -f1)" \
        || { log_error "Diffusion Model BF16: MISSING"; all_ok=false; }

    [ -f "${COMFYUI_DIR}/models/text_encoders/qwen_3_4b_fp8_mixed.safetensors" ] \
        && log_success "Text Encoder Qwen 3.4B: $(du -h "${COMFYUI_DIR}/models/text_encoders/qwen_3_4b_fp8_mixed.safetensors" | cut -f1)" \
        || { log_error "Text Encoder: MISSING"; all_ok=false; }

    [ -f "${COMFYUI_DIR}/models/vae/ae.safetensors" ] \
        && log_success "VAE: $(du -h "${COMFYUI_DIR}/models/vae/ae.safetensors" | cut -f1)" \
        || { log_error "VAE: MISSING"; all_ok=false; }

    [ -f "${COMFYUI_DIR}/models/loras/pixel_art_style_z_image_turbo.safetensors" ] \
        && log_success "LoRA (opzionale): $(du -h "${COMFYUI_DIR}/models/loras/pixel_art_style_z_image_turbo.safetensors" | cut -f1)" \
        || log_warn "LoRA: not downloaded (optional)"

    echo ""
    if [ "$all_ok" = true ]; then
        log_success "All essential models installed successfully!"
    else
        log_error "Some models are missing. Re-run the script."; return 1
    fi
}

main() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║      Z-Image-Turbo model download for COMFYUI               ║"
    echo "║      Comfy-Org FP8 - Total: ~20GB                          ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""

    check_dependencies
    create_directories
    download_all_models
    verify_installation
}

main "$@"
