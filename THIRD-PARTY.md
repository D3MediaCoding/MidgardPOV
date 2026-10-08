# UE4SS dependency provenance

The Nexus 0.8-beta package contains **unmodified upstream binaries**. They are not built by Midgard POV and are not committed to this source repository. UE4SS is MIT-licensed; its license is retained in [installer/LICENSE-UE4SS.txt](installer/LICENSE-UE4SS.txt).

| Component | Upstream release | SHA256 of binary in Nexus ZIP |
| --- | --- | --- |
| `dwmapi.dll` | `UE4SS_v3.0.1.zip`, tag `v3.0.1` | `ce596412befa68c30b7f88f65beb77d9bdad55e9b96a276a5a9cf690c63f24bb` |
| `UE4SS.dll` | `UE4SS_v3.0.1-1161-g6eb3d9bc.zip`, tag `experimental` | `f176dc36fd2bc7b8211dde6ba54ade6f66da5c8f3a79e3017a85b45c215e8242` |

Downloads:

- https://github.com/UE4SS-RE/RE-UE4SS/releases/download/v3.0.1/UE4SS_v3.0.1.zip
- https://github.com/UE4SS-RE/RE-UE4SS/releases/download/experimental/UE4SS_v3.0.1-1161-g6eb3d9bc.zip

Sources and build documentation:

- Proxy release source: https://github.com/UE4SS-RE/RE-UE4SS/tree/v3.0.1
- Core source commit: https://github.com/UE4SS-RE/RE-UE4SS/tree/6eb3d9bc3346ba01f7191612b5812e0e47a3bbe1
- Core build instructions: https://github.com/UE4SS-RE/RE-UE4SS/blob/6eb3d9bc3346ba01f7191612b5812e0e47a3bbe1/README.md
- Proxy build instructions: https://github.com/UE4SS-RE/RE-UE4SS/blob/v3.0.1/README.md

For a source build, clone the upstream repository, check out the appropriate tag/commit and initialize its recursive submodules. Follow the prerequisites and build instructions in that revision's README; the two revisions may use different build systems. The pinned core README documents Visual Studio 2022 CMake generation and `Game__Shipping__Win64` builds. We have not independently rebuilt these binaries or established reproducible binary output.

The older core failed its FText constructor scan on the tested game build. The release therefore pairs the v3.0.1 proxy with the above experimental core in the legacy directory layout and sets Unreal's major/minor version explicitly to 4/27. Do not substitute a current experimental build without compatibility testing.

## Nexus package evidence

- Archive: `MidgardPOV-0.8.zip`
- Bytes: `8881464`
- SHA256: `14ec6599555f5fd9ff8e37152278ceb4e7728afb849131bf1620c69e201d031c`
- Public scan: https://www.virustotal.com/gui/file/14ec6599555f5fd9ff8e37152278ceb4e7728afb849131bf1620c69e201d031c

At inspection on 8 October 2026, the archive report showed 0/67 detections and its Relations tab showed 0/71 for both DLLs. These results do not guarantee safety or explain Nexus's quarantine. The file remains subject to Nexus moderation review. All 18 non-empty ZIP entries were read and matched against the packaged originals by SHA256; no nested archive was present.
