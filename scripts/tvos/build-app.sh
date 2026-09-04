#!/bin/sh
set -eu

EXPECTED_DEVELOPER_DIR="/Applications/Xcode-27-beta-5.app/Contents/Developer"

die() {
    status=$1
    shift
    printf 'ERROR: %s\n' "$*" >&2
    exit "$status"
}

usage() {
    printf 'Usage: DEVELOPER_DIR=%s %s [ROM_PATH] [appletvos|appletvsimulator]\n' \
        "$EXPECTED_DEVELOPER_DIR" "$0" >&2
    printf '       %s [ROM_PATH] --sdk appletvos|appletvsimulator\n' "$0" >&2
    printf '       Set DKC2_TVOS_CORE_ARCHIVE to use a prebuilt core without a ROM.\n' >&2
}

script_dir=$(CDPATH= cd -P -- "$(dirname "$0")" && pwd -P)
repo_root=$(CDPATH= cd -P -- "$script_dir/../.." && pwd -P)
preflight="$repo_root/scripts/tvos/preflight.sh"
generator="$repo_root/scripts/generate_snesrecomp.py"

rom_path=""
sdk="appletvos"
sdk_seen=0
core_archive=${DKC2_TVOS_CORE_ARCHIVE-}
core_function=${DKC2_TVOS_CORE_FUNCTION:-dkc2_game_core}
bundle_id=${DKC2_BUNDLE_ID:-tv.nijssen.DKC2RecompTV}
product_name=${DKC2_PRODUCT_NAME:-DKC2 Recomp TV}
executable_name=${DKC2_EXECUTABLE_NAME:-DKCRecompTV}
while [ "$#" -gt 0 ]; do
    case "$1" in
        --help|-h)
            usage
            exit 0
            ;;
        --sdk)
            [ "$#" -ge 2 ] || {
                usage
                die 64 "--sdk requires appletvos or appletvsimulator"
            }
            [ "$sdk_seen" -eq 0 ] || die 64 "SDK was specified twice"
            sdk=$2
            sdk_seen=1
            shift 2
            ;;
        --core-archive)
            [ "$#" -ge 2 ] || die 64 "--core-archive requires a path"
            core_archive=$2
            shift 2
            ;;
        --core-function)
            [ "$#" -ge 2 ] || die 64 "--core-function requires a C identifier"
            core_function=$2
            shift 2
            ;;
        --bundle-id)
            [ "$#" -ge 2 ] || die 64 "--bundle-id requires an identifier"
            bundle_id=$2
            shift 2
            ;;
        --product-name)
            [ "$#" -ge 2 ] || die 64 "--product-name requires a name"
            product_name=$2
            shift 2
            ;;
        --executable-name)
            [ "$#" -ge 2 ] || die 64 "--executable-name requires a name"
            executable_name=$2
            shift 2
            ;;
        --*)
            usage
            die 64 "unknown option: $1"
            ;;
        *)
            if [ -z "$rom_path" ]; then
                rom_path=$1
            elif [ "$sdk_seen" -eq 0 ]; then
                sdk=$1
                sdk_seen=1
            else
                usage
                die 64 "expected one optional ROM path and one optional SDK"
            fi
            shift
            ;;
    esac
done

case "$sdk" in
    appletvos|appletvsimulator)
        ;;
    *)
        usage
        die 64 "SDK must be appletvos or appletvsimulator: $sdk"
        ;;
esac
case "$core_function" in
    ""|[!A-Za-z_]*|*[!A-Za-z0-9_]*)
        die 64 "core function must be a C identifier: $core_function"
        ;;
esac
case "$bundle_id" in
    ""|*[!A-Za-z0-9.-]*)
        die 64 "bundle ID contains unsupported characters: $bundle_id"
        ;;
esac
[ -n "$product_name" ] ||
    die 64 "product name must not be empty"
case "$executable_name" in
    ""|*[!A-Za-z0-9._-]*)
        die 64 "executable name contains unsupported characters: $executable_name"
        ;;
esac

export DEVELOPER_DIR="${DEVELOPER_DIR:-$EXPECTED_DEVELOPER_DIR}"
command -v cmake >/dev/null 2>&1 || die 2 "cmake is required"
command -v ninja >/dev/null 2>&1 || die 2 "ninja is required"
command -v xcrun >/dev/null 2>&1 || die 2 "xcrun is required"

if [ -n "$core_archive" ]; then
    case "$core_archive" in
        /*)
            ;;
        *)
            die 64 "core archive path must be absolute"
            ;;
    esac
    [ -f "$core_archive" ] ||
        die 3 "core archive not found: $core_archive"
else
    [ -n "$rom_path" ] || {
        usage
        die 64 "ROM path is required when no core archive is supplied"
    }
    command -v python3 >/dev/null 2>&1 || die 2 "python3 is required"
    [ -x "$preflight" ] || die 2 "tvOS preflight is missing: $preflight"
    [ -f "$generator" ] || die 2 "snesrecomp generator is missing: $generator"
    "$preflight" "$rom_path"
    python3 "$generator" \
        --rom "$rom_path" \
        --snesrecomp-root "$repo_root/snesrecomp"
fi

sdk_path=$(xcrun --sdk "$sdk" --show-sdk-path) ||
    die 2 "could not resolve SDK path for $sdk"
[ -d "$sdk_path" ] || die 2 "SDK path does not exist: $sdk_path"
clang=$(xcrun --sdk "$sdk" --find clang) ||
    die 2 "could not resolve clang for $sdk"
clangxx=$(xcrun --sdk "$sdk" --find clang++) ||
    die 2 "could not resolve clang++ for $sdk"

build_root="$repo_root/tvos/build"
app_build="$build_root/app-xcode27-ninja-$sdk"
mkdir -p "$build_root"

if [ -z "$core_archive" ]; then
    core_build="$build_root/core-xcode27-$sdk"
    path_map_flags="-ffile-prefix-map=$repo_root=. -fdebug-prefix-map=$repo_root=. -fmacro-prefix-map=$repo_root=."
    cmake -S "$repo_root" -B "$core_build" -G Ninja \
        -DCMAKE_SYSTEM_NAME=tvOS \
        -DCMAKE_OSX_SYSROOT="$sdk" \
        -DCMAKE_OSX_ARCHITECTURES=arm64 \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_COMPILER="$clang" \
        -DCMAKE_CXX_COMPILER="$clangxx" \
        -DCMAKE_C_FLAGS="$path_map_flags" \
        -DCMAKE_CXX_FLAGS="$path_map_flags" \
        -DBUILD_TESTING=OFF \
        -DDKC2_BUILD_SNESRECOMP=OFF \
        -DDKC2_FETCH_SDL2=OFF \
        -DDKC2_BUILD_TVOS_CORE=ON \
        -DDKC2_SNESRECOMP_GEN_DIR="$repo_root/generated/snesrecomp"
    cmake --build "$core_build" --target dkc2_tvos_core --config Release
    core_archive="$core_build/libdkc2_tvos_core.a"
    [ -f "$core_archive" ] ||
        die 2 "core archive was not built: $core_archive"
fi

cmake -S "$repo_root/tvos/apple" -B "$app_build" -G Ninja \
    -DCMAKE_SYSTEM_NAME=tvOS \
    -DCMAKE_OSX_SYSROOT="$sdk" \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER="$clang" \
    -DCMAKE_CXX_COMPILER="$clangxx" \
    -DCMAKE_OBJCXX_COMPILER="$clangxx" \
    -DDKC2_TVOS_SDK="$sdk" \
    -DDKC2_TVOS_SDK_PATH="$sdk_path" \
    -DDKC2_TVOS_CORE_ARCHIVE="$core_archive" \
    -DDKC2_TVOS_CORE_FUNCTION="$core_function" \
    -DDKC2_BUNDLE_ID="$bundle_id" \
    -DDKC2_PRODUCT_NAME="$product_name" \
    -DDKC2_EXECUTABLE_NAME="$executable_name" \
    -DDKC2_SOURCE_ROOT="$repo_root"
cmake --build "$app_build" --config Release --target DKCRecompTV

app_path="$app_build/$executable_name.app"
[ -d "$app_path" ] ||
    die 2 "built tvOS app bundle was not found: $app_path"

printf 'PASS: built unsigned tvOS app\n'
printf 'SDK: %s (%s)\n' "$sdk" "$sdk_path"
printf 'CORE_ARCHIVE: %s\n' "$core_archive"
printf 'CORE_FUNCTION: %s\n' "$core_function"
printf 'BUNDLE_ID: %s\n' "$bundle_id"
printf 'PRODUCT_NAME: %s\n' "$product_name"
printf 'EXECUTABLE_NAME: %s\n' "$executable_name"
printf 'APP_PATH: %s\n' "$app_path"
