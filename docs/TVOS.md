# Native tvOS preparation

## Milestone 1 boundary

This checkout remains source-only. A private ROM must stay outside the
repository and is read only by the preflight. No ROM bytes, copier-header
stripping, ROM conversion, downloads, generated game C, private build output,
signing material, or team IDs belong in Git.

The accepted game-data profiles are complete, headerless North American DKC2
USA payloads with one of these exact size and SHA-256 identities:

| Field | Required value |
| --- | --- |
| Size | `4194304` bytes |
| USA v1.0 SHA-256 | `35421a9af9dd011b40b91f792192af9f99c93201d8d394026bdfb42cbf2d8633` |
| USA Rev 1/v1.1 SHA-256 | `b79c2bb86f6fc76e1fc61c62fc16d51c664c381e58bc2933be643bbc4d8b610c` |

Other sizes or digests are not accepted. The Rev 1/v1.1 profile is a valid
private input and remains outside the source tree.

## Reproducible preflight

The script requires the exact beta-5 developer directory and never calls
`xcode-select`:

```sh
export DEVELOPER_DIR=/Applications/Xcode-27-beta-5.app/Contents/Developer
./scripts/tvos/preflight.sh --toolchain-only
./scripts/tvos/preflight.sh "/absolute/path/to/private/DKC2-USA-v1.0.sfc"
DKC2_ROM="/absolute/path/to/private/DKC2-USA-Rev1.sfc" \
  ./scripts/tvos/preflight.sh
```

The current installation reports `Xcode 27.0`, build `27A5237l`, with tvOS
and tvOS Simulator SDK `27.0`. `--toolchain-only` is the explicit successful
path when no ROM is available. The normal path requires one external ROM
argument or the `DKC2_ROM` environment variable. Either exact SHA-256 profile
passes.

The ROM path is rejected when it resolves inside this checkout. The read-only
size and SHA-256 checks run on the original file; nothing is copied or
rewritten.

## Boundary check

Run the single focused test with the standard library:

```sh
python3 tests/test_tvos_preflight.py
```

It covers the toolchain-only success, missing-ROM error, in-checkout path
rejection, both known SHA-256 profiles, and the tracked-source/private-output
scan without private ROM data.
No tvOS target, signing setup, device install, or private build is part of
this milestone.
