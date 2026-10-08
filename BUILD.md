# Packaging and review instructions

Midgard POV's Lua mod and CMD/PowerShell installer do not require compilation. The release includes precompiled upstream UE4SS DLLs, whose sources and build instructions are linked in [THIRD-PARTY.md](THIRD-PARTY.md).

## Assemble the installer ZIP

Use a fresh clone of this repository on Windows with PowerShell 5.1. Download and extract the exact two official upstream archives listed in THIRD-PARTY.md into these ignored directories:

```text
vendor/
  UE4SS_v3.0.1/
    dwmapi.dll
  UE4SS_v3.0.1-1161-g6eb3d9bc/
    ue4ss/
      UE4SS.dll
```

Check each DLL with `Get-FileHash -Algorithm SHA256` against THIRD-PARTY.md before packaging. The packaging script does not download or run the binaries.

From the repository root:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File build-package.ps1
```

Output: `dist/MidgardPOV-0.8.zip`. The script includes nine Lua modules, the installer sources, user instructions, MIT license and the explicitly configured UE4.27 payload. It enables only `MidgardFirstPerson` in `Mods/mods.txt`.

Use a fresh output directory when packaging; the script updates its staging directory rather than removing unexpected old files. Inspect the archive before uploading. A rebuild's ZIP hash can differ because archive timestamps/metadata differ; the Lua and installer source content should match the 0.8-beta release. No bit-for-bit reproducible archive claim is made.

## Build upstream UE4SS for inspection

Install the prerequisites specified by each pinned upstream README. Clone the upstream source in a separate directory:

```powershell
git clone https://github.com/UE4SS-RE/RE-UE4SS.git UE4SS-review
cd UE4SS-review
git checkout 6eb3d9bc3346ba01f7191612b5812e0e47a3bbe1
git submodule update --init --recursive
```

For this core revision, its README documents a Visual Studio 2022 CMake build:

```powershell
cmake -B build_cmake_Game__Shipping__Win64 -G "Visual Studio 17 2022"
cmake --build build_cmake_Game__Shipping__Win64 --config Game__Shipping__Win64
```

For the v3.0.1 proxy, use a separate checkout at `v3.0.1`, initialize its recursive submodules, and follow that revision's build instructions. We distribute the official upstream release binaries, not independently compiled substitutes; these source-build instructions are for inspection and are not a claim of reproduced release hashes.
