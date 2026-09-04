#!/bin/sh
set -eu

EXPECTED_DEVELOPER_DIR="/Applications/Xcode-27-beta-5.app/Contents/Developer"
EXPECTED_XCODE_VERSION="Xcode 27.0"
EXPECTED_XCODE_BUILD="Build version 27A5237l"
EXPECTED_SDK_VERSION="27.0"
EXPECTED_ROM_SIZE="4194304"
DKC2_USA_V10_SHA256="35421a9af9dd011b40b91f792192af9f99c93201d8d394026bdfb42cbf2d8633"
DKC2_USA_REV1_SHA256="b79c2bb86f6fc76e1fc61c62fc16d51c664c381e58bc2933be643bbc4d8b610c"

die() {
    status=$1
    shift
    printf 'ERROR: %s\n' "$*" >&2
    exit "$status"
}

usage() {
    printf 'Usage: DEVELOPER_DIR=%s %s [--toolchain-only|ROM_PATH]\n' \
        "$EXPECTED_DEVELOPER_DIR" "$0" >&2
}

script_dir=$(CDPATH= cd -P -- "$(dirname "$0")" && pwd -P)
repo_root=$(CDPATH= cd -P -- "$script_dir/../.." && pwd -P)

if [ "${DEVELOPER_DIR-}" != "$EXPECTED_DEVELOPER_DIR" ]; then
    die 2 "DEVELOPER_DIR must be set exactly to $EXPECTED_DEVELOPER_DIR; global xcode-select is not used"
fi
if [ ! -d "$DEVELOPER_DIR" ]; then
    die 2 "Xcode developer directory not found: $DEVELOPER_DIR"
fi

command -v xcodebuild >/dev/null 2>&1 ||
    die 2 "xcodebuild is unavailable under DEVELOPER_DIR"
command -v xcrun >/dev/null 2>&1 ||
    die 2 "xcrun is unavailable under DEVELOPER_DIR"
command -v shasum >/dev/null 2>&1 ||
    die 2 "shasum is required"
command -v stat >/dev/null 2>&1 ||
    die 2 "stat is required"
command -v realpath >/dev/null 2>&1 ||
    die 2 "realpath is required"

xcode_version_output=$(xcodebuild -version 2>&1) ||
    die 2 "xcodebuild -version failed: $xcode_version_output"
xcode_version=$(printf '%s\n' "$xcode_version_output" | sed -n '1p')
xcode_build=$(printf '%s\n' "$xcode_version_output" | sed -n '2p')
[ "$xcode_version" = "$EXPECTED_XCODE_VERSION" ] ||
    die 2 "expected $EXPECTED_XCODE_VERSION, got: $xcode_version_output"
[ "$xcode_build" = "$EXPECTED_XCODE_BUILD" ] ||
    die 2 "expected $EXPECTED_XCODE_BUILD, got: $xcode_version_output"

tvos_sdk_version=$(xcrun --sdk appletvos --show-sdk-version 2>&1) ||
    die 2 "tvOS SDK lookup failed: $tvos_sdk_version"
tvos_sim_sdk_version=$(xcrun --sdk appletvsimulator --show-sdk-version 2>&1) ||
    die 2 "tvOS Simulator SDK lookup failed: $tvos_sim_sdk_version"
[ "$tvos_sdk_version" = "$EXPECTED_SDK_VERSION" ] ||
    die 2 "expected tvOS SDK $EXPECTED_SDK_VERSION, got $tvos_sdk_version"
[ "$tvos_sim_sdk_version" = "$EXPECTED_SDK_VERSION" ] ||
    die 2 "expected tvOS Simulator SDK $EXPECTED_SDK_VERSION, got $tvos_sim_sdk_version"

tvos_sdk_path=$(xcrun --sdk appletvos --show-sdk-path 2>&1) ||
    die 2 "tvOS SDK path lookup failed: $tvos_sdk_path"
tvos_sim_sdk_path=$(xcrun --sdk appletvsimulator --show-sdk-path 2>&1) ||
    die 2 "tvOS Simulator SDK path lookup failed: $tvos_sim_sdk_path"
[ -d "$tvos_sdk_path" ] ||
    die 2 "tvOS SDK path does not exist: $tvos_sdk_path"
[ -d "$tvos_sim_sdk_path" ] ||
    die 2 "tvOS Simulator SDK path does not exist: $tvos_sim_sdk_path"

printf 'PASS: %s (%s)\n' "$xcode_version" "$xcode_build"
printf 'DEVELOPER_DIR: %s\n' "$DEVELOPER_DIR"
printf 'tvOS SDK: %s (%s)\n' "$tvos_sdk_version" "$tvos_sdk_path"
printf 'tvOS Simulator SDK: %s (%s)\n' "$tvos_sim_sdk_version" "$tvos_sim_sdk_path"

if [ "${1-}" = "--toolchain-only" ]; then
    [ "$#" -eq 1 ] || {
        usage
        die 64 "--toolchain-only does not accept another argument"
    }
    printf 'PASS: ROM check skipped by explicit --toolchain-only\n'
    exit 0
fi

[ "$#" -le 1 ] || {
    usage
    die 64 "expected one ROM path or --toolchain-only"
}
rom_path=${1:-${DKC2_ROM-}}
[ -n "$rom_path" ] ||
    die 64 "ROM path required: pass it as the first argument or set DKC2_ROM"
[ -f "$rom_path" ] || die 3 "ROM not found: $rom_path"
[ -r "$rom_path" ] || die 3 "ROM is not readable: $rom_path"

rom_path=$(realpath "$rom_path") ||
    die 3 "cannot resolve ROM path: $rom_path"
case "$rom_path" in
    "$repo_root"|"$repo_root"/*)
        die 4 "ROM must remain outside the repository: $rom_path"
        ;;
esac

rom_size=$(stat -f '%z' "$rom_path") ||
    die 3 "cannot read ROM size: $rom_path"
rom_sha256_output=$(shasum -a 256 -- "$rom_path") ||
    die 3 "cannot calculate ROM SHA-256: $rom_path"
rom_sha256=$(printf '%s\n' "$rom_sha256_output" | sed -n '1s/[[:space:]].*$//p')
if [ "$rom_size" != "$EXPECTED_ROM_SIZE" ]; then
    die 4 "no accepted DKC2 USA profile: expected a $EXPECTED_ROM_SIZE-byte headerless ROM, got $rom_size bytes"
fi

case "$rom_sha256" in
    "$DKC2_USA_V10_SHA256")
        rom_profile="DKC2 USA v1.0"
        ;;
    "$DKC2_USA_REV1_SHA256")
        rom_profile="DKC2 USA Rev 1/v1.1"
        ;;
    *)
        die 4 "no accepted DKC2 USA SHA-256 profile: $rom_sha256"
        ;;
esac

printf 'PASS: accepted private %s ROM\n' "$rom_profile"
printf 'ROM: %s bytes, SHA-256 %s\n' "$rom_size" "$rom_sha256"
