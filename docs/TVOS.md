# Native tvOS builds

The tvOS port uses one shared Apple-native host for all three Donkey Kong
Country games:

- UIKit owns the application lifecycle.
- Metal and MetalKit present the 342x224 BGRA framebuffer.
- AVAudioEngine and AVAudioSession play 32,040 Hz stereo audio.
- GameController provides two standard controller ports.
- A small C ABI (`DKCGameCoreV2`) keeps title code independent from the host.

DKC1 and DKC3 share the generic SNES runtime and differ only in their title
adapter, recompilation configuration, save prefix, and widescreen policy.
DKC2 uses the same Apple host through its existing game-specific adapter.

The 342-pixel framebuffer is presented with the SNES 7:6 pixel aspect ratio,
which yields native 16:9 at 224 lines. Gameplay can render the additional
tilemap columns; menus and transitions that do not expose safe world data stay
centered instead of being stretched.

## Private data boundary

Keep every ROM, generated recompilation unit, save, screenshot, signing
identity, provisioning profile, and signed application outside Git. The build
scripts read the selected ROM and write generated C under ignored `generated/`
directories. DKC1 and DKC3 accept a complete headerless ROM by size and
internal title; the generated module records the exact input digest without
using a revision allowlist.

## Toolchain

Initialize submodules and select the known Xcode installation:

```sh
git submodule update --init --recursive
export DEVELOPER_DIR=/Applications/Xcode-27-beta-5.app/Contents/Developer
./scripts/tvos/preflight.sh --toolchain-only
```

The scripts use `xcrun` with `appletvos` or `appletvsimulator` directly and do
not change the machine-wide `xcode-select` setting.

## Build

Build DKC2:

```sh
./scripts/tvos/build-app.sh "/absolute/path/to/private/DKC2.sfc" appletvos
```

Build DKC3 or DKC1:

```sh
./scripts/tvos/build-title-app.sh dkc3 "/absolute/path/to/private/DKC3.sfc" appletvos
./scripts/tvos/build-title-app.sh dkc1 "/absolute/path/to/private/DKC1.sfc" appletvos
```

Use `appletvsimulator` as the final argument for a simulator build. Every
command prints the resulting `.app` path, bundle identifier, core function,
and product name.

Audit an unsigned build before adding a provisioning profile. For example:

```sh
DKC2_BUNDLE_ID=tv.nijssen.DKC1RecompTV \
DKC2_PRODUCT_NAME="DKC1 Recomp TV" \
  ./scripts/tvos/audit-app.sh \
  tvos/build/app-xcode27-ninja-appletvos/DKC1RecompTV.app \
  appletvos dkc1_game_core
```

The audit checks the Apple platform, arm64 architecture, minimum tvOS version,
bundle metadata, selected core symbol, resources, and absence of private or
generated game data.

## Install and stage

Sign the audited app with the local Apple Development identity and a matching
provisioning profile, then install it with `xcrun devicectl device install
app`. Stage the private ROM into the installed app's data container:

```sh
./scripts/tvos/stage-game.sh \
  "/absolute/path/to/private/DKC1.sfc" DEVICE \
  tv.nijssen.DKC1RecompTV dkc1
```

Use `tv.nijssen.DKC2RecompTV dkc2` or
`tv.nijssen.DKC3RecompTV dkc3` for the other titles. The staging command copies
the ROM to `Library/Caches/DKCRecompTV/<title>/Game.sfc`, reads it back from
the device, and requires matching size, SHA-256, and bytes.

## Controls

Standard Apple-compatible game controllers map to both SNES controller ports.
The Siri Remote fallback maps arrows to the D-pad, a short click to B, a click
held for at least half a second to A, and Back/Menu or Play/Pause to Start.
The Start buttons are claimed with native tvOS press gesture recognition so
they do not depend on responder-chain timing.
