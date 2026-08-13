#!/usr/bin/env bash

SECONDS=0

DEVICE="lavender"
DEVICE_NAME="Redmi Note 7"
DEFCONFIG="vendor/xiaomi/sdm660_defconfig"

TC_DIR="$(pwd)/tc/clang-r596125"
export PATH="$TC_DIR/bin:$PATH"

AK3_REPO="https://github.com/LavenderLabz/AnyKernel3"
AK3_BRANCH="master"
AK3_DIR="$(pwd)/AnyKernel3"

OUT_DIR="$(pwd)/out"
BOOT_DIR="$OUT_DIR/arch/arm64/boot"
KERNEL_IMG="$BOOT_DIR/Image.gz"

BUILD_KSU=0
ZIPNAME_PREFIX="SouthWest-NG-${DEVICE}-$(date '+%Y%m%d-%H%M')"

for arg in "$@"; do
    if [[ "$arg" == "--ksu" ]]; then
        BUILD_KSU=1
        ZIPNAME_PREFIX="${ZIPNAME_PREFIX}-KSU"
    elif [[ "$arg" == "--clean" || "$arg" == "-c" ]]; then
        rm -rf out
    elif [[ "$arg" == "--regen" || "$arg" == "-r" ]]; then
        mkdir -p out
        make O=out ARCH=arm64 $DEFCONFIG savedefconfig
        cp out/defconfig arch/arm64/configs/vendor/xiaomi/sdm660_defconfig
        exit 0
    elif [[ "$arg" == "--regen-full" || "$arg" == "-rf" ]]; then
        mkdir -p out
        make O=out ARCH=arm64 $DEFCONFIG
        cp out/.config arch/arm64/configs/vendor/xiaomi/sdm660_defconfig
        exit 0
    fi
done

if test -z "$(git rev-parse --show-cdup 2>/dev/null)" &&
   head=$(git rev-parse --verify HEAD 2>/dev/null); then
    ZIPNAME="${ZIPNAME_PREFIX}-$(echo "$head" | cut -c1-8)"
else
    ZIPNAME="${ZIPNAME_PREFIX}"
fi
ZIPNAME="${ZIPNAME}.zip"

if ! [ -d "$TC_DIR" ]; then
    git clone --depth=1 \
        https://gitlab.com/crdroidandroid/android_prebuilts_clang_host_linux-x86_clang-r596125 \
        "$TC_DIR" || exit 1
fi

export KBUILD_COMPILER_STRING="$($TC_DIR/bin/clang --version | head -n 1)"
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
make "${MAKE_ARGS[@]}" vendor/xiaomi/sdm660_defconfig

echo "[*] Merging lavender.config..."
cat arch/arm64/configs/vendor/xiaomi/lavender.config >> out/.config

if [ "$BUILD_KSU" -eq 1 ]; then
    echo "[*] Fetching ReSukiSU driver..."
    curl -LSs "https://raw.githubusercontent.com/ReSukiSU/ReSukiSU/main/kernel/setup.sh" | bash
    echo "[*] Injecting KernelSU configs dynamically..."
    echo "CONFIG_KSU=y" >> out/.config
    echo "CONFIG_KSU_MANUAL_HOOK=y" >> out/.config
fi

make "${MAKE_ARGS[@]}" olddefconfig

make -j$(nproc --all) "${MAKE_ARGS[@]}" Image.gz

if ! [ -f "$KERNEL_IMG" ]; then
    exit 1
fi

rm -rf AnyKernel3
git clone -q -b "$AK3_BRANCH" "$AK3_REPO" AnyKernel3 || exit 1

cp "$KERNEL_IMG" AnyKernel3
rm -rf out/arch/arm64/boot

cd AnyKernel3 || exit 1
zip -r9 "../$ZIPNAME" * -x .git README.md "*placeholder*"
cd ..
rm -rf AnyKernel3

echo "[✓] Done in $((SECONDS / 60))m $((SECONDS % 60))s"
echo "[✓] Zip: $ZIPNAME"
