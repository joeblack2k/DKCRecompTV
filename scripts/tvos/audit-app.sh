#!/bin/sh
set -eu

EXPECTED_BUNDLE_ID="tv.nijssen.DKC2RecompTV"
EXPECTED_PRODUCT_NAME="DKC2 Recomp TV"
EXPECTED_VERSION="0.1.0"
EXPECTED_BUILD="1"

die() {
    status=$1
    shift
    printf 'ERROR: %s\n' "$*" >&2
    exit "$status"
}

usage() {
    printf 'Usage: %s APP_PATH [appletvos|appletvsimulator] [AUDIT_SYMBOL]\n' \
        "$0" >&2
}

[ "$#" -ge 1 ] && [ "$#" -le 3 ] || {
    usage
    die 64 "app path, optional SDK, and optional audit symbol are required"
}

app_path=$1
sdk=${2-}
EXPECTED_BUNDLE_ID=${DKC2_BUNDLE_ID:-$EXPECTED_BUNDLE_ID}
EXPECTED_PRODUCT_NAME=${DKC2_PRODUCT_NAME:-$EXPECTED_PRODUCT_NAME}
EXPECTED_CORE_SYMBOL=${3:-${DKC2_TVOS_AUDIT_SYMBOL:-${DKC2_TVOS_CORE_FUNCTION:-dkc2_game_core}}}
command -v lipo >/dev/null 2>&1 || die 2 "lipo is required"
command -v vtool >/dev/null 2>&1 || die 2 "vtool is required"
command -v nm >/dev/null 2>&1 || die 2 "nm is required"
command -v otool >/dev/null 2>&1 || die 2 "otool is required"
command -v plutil >/dev/null 2>&1 || die 2 "plutil is required"
command -v realpath >/dev/null 2>&1 || die 2 "realpath is required"
command -v find >/dev/null 2>&1 || die 2 "find is required"
command -v grep >/dev/null 2>&1 || die 2 "grep is required"

case "$sdk" in
    ""|appletvos|appletvsimulator)
        ;;
    *)
        usage
        die 64 "SDK must be appletvos or appletvsimulator: $sdk"
        ;;
esac
case "$EXPECTED_BUNDLE_ID" in
    ""|*[!A-Za-z0-9.-]*)
        die 64 "bundle ID contains unsupported characters: $EXPECTED_BUNDLE_ID"
        ;;
esac
[ -n "$EXPECTED_PRODUCT_NAME" ] ||
    die 64 "product name must not be empty"
case "$EXPECTED_CORE_SYMBOL" in
    ""|[!A-Za-z_]*|*[!A-Za-z0-9_]*)
        die 64 "audit symbol must be a C identifier: $EXPECTED_CORE_SYMBOL"
        ;;
esac
[ -d "$app_path" ] || die 3 "app bundle not found: $app_path"
case "$app_path" in
    *.app)
        ;;
    *)
        die 3 "expected a .app bundle: $app_path"
        ;;
esac
app_path=$(realpath "$app_path") ||
    die 3 "could not resolve app path"

plist="$app_path/Info.plist"
privacy="$app_path/PrivacyInfo.xcprivacy"
metallib="$app_path/default.metallib"
[ -f "$plist" ] || die 4 "Info.plist is missing"
[ -f "$privacy" ] || die 4 "PrivacyInfo.xcprivacy is missing"
[ -s "$metallib" ] || die 4 "default.metallib is missing or empty"

plist_value() {
    plutil -extract "$1" raw -o - -- "$plist" 2>/dev/null || true
}

bundle_id=$(plist_value CFBundleIdentifier)
executable_name=$(plist_value CFBundleExecutable)
bundle_name=$(plist_value CFBundleName)
display_name=$(plist_value CFBundleDisplayName)
short_version=$(plist_value CFBundleShortVersionString)
build_version=$(plist_value CFBundleVersion)
package_type=$(plist_value CFBundlePackageType)
requires_ios=$(plist_value LSRequiresIPhoneOS)
device_family=$(plist_value UIDeviceFamily.0)
[ "$bundle_id" = "$EXPECTED_BUNDLE_ID" ] ||
    die 4 "unexpected bundle identifier: $bundle_id"
[ -n "$executable_name" ] || die 4 "CFBundleExecutable is missing"
[ "$bundle_name" = "$EXPECTED_PRODUCT_NAME" ] ||
    die 4 "unexpected CFBundleName: $bundle_name"
[ "$display_name" = "$EXPECTED_PRODUCT_NAME" ] ||
    die 4 "unexpected CFBundleDisplayName: $display_name"
[ "$short_version" = "$EXPECTED_VERSION" ] ||
    die 4 "unexpected marketing version: $short_version"
[ "$build_version" = "$EXPECTED_BUILD" ] ||
    die 4 "unexpected bundle version: $build_version"
[ "$package_type" = "APPL" ] ||
    die 4 "unexpected bundle package type: $package_type"
[ "$requires_ios" = "true" ] ||
    die 4 "LSRequiresIPhoneOS is not true"
[ "$device_family" = "3" ] ||
    die 4 "tvOS UIDeviceFamily 3 is missing"

executable="$app_path/$executable_name"
[ -f "$executable" ] || die 4 "bundle executable is missing: $executable_name"

plist_dump=$(plutil -p "$plist")

build_info=$(vtool -show-build "$executable" 2>&1) ||
    die 4 "vtool could not inspect the app executable"
if [ -z "$sdk" ]; then
    if printf '%s\n' "$build_info" |
        grep -Eq '(^|[[:space:]])platform[[:space:]]+TVOS([[:space:]]|$)'; then
        sdk=appletvos
    elif printf '%s\n' "$build_info" |
        grep -Eq '(^|[[:space:]])platform[[:space:]]+TVOSSIMULATOR([[:space:]]|$)'; then
        sdk=appletvsimulator
    else
        die 4 "vtool did not report a tvOS platform"
    fi
fi
case "$sdk" in
    appletvos)
        expected_platform=TVOS
        expected_plist_platform=AppleTVOS
        ;;
    appletvsimulator)
        expected_platform=TVOSSIMULATOR
        expected_plist_platform=AppleTVSimulator
        ;;
esac
printf '%s\n' "$build_info" |
    grep -Eq "(^|[[:space:]])platform[[:space:]]+$expected_platform([[:space:]]|$)" ||
    die 4 "unexpected Mach-O platform; expected $expected_platform"
printf '%s\n' "$build_info" |
    grep -Eq '(^|[[:space:]])minos[[:space:]]+17\.0([[:space:]]|$)' ||
    die 4 "Mach-O minimum OS is not tvOS 17.0"
plist_platform=$(plist_value CFBundleSupportedPlatforms.0)
[ "$plist_platform" = "$expected_plist_platform" ] ||
    die 4 "Info.plist does not identify $expected_plist_platform"

arch_info=$(lipo -info "$executable" 2>&1) ||
    die 4 "lipo could not inspect the app executable"
printf '%s\n' "$arch_info" |
    grep -Eq '(^|[[:space:]])arm64([[:space:]]|$)' ||
    die 4 "app executable is not arm64: $arch_info"

symbols=$(nm "$executable" 2>/dev/null) ||
    die 4 "nm could not inspect the app executable"
printf '%s\n' "$symbols" |
    grep -Eq "(^|[[:space:]])_?${EXPECTED_CORE_SYMBOL}([[:space:]]|$)" ||
    die 4 "$EXPECTED_CORE_SYMBOL symbol is missing"
printf '%s\n' "$symbols" |
    grep -Eq '(^|[[:space:]])_?main([[:space:]]|$)' ||
    die 4 "host main symbol is missing"
for host_symbol in DKCGameViewController DKCSceneDelegate DKCAppDelegate; do
    printf '%s\n' "$symbols" |
        grep -Fq "OBJC_CLASS_\$_${host_symbol}" ||
        die 4 "host Objective-C class symbol is missing: $host_symbol"
done

linked_libraries=$(otool -L "$executable" 2>&1) ||
    die 4 "otool could not inspect the app executable"
for framework in UIKit Metal MetalKit QuartzCore AVFAudio GameController Foundation; do
    printf '%s\n' "$linked_libraries" |
        grep -Eq "/${framework}\\.framework/${framework}([[:space:]]|$)" ||
        die 4 "required framework is not linked: $framework"
done

artifact_paths=$(find "$app_path" -type f \( \
    -iname '*.sfc' -o \
    -iname '*.smc' -o \
    -iname '*.rom' -o \
    -iname '*.c' -o \
    -iname '*.cc' -o \
    -iname '*.cpp' -o \
    -iname '*.mm' -o \
    -iname '*.metal' -o \
    -iname '*.h' -o \
    -iname '*.hpp' -o \
    -path "$app_path/generated/*" -o \
    -path "$app_path/*/generated/*" -o \
    -path "$app_path/private/*" -o \
    -path "$app_path/*/private/*" \
    \) -print)
[ -z "$artifact_paths" ] ||
    die 4 "source or private ROM artifact is inside the app bundle"

repo_root=$(CDPATH= cd -P -- "$(dirname "$0")/../.." && pwd -P)
for personal_path in "$repo_root" "${HOME-}"; do
    [ -n "$personal_path" ] || continue
    if grep -R -aFq -- "$personal_path" "$app_path"; then
        die 4 "personal absolute source path is embedded in the app bundle"
    fi
done

printf 'PASS: tvOS app audit\n'
printf 'PLATFORM: %s, minimum OS 17.0\n' "$expected_platform"
printf 'ARCHITECTURE: arm64\n'
printf 'BUNDLE: %s (%s %s)\n' "$bundle_id" "$short_version" "$build_version"
printf 'CORE_SYMBOL: %s\n' "$EXPECTED_CORE_SYMBOL"
printf 'RESOURCES: PrivacyInfo.xcprivacy default.metallib\n'
printf 'SIGNATURE: not required\n'
