# Repository working agreement

## Purpose

Build a source-only native port foundation for the Donkey Kong Country SNES
trilogy, with DKC2 first, DKC3 second, and DKC1 third. Preserve correctness
evidence and make every desktop and tvOS milestone reproducible.

## Content boundary

- Never add ROMs, save files, extracted graphics, music, BRR samples, level
  data, screenshots, or generated game binaries to the repository.
- Every private ROM and its generated recompilation output must remain outside
  Git. Do not turn a ROM revision into a repository-wide compatibility policy.
- Treat research projects without an explicit compatible license as
  references only. Do not copy their code, comments, or bundled assets.
- Record third-party source provenance, exact revision, local adaptations,
  and license text under `third_party/`.

## Required workflow

1. Read `docs/IMPLEMENTATION_JOURNAL.md`, `docs/ARCHITECTURE.md`, and
   `docs/ROADMAP.md` before changing architecture.
2. Add synthetic unit tests for public behavior. Use hashes and external ROM
   paths for private integration checks.
3. Run the complete available test suite before and after a milestone.
4. Update the implementation journal, architecture, hardware notes, roadmap,
   changelog, and README when behavior or limitations change.
5. Report unverified work explicitly. Never replace missing hardware with a
   guessed success response merely to advance the boot probe.

## Builds

With CMake:

```powershell
cmake -S . -B build
cmake --build build --config Release
ctest --test-dir build -C Release --output-on-failure
```

Private ROM integration:

```powershell
cmake -S . -B build -DDKC2_ROM="C:\private\dkc2.smc"
cmake --build build --config Release
ctest --test-dir build -C Release --output-on-failure
```

With Make:

```sh
make test
make verify-rom ROM="/private/path/dkc2.smc"
make boot-rom ROM="/private/path/dkc2.smc"
```

Use strict warnings for project code. Third-party warnings may be isolated,
but never silence errors globally.
