# Midgard POV

An unofficial beta camera, aiming and color-grading mod for the **Windows Steam edition of Tribes of Midgard**, developed against Steam build **19737805 / Unreal Engine 4.27**.

This repository contains **0.8.1-beta** source, including the save-and-quit cleanup fix and camera-relative minimap update. The original **0.8-beta** Nexus package source is preserved at [commit 5e3e670](https://github.com/D3MediaCoding/MidgardPOV/tree/5e3e670f4af83a000807cc6c43dcf279ed5e67e0). Compiled UE4SS loader binaries are upstream dependencies and are not committed here.

**Nexus page:** https://www.nexusmods.com/tribesofmidgard/mods/4

The Nexus page is currently unpublished and the installer ZIP is quarantined pending moderation review. This source repository does not establish that the package has passed Nexus review.

## Features

### Camera-relative minimap and compass

While first- or third-person mode is active, the HUD minimap rotates with camera yaw so forward travel points toward the top of the map. An upright compass inside the minimap's bottom edge displays a cardinal direction and bearing. The heading includes the 180-degree correction identified during in-game testing. Original view restores the previous map angle and pivot and removes the compass; world-exit cleanup restores these before travel. The full-screen map is unchanged.

Widget discovery runs once per camera activation/attachment. Updates use cached widgets and write only changed headings. Regression checks cover both camera modes, compass placement and removal, idle update counts, unrelated map isolation and travel cleanup. The user confirmed the corrected local update worked in-game.

### 0.8.1: save-and-quit cleanup

The mod now restores the camera and detaches its HUD before map travel or QuitGame, then pauses camera, aiming, menu polling and queued controls during teardown. An EndPlay fallback drops references without invoking methods on dying actors. Engine input mappings are restored after travel, and the next world can enable the mod normally.

Regression tests cover an open settings panel during travel, input/camera restoration, remote actor isolation, blocked outgoing-controller access and reactivation after loading. The user confirmed that save-and-quit from first person no longer crashed in their in-game test. This is not a guarantee for every world transition or multiplayer configuration.

- First-person and over-the-shoulder third-person cameras, with a return to the original view.
- Mouse look, including pitch, and camera-relative WASD movement.
- Center crosshair and camera-based targeting.
- Adjustable FOV (60–130), sensitivity and inverted vertical look.
- Original, Natural, Atmospheric and Vivid graphics presets.
- An in-game settings panel and automatically saved preferences.
- Optional F-key shortcuts.
- Camera-relative minimap rotation and an integrated compass in first/third person.
- Experimental vertical launch steering for locally owned projectiles using Unreal's standard ProjectileMovementComponent.

The mod adjusts existing rendering. It does not replace textures, models or lighting assets. Custom weapons, multiplayer behavior and damage across elevations need more testing. The original game assets can clip or look incomplete from these camera positions. No FPS improvement is guaranteed.

## Installation and controls

Use the complete installer package once its release is available. Close the game, extract the whole ZIP, and run `Install.cmd`. Select the game folder and click **Install / Update**. A clean install uses the loader bundled in the release; unrelated loader installations are rejected for manual merging.

In a world, click **Mod settings** near the upper-right corner when the cursor is visible, or press **Insert**. Choose first person or third person. Adjust FOV, sensitivity, crosshair, graphics and inverted look. Preferences save automatically. **Save & return to game** or Escape closes the panel.

| Key | Action |
| --- | --- |
| Insert | Open/close settings |
| F6 | Toggle mod camera |
| F7 | Write cached diagnostics |
| F8 | Release/resume mouse cursor |
| F9 | Switch first/third person |
| F10 | Toggle crosshair |
| F11 | Cycle graphics presets |
| Page Up / Down | Increase/decrease FOV |
| Home / End | Increase/decrease sensitivity |

To uninstall, close the game and use **Uninstall** in the setup window. The installer checks hashes and removes only recorded mod files; preferences, backups, logs and saves remain. This release does not edit `Engine.ini` or render distance.

## Source layout

- `Mods/MidgardFirstPerson/Scripts/`: nine active Lua modules.
- `installer/`: CMD launcher, PowerShell setup UI, install/update/uninstall implementation, user instructions and UE4SS license.
- `staging/UE4SS-settings.ini`: tested configuration with the explicit UE4.27 override.
- `build-package.ps1`: release packaging script; see [BUILD.md](BUILD.md).
- `tests/`: Unreal API stand-in tests and isolated installer tests.
- [THIRD-PARTY.md](THIRD-PARTY.md): exact UE4SS versions, sources and binary hashes.

The Lua, PowerShell and CMD sources require no compilation. No game files, logs, personal settings, save files or development install manifests are included in this repository.

## Validation

The source includes stand-in checks for camera/input restoration, local versus remote aiming/projectiles, graphics settings, crosshair/menu behavior, preferences and bounded streaming work. Installer checks use a fake executable that is never run and verify update/uninstall ownership, hashes, conflict handling and path containment.

These checks are not a substitute for testing actual weapons, world transitions, multiplayer or frame times inside the game.

With Python and `lupa` available:

```powershell
python -m pip install lupa==2.8
python tests/verify.py
```

With Windows PowerShell 5.1:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/verify-installer.ps1
```

The installer test preserves its isolated fixture and backups as test evidence. They are ignored by Git.

## Security review and credits

The installer copies an offline payload into the selected game's `TOM/Binaries/Win64` directory. It checks for a running game and unrelated existing loaders, records relative owned paths and hashes, and supports backup/update/uninstall. It does not download dependencies. The CMD launcher starts the PowerShell UI with process-scoped `-ExecutionPolicy Bypass`; it does not change the machine's policy. Normal installation does not request administrator privileges.

Concept, direction and gameplay testing: **botDanka**. Lua implementation, packaging, tests and documentation were generated with AI assistance through **OpenAI Codex**. UE4SS is developed by its upstream contributors and is distributed under its included MIT license. See [LICENSE.md](LICENSE.md) for the distinction between this mod's permissions and third-party permissions.

Tribes of Midgard belongs to its respective rights holders. This project is not affiliated with or endorsed by Norsfell or Nexus Mods.

For issues, include mod/game version, solo/co-op status, camera mode, weapon if relevant and reproduction steps. Share only relevant log excerpts with personal information removed.
