#!/bin/bash

# Configuration
START_TIME=$(date +%s)
KERNEL_NAME="Anubis-X3"
ZIPNAME="$KERNEL_NAME$(date '+%Y%m%d-%H%M').zip"
TC_DIR="$HOME/tc/proton-clang"
DEFCONFIG="vendor/x3-perf_defconfig"
OUT_DIR="$HOME/kernel_build"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Functions
log() {
    echo "$1${NC}"
}

check_exit_code() {
    if [ $? -ne 0 ]; then
        log "${RED}Error: $1${NC}"
        exit 1
    fi
}

# Set up environment
export PATH="$TC_DIR/bin:$PATH"

# Ensure Proton clang is available
if ! [ -d "$TC_DIR" ]; then
    log "${YELLOW}Proton clang not found! Cloning to $TC_DIR...${NC}"
    if ! git clone -q --depth=1 --single-branch https://github.com/kdrag0n/proton-clang "$TC_DIR"; then
        log "${RED}Cloning failed! Aborting...${NC}"
        exit 1
    fi
fi

# Create output directory if it doesn't exist
mkdir -p "$OUT_DIR"
log "${GREEN}Output directory created: $OUT_DIR${NC}"

# Option to regenerate defconfig
if [[ $1 = "-r" || $1 = "--regen" ]]; then
    make O="$OUT_DIR" ARCH=arm64 $DEFCONFIG savedefconfig
    check_exit_code "Defconfig regeneration failed"
    cp "$OUT_DIR"/defconfig arch/arm64/configs/$DEFCONFIG
    log "${GREEN}Defconfig regenerated successfully.${NC}"
    exit
fi

# Option to clean build directory
if [[ $1 = "-c" || $1 = "--clean" ]]; then
    rm -rf "$OUT_DIR/out"
    log "${GREEN}Build directory cleaned.${NC}"
fi

# Create build directory if it doesn't exist
mkdir -p "$OUT_DIR/out"

# Configure kernel with selected defconfig
log "${GREEN}Configuring kernel...${NC}"
make O="$OUT_DIR/out" ARCH=arm64 $DEFCONFIG
check_exit_code "Kernel configuration failed"

# Start compilation
log "${GREEN}Starting compilation...${NC}"
make -j$(nproc --all) O="$OUT_DIR/out" ARCH=arm64 CC=clang LD=ld.lld AR=llvm-ar NM=llvm-nm OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnueabi- Image.gz dtbo.img 2>&1 | tee "$OUT_DIR/build_log.txt"

# Check if compilation succeeded
kernel="$OUT_DIR/out/arch/arm64/boot/Image.gz"
dtb="$OUT_DIR/out/arch/arm64/boot/dts/qcom/sm8150-v2.dtb"
dtbo="$OUT_DIR/out/arch/arm64/boot/dtbo.img"

if [ -f "$kernel" ] && [ -f "$dtb" ] && [ -f "$dtbo" ]; then
    log "${GREEN}Kernel compiled successfully! Zipping up...${NC}"

    # Check if AnyKernel3 directory exists
    if [ -d "$OUT_DIR/AnyKernel3" ]; then
        log "${GREEN}AnyKernel3 directory found. Updating...${NC}"
        cd "$OUT_DIR/AnyKernel3"
        git pull origin x3
        cd "$OUT_DIR"
    else
        # Clone AnyKernel3 repository
        if ! git clone -q https://github.com/akmacc/AnyKernel3 -b x3 "$OUT_DIR/AnyKernel3"; then
            log "${RED}Cloning AnyKernel3 repo failed! Aborting...${NC}"
            exit 1
        fi
    fi

    # Copy kernel, dtbo, and dtb to AnyKernel3 directory
    cp "$kernel" "$dtbo" "$OUT_DIR/AnyKernel3"
    cp "$dtb" "$OUT_DIR/AnyKernel3/dtb"

    # Clean up previous zip files
    rm -f "$OUT_DIR"/*zip

    # Zip up the files
    cd "$OUT_DIR/AnyKernel3" || exit
    rm -rf out/arch/arm64/boot
    zip -r9 "../$ZIPNAME" * -x .git README.md *placeholder
    cd "$OUT_DIR" || exit

    # Clean up AnyKernel3 directory
    rm -rf "$OUT_DIR/AnyKernel3"

    ELAPSED_TIME=$(( $(date +%s) - START_TIME ))
    ELAPSED_MINUTES=$(( ELAPSED_TIME / 60 ))
    ELAPSED_SECONDS=$(( ELAPSED_TIME % 60 ))

    log "${GREEN}Completed in $ELAPSED_MINUTES minute(s) and $ELAPSED_SECONDS second(s)!${NC}"

    # Upload the zip file
    upload_url=$(curl -F "file=@$OUT_DIR/$ZIPNAME" https://file.io/?expires=7d) # Set expiration to 7 days
    
    # Extract the file download URL from the response
    download_url=$(echo "$upload_url" | jq -r '.link')

    # Display the download URL
    log "${YELLOW}Uploaded ZIP file: $download_url${NC}"

    log "${YELLOW}The zip file will be saved in the following directory:${GREEN} $OUT_DIR/$ZIPNAME"
else
    log "${RED}Compilation failed!${NC}"
fi

