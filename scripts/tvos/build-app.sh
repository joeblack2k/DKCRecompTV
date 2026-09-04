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
    printf 'Usage: DEVELOPER_DIR=%s %s ROM_PATH [appletvos|appletvsimulator]\n' \
        "$EXPECTED_DEVELOPER_DIR" "$0" >&2
    printf '       %s ROM_PATH --sdk appletvos|appletvsimulator\n' "$0" >&2
}

script_dir=$(CDPATH= cd -P -- "$(dirname "$0")" && pwd -P)
repo_root=$(CDPATH= cd -P -- "$script_dir/../.." && pwd -P)
preflight="$repo_root/scripts/tvos/preflight.sh"
generator="$repo_root/scripts/generate_snesrecomp.py"

rom_path=""
sdk="appletvos"
positional_sdk_seen=0
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
            [ "$positional_sdk_seen" -eq 0 ] || die 64 "SDK was specified twice"
            sdk=$2
            shift 2
            ;;
        --*)
            usage
            die 64 "unknown option: $1"
            ;;
        *)
            if [ -z "$rom_path" ]; then
                rom_path=$1
            elif [ "$positional_sdk_seen" -eq 0 ]; then
                sdk=$1
                positional_sdk_seen=1
            else
                usage
                die 64 "expected one ROM path and one optional SDK"
            fi
            shift
            ;;
    esac
done

[ -n "$rom_path" ] || {
    usage
    die 64 "ROM path is required"
}
case "$sdk" in
    appletvos|appletvsimulator)
        ;;
    *)
        usage
        die 64 "SDK must be appletvos or appletvsimulator: $sdk"
        ;;
esac

export DEVELOPER_DIR="${DEVELOPER_DIR:-$EXPECTED_DEVELOPER_DIR}"
command -v cmake >/dev/null 2>&1 || die 2 "cmake is required"
command -v ninja >/dev/null 2>&1 || die 2 "ninja is required"
command -v python3 >/dev/null 2>&1 || die 2 "python3 is required"
command -v xcrun >/dev/null 2>&1 || die 2 "xcrun is required"
[ -x "$preflight" ] || die 2 "tvOS preflight is missing: $preflight"
[ -f "$generator" ] || die 2 "snesrecomp generator is missing: $generator"

"$preflight" "$rom_path"
python3 "$generator" \
    --rom "$rom_path" \
    --snesrecomp-root "$repo_root/snesrecomp"

sdk_path=$(xcrun --sdk "$sdk" --show-sdk-path) ||
    die 2 "could not resolve SDK path for $sdk"
[ -d "$sdk_path" ] || die 2 "SDK path does not exist: $sdk_path"
clang=$(xcrun --sdk "$sdk" --find clang) ||
    die 2 "could not resolve clang for $sdk"
clangxx=$(xcrun --sdk "$sdk" --find clang++) ||
    die 2 "could not resolve clang++ for $sdk"

build_root="$repo_root/tvos/build"
core_build="$build_root/core-xcode27-$sdk"
app_build="$build_root/app-xcode27-ninja-$sdk"
mkdir -p "$build_root"

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
[ -f "$core_archive" ] || die 2 "core archive was not built: $core_archive"

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
    -DDKC2_SOURCE_ROOT="$repo_root"
cmake --build "$app_build" --config Release --target DKCRecompTV

app_path=$(find "$app_build" -type d -name '*.app' -print -quit)
[ -n "$app_path" ] || die 2 "built tvOS app bundle was not found in $app_build"

printf 'PASS: built unsigned tvOS app\n'
printf 'SDK: %s (%s)\n' "$sdk" "$sdk_path"
printf 'CORE_ARCHIVE: %s\n' "$core_archive"
printf 'APP_PATH: %s\n' "$app_path"
