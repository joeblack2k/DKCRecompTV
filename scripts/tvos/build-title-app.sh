#!/bin/sh
set -eu

EXPECTED_DEVELOPER_DIR="/Applications/Xcode-27-beta-5.app/Contents/Developer"

die() {
    status=$1
    shift
    printf 'error: %s\n' "$*" >&2
    exit "$status"
}

usage() {
    printf 'Usage: DEVELOPER_DIR=%s %s {dkc1|dkc3} ROM_PATH [appletvos|appletvsimulator]\n' \
        "$EXPECTED_DEVELOPER_DIR" "$0" >&2
}

[ "$#" -ge 2 ] && [ "$#" -le 3 ] || {
    usage
    die 64 "title, ROM path, and optional SDK are required"
}

title=$1
rom_path=$2
sdk=${3:-appletvos}
case "$title" in
    dkc1)
        core_target="dkc1_tvos_core"
        core_function="dkc1_game_core"
        build_option="DKC1_BUILD_TVOS_CORE"
        bundle_id="tv.nijssen.DKC1RecompTV"
        product_name="DKC1 Recomp TV"
        executable_name="DKC1RecompTV"
        ;;
    dkc3)
        core_target="dkc3_tvos_core"
        core_function="dkc3_game_core"
        build_option="DKC3_BUILD_TVOS_CORE"
        bundle_id="tv.nijssen.DKC3RecompTV"
        product_name="DKC3 Recomp TV"
        executable_name="DKC3RecompTV"
        ;;
    *)
        die 64 "unsupported title: $title"
        ;;
esac
case "$sdk" in
    appletvos|appletvsimulator)
        ;;
    *)
        die 64 "SDK must be appletvos or appletvsimulator: $sdk"
        ;;
esac

script_dir=$(CDPATH= cd -P -- "$(dirname "$0")" && pwd -P)
repo_root=$(CDPATH= cd -P -- "$script_dir/../.." && pwd -P)
generator="$repo_root/scripts/generate_title_snesrecomp.py"
host_builder="$script_dir/build-app.sh"
export DEVELOPER_DIR="${DEVELOPER_DIR:-$EXPECTED_DEVELOPER_DIR}"

for tool in cmake ninja python3 xcrun; do
    command -v "$tool" >/dev/null 2>&1 || die 2 "$tool is required"
done
[ -f "$generator" ] || die 2 "title generator is missing: $generator"
[ -x "$host_builder" ] || die 2 "host builder is missing: $host_builder"

python3 "$generator" \
    --title "$title" \
    --rom "$rom_path" \
    --snesrecomp-root "$repo_root/snesrecomp"

clang=$(xcrun --sdk "$sdk" --find clang) ||
    die 2 "could not resolve clang for $sdk"
clangxx=$(xcrun --sdk "$sdk" --find clang++) ||
    die 2 "could not resolve clang++ for $sdk"
build_root="$repo_root/tvos/build"
core_build="$build_root/core-$title-xcode27-$sdk"
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
    -D"$build_option=ON"
cmake --build "$core_build" --target "$core_target" --config Release

core_archive="$core_build/lib$core_target.a"
[ -f "$core_archive" ] ||
    die 2 "core archive was not built: $core_archive"

"$host_builder" \
    --sdk "$sdk" \
    --core-archive "$core_archive" \
    --core-function "$core_function" \
    --bundle-id "$bundle_id" \
    --product-name "$product_name" \
    --executable-name "$executable_name"
