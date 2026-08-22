#!/usr/bin/env bash

SECONDS=0

DEVICE="lavender"
DEVICE_NAME="Redmi Note 7"
DEFCONFIG="vendor/xiaomi/lavender_defconfig"

TC_DIR="$(pwd)/tc/clang-r596125"
export PATH="$TC_DIR/bin:$PATH"

AK3_REPO="https://github.com/LavenderLabz/AnyKernel3"
AK3_BRANCH="master"
AK3_DIR="$(pwd)/AnyKernel3"

OUT_DIR="$(pwd)/out"
BOOT_DIR="$OUT_DIR/arch/arm64/boot"
KERNEL_IMG="$BOOT_DIR/Image.gz-dtb"

BUILD_KSU=0
BUILD_SUSFS=0
ZIPNAME_PREFIX="SouthWest-NG-${DEVICE}-$(date '+%Y%m%d-%H%M')"

for arg in "$@"; do
    if [[ "$arg" == "--ksu" ]]; then
        BUILD_KSU=1
    elif [[ "$arg" == "--susfs" ]]; then
        BUILD_SUSFS=1
        BUILD_KSU=1
    elif [[ "$arg" == "--clean" || "$arg" == "-c" ]]; then
        rm -rf out
    elif [[ "$arg" == "--regen" || "$arg" == "-r" ]]; then
        mkdir -p out
        make O=out ARCH=arm64 "$DEFCONFIG" savedefconfig
        cp out/defconfig "arch/arm64/configs/$DEFCONFIG"
        exit 0
    elif [[ "$arg" == "--regen-full" || "$arg" == "-rf" ]]; then
        mkdir -p out
        make O=out ARCH=arm64 "$DEFCONFIG"
        cp out/.config "arch/arm64/configs/$DEFCONFIG"
        exit 0
    fi
done

if [ "$BUILD_SUSFS" -eq 1 ]; then
    ZIPNAME_PREFIX="${ZIPNAME_PREFIX}-KSU-SUSFS"
elif [ "$BUILD_KSU" -eq 1 ]; then
    ZIPNAME_PREFIX="${ZIPNAME_PREFIX}-KSU"
fi

if test -z "$(git rev-parse --show-cdup 2>/dev/null)" &&
   head=$(git rev-parse --verify HEAD 2>/dev/null); then
    ZIPNAME="${ZIPNAME_PREFIX}-$(echo "$head" | cut -c1-8)"
else
    ZIPNAME="${ZIPNAME_PREFIX}"
fi

ZIPNAME="${ZIPNAME}.zip"

if ! [ -d "$TC_DIR" ]; then
    git clone --depth=1 "https://gitlab.com/crdroidandroid/android_prebuilts_clang_host_linux-x86_clang-r596125" "$TC_DIR" || exit 1
fi

export KBUILD_COMPILER_STRING="$("$TC_DIR/bin/clang" --version | head -n 1)"

MAKE_ARGS=(
    O=out
    ARCH=arm64
    CC=clang
    LD=ld.lld
    AS=llvm-as
    AR=llvm-ar
    NM=llvm-nm
    OBJCOPY=llvm-objcopy
    OBJDUMP=llvm-objdump
    STRIP=llvm-strip
    CROSS_COMPILE=aarch64-linux-gnu-
    CROSS_COMPILE_ARM32=arm-linux-gnueabi-
    LLVM=1
    LLVM_IAS=1
)

mkdir -p out
make "${MAKE_ARGS[@]}" "$DEFCONFIG" || exit 1

if [ "$BUILD_KSU" -eq 1 ]; then
    echo "[*] Fetching ReSukiSU driver..."
    curl -LSs "https://raw.githubusercontent.com/ReSukiSU/ReSukiSU/main/kernel/setup.sh" | bash
    echo "[*] Injecting KernelSU configs dynamically..."
    echo "CONFIG_KSU=y" >> out/.config
    echo "CONFIG_KSU_MANUAL_HOOK=y" >> out/.config

    if [ "$BUILD_SUSFS" -eq 1 ]; then
        echo "[*] Enabling SUSFS configs (ReSukiSU has built-in SUSFS support)..."
        cat << 'EOF' >> out/.config
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
CONFIG_KSU_SUSFS_ENABLE_LOG=y
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
CONFIG_KSU_SUSFS_SUS_MAP=y
EOF
    fi
fi

make "${MAKE_ARGS[@]}" olddefconfig || exit 1

make -j"$(nproc --all)" "${MAKE_ARGS[@]}" Image.gz-dtb || exit 1

if ! [ -f "$KERNEL_IMG" ]; then
    exit 1
fi

rm -rf AnyKernel3
git clone -q --depth=1 -b "$AK3_BRANCH" "$AK3_REPO" AnyKernel3 || exit 1

cp "$KERNEL_IMG" AnyKernel3/Image.gz-dtb
rm -rf out/arch/arm64/boot

cd AnyKernel3 || exit 1
zip -r9 "../$ZIPNAME" * -x .git README.md "*placeholder*"
cd ..
rm -rf AnyKernel3

echo "[✓] Done in $((SECONDS / 60))m $((SECONDS % 60))s"
echo "[✓] Zip: $ZIPNAME"
