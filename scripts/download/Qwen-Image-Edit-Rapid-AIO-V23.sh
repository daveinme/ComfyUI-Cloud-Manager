#!/bin/bash

# =============================================================================
# Script download modelli Qwen-Image-Edit AIO (All-In-One) per ComfyUI
# Base model: Phr00t/Qwen-Image-Edit-Rapid-AIO (NSFW v23)
# Accessori: Text Encoder FP8, VAE, Lightning LoRa (Comfy-Org)
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

# =============================================================================
# CONFIGURAZIONE
# =============================================================================
if [ -d "/workspace/runpod-slim/ComfyUI" ]; then
    COMFYUI_DIR="/workspace/runpod-slim/ComfyUI"
elif [ -d "/workspace/ComfyUI" ]; then
    COMFYUI_DIR="/workspace/ComfyUI"
elif [ -d "$HOME/workspace/ComfyUI" ]; then
    COMFYUI_DIR="$HOME/workspace/ComfyUI"
elif [ -d "/opt/ComfyUI" ]; then
    COMFYUI_DIR="/opt/ComfyUI"
elif [ -d "/app/ComfyUI" ]; then
    COMFYUI_DIR="/app/ComfyUI"
else
    log_error "ComfyUI directory not found automatically"
    read -p "Enter the ComfyUI path (e.g. /home/user/ComfyUI): " COMFYUI_DIR
    if [ ! -d "$COMFYUI_DIR" ]; then
        log_error "Directory $COMFYUI_DIR does not exist!"
        exit 1
    fi
fi

log_info "ComfyUI found at: $COMFYUI_DIR"
[ -n "$HF_TOKEN" ] || { echo "❌ HF_TOKEN is not set — set it in Settings"; exit 1; }
export HF_TOKEN

# Base model AIO (download diretto da URL)
AIO_URL="https://huggingface.co/Phr00t/Qwen-Image-Edit-Rapid-AIO/resolve/main/v23/Qwen-Rapid-AIO-NSFW-v23.safetensors"
AIO_FILENAME="Qwen-Rapid-AIO-NSFW-v23.safetensors"

# Modelli accessori via HuggingFace hub
TEXTENC_REPO="Comfy-Org/Qwen-Image_ComfyUI"
TEXTENC_FILE="split_files/text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors"

VAE_REPO="Comfy-Org/Qwen-Image_ComfyUI"
VAE_FILE="split_files/vae/qwen_image_vae.safetensors"

LIGHTNING_REPO="landon2022/F2P"
LIGHTNING_FILE="Qwen-Image-Edit-F2P.safetensors"

# =============================================================================
# FUNZIONI
# =============================================================================

check_dependencies() {
    log_info "Checking dependencies..."

    if ! command -v pip &> /dev/null; then
        log_error "pip not found. Install Python before proceeding."
        exit 1
    fi

    if ! command -v huggingface-cli &> /dev/null; then
        log_info "Installing huggingface_hub..."
        pip install -q huggingface_hub
        export PATH="$PATH:$(python3 -c 'import site; print(site.getusersitepackages())')/../../bin"
        hash -r
    fi

    if ! command -v wget &> /dev/null && ! command -v curl &> /dev/null; then
        log_error "wget or curl required to download the AIO base model."
        exit 1
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

download_url() {
    local url=$1
    local dest=$2
    local filename=$(basename "$dest")

    if [ -f "$dest" ]; then
        log_warn "$filename already exists ($(du -h "$dest" | cut -f1))"
        return 0
    fi

    log_info "Downloading $filename..."
    if command -v wget &> /dev/null; then
        wget --header="Authorization: Bearer ${HF_TOKEN}" \
             --progress=bar:force \
             -O "$dest" "$url"
    else
        curl -L \
             -H "Authorization: Bearer ${HF_TOKEN}" \
             --progress-bar \
             -o "$dest" "$url"
    fi

    if [ -f "$dest" ]; then
        log_success "$filename downloaded ($(du -h "$dest" | cut -f1))"
    else
        log_error "Download failed for $filename"
        return 1
    fi
}

download_hf() {
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
    python3 -c "
import os, shutil
from huggingface_hub import hf_hub_download
dest = '$dest_dir/$filename'
hf_hub_download(repo_id='$repo', filename='$file', local_dir='$dest_dir', local_dir_use_symlinks=False, force_download=False)
downloaded = os.path.join('$dest_dir', '$file')
if os.path.isfile(downloaded) and downloaded != dest:
    shutil.move(downloaded, dest)
    subdir = os.path.join('$dest_dir', '$file'.split('/')[0])
    shutil.rmtree(subdir, ignore_errors=True)
"

    if [ -f "$dest" ]; then
        log_success "$filename downloaded ($(du -h "$dest" | cut -f1))"
    else
        log_error "Download failed for $filename"
        return 1
    fi
}

download_all_models() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║      DOWNLOAD MODELLI Qwen-Image-Edit AIO (Phr00t v23)      ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    log_info "Total to download: ~15GB"
    echo ""

    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│ 1/4 - Base Model AIO NSFW v23 - ~8GB                       │"
    echo "└─────────────────────────────────────────────────────────────┘"
    download_url "$AIO_URL" \
        "${COMFYUI_DIR}/models/diffusion_models/${AIO_FILENAME}"

    echo ""
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│ 2/4 - Text Encoder Qwen 2.5 VL 7B FP8 - ~6GB              │"
    echo "└─────────────────────────────────────────────────────────────┘"
    download_hf "$TEXTENC_REPO" "$TEXTENC_FILE" \
        "${COMFYUI_DIR}/models/text_encoders"

    echo ""
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│ 3/4 - VAE - ~254MB                                         │"
    echo "└─────────────────────────────────────────────────────────────┘"
    download_hf "$VAE_REPO" "$VAE_FILE" \
        "${COMFYUI_DIR}/models/vae"

    echo ""
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│ 4/4 - Lightning LoRa 4-steps (optional) - ~1GB             │"
    echo "└─────────────────────────────────────────────────────────────┘"
    download_hf "$LIGHTNING_REPO" "$LIGHTNING_FILE" \
        "${COMFYUI_DIR}/models/loras"
}

verify_installation() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║           INSTALLATION VERIFY                                ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""

    local all_ok=true

    if [ -f "${COMFYUI_DIR}/models/diffusion_models/${AIO_FILENAME}" ]; then
        log_success "Base Model AIO: $(du -h "${COMFYUI_DIR}/models/diffusion_models/${AIO_FILENAME}" | cut -f1)"
    else
        log_error "Base Model AIO: MISSING"; all_ok=false
    fi

    if [ -f "${COMFYUI_DIR}/models/text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors" ]; then
        log_success "Text Encoder: $(du -h "${COMFYUI_DIR}/models/text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors" | cut -f1)"
    else
        log_error "Text Encoder: MISSING"; all_ok=false
    fi

    if [ -f "${COMFYUI_DIR}/models/vae/qwen_image_vae.safetensors" ]; then
        log_success "VAE: $(du -h "${COMFYUI_DIR}/models/vae/qwen_image_vae.safetensors" | cut -f1)"
    else
        log_error "VAE: MISSING"; all_ok=false
    fi

    if [ -f "${COMFYUI_DIR}/models/loras/Qwen-Image-Edit-F2P.safetensors" ]; then
        log_success "Lightning LoRa (opzionale): $(du -h "${COMFYUI_DIR}/models/loras/Qwen-Image-Edit-F2P.safetensors" | cut -f1)"
    else
        log_warn "Lightning LoRa: not downloaded (optional)"
    fi

    echo ""
    if [ "$all_ok" = true ]; then
        log_success "All essential models installed successfully!"
    else
        log_error "Some models are missing. Re-run the script."
        return 1
    fi
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║      Qwen-Image-Edit AIO model download for COMFYUI         ║"
    echo "║      Base: Phr00t AIO NSFW v23 + Text Enc + VAE + LoRa     ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""

    check_dependencies
    create_directories
    download_all_models
    verify_installation
}

main "$@"
