#!/bin/sh
set -eu

EXPECTED_DEVELOPER_DIR="/Applications/Xcode-27-beta-5.app/Contents/Developer"
DEFAULT_BUNDLE_ID="tv.nijssen.DKC2RecompTV"
DEFAULT_CORE_ID="dkc2"
DEFAULT_DATA_ROOT="Library/Caches/DKCRecompTV"

die() {
    status=$1
    shift
    printf 'ERROR: %s\n' "$*" >&2
    exit "$status"
}

usage() {
    printf 'Usage: DEVELOPER_DIR=%s %s ABSOLUTE_ROM_PATH DEVICE [BUNDLE_ID [CORE_ID [DATA_ROOT]]]\n' \
        "$EXPECTED_DEVELOPER_DIR" "$0" >&2
}

[ "$#" -ge 2 ] && [ "$#" -le 5 ] || {
    usage
    die 64 "ROM path, device, and optional title parameters are required"
}

rom_path=$1
device=$2
bundle_id=${3-${DKC2_BUNDLE_ID:-$DEFAULT_BUNDLE_ID}}
core_id=${4-${DKC2_CORE_ID:-$DEFAULT_CORE_ID}}
data_root=${5-${DKC2_DATA_ROOT:-$DEFAULT_DATA_ROOT}}
case "$rom_path" in
    /*)
        ;;
    *)
        die 64 "ROM path must be absolute"
        ;;
esac
[ -n "$device" ] || die 64 "device is required"
case "$bundle_id" in
    ""|*[!A-Za-z0-9.-]*)
        die 64 "bundle ID contains unsupported characters"
        ;;
esac
case "$core_id" in
    ""|.|..|[!A-Za-z0-9]*|*[!A-Za-z0-9._-]*)
        die 64 "core ID contains unsafe path characters: $core_id"
        ;;
esac
case "$data_root" in
    ""|/*|*[!A-Za-z0-9._/-]*|*//*)
        die 64 "data root contains unsupported path characters"
        ;;
esac
case "/$data_root/" in
    */./*|*/../*)
        die 64 "data root must not contain dot path components"
        ;;
esac

export DEVELOPER_DIR="${DEVELOPER_DIR:-$EXPECTED_DEVELOPER_DIR}"
command -v xcrun >/dev/null 2>&1 || die 2 "xcrun is required"
command -v shasum >/dev/null 2>&1 || die 2 "shasum is required"
command -v stat >/dev/null 2>&1 || die 2 "stat is required"
command -v realpath >/dev/null 2>&1 || die 2 "realpath is required"
command -v mktemp >/dev/null 2>&1 || die 2 "mktemp is required"
command -v cp >/dev/null 2>&1 || die 2 "cp is required"
command -v cmp >/dev/null 2>&1 || die 2 "cmp is required"
command -v awk >/dev/null 2>&1 || die 2 "awk is required"

script_dir=$(CDPATH= cd -P -- "$(dirname "$0")" && pwd -P)
repo_root=$(CDPATH= cd -P -- "$script_dir/../.." && pwd -P)
preflight="$repo_root/scripts/tvos/preflight.sh"
[ -x "$preflight" ] || die 2 "tvOS preflight is missing: $preflight"
rom_path=$(realpath "$rom_path") ||
    die 3 "could not resolve ROM path"

if [ "$core_id" = "$DEFAULT_CORE_ID" ]; then
    "$preflight" "$rom_path"
else
    [ -f "$rom_path" ] || die 3 "ROM file not found: $rom_path"
    [ -r "$rom_path" ] || die 3 "ROM file is not readable: $rom_path"
fi

stage_dir=$(mktemp -d "${TMPDIR:-/tmp}/dkc2-stage.XXXXXX")
trap 'rm -rf -- "$stage_dir"' EXIT
overlay="$stage_dir/Game.sfc"
readback="$stage_dir/readback/Game.sfc"
mkdir -p "$(dirname "$readback")"
cp "$rom_path" "$overlay"

expected_size=$(stat -f '%z' "$overlay")
expected_sha=$(shasum -a 256 -- "$overlay" | awk '{print $1}')
data_destination="$data_root/$core_id/Game.sfc"
xcrun devicectl device copy to \
    --device "$device" \
    --source "$overlay" \
    --destination "$data_destination" \
    --domain-type appDataContainer \
    --domain-identifier "$bundle_id" \
    --remove-existing-content false

xcrun devicectl device copy from \
    --device "$device" \
    --source "$data_destination" \
    --destination "$readback" \
    --domain-type appDataContainer \
    --domain-identifier "$bundle_id"

[ -f "$readback" ] || die 5 "device read-back did not produce Game.sfc"
actual_size=$(stat -f '%z' "$readback")
actual_sha=$(shasum -a 256 -- "$readback" | awk '{print $1}')
[ "$actual_size" = "$expected_size" ] ||
    die 5 "device read-back size mismatch"
[ "$actual_sha" = "$expected_sha" ] ||
    die 5 "device read-back SHA-256 mismatch"
cmp -s "$overlay" "$readback" ||
    die 5 "device read-back byte comparison failed"

printf 'PASS: staged Game.sfc into app data container\n'
printf 'BUNDLE: %s\n' "$bundle_id"
printf 'CORE_ID: %s\n' "$core_id"
printf 'DESTINATION: %s\n' "$data_destination"
printf 'SIZE: %s bytes\n' "$actual_size"
printf 'SHA-256: %s\n' "$actual_sha"
