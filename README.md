# Midgard POV

An unofficial beta camera, aiming and color-grading mod for the **Windows Steam edition of Tribes of Midgard**, developed against Steam build **19737805 / Unreal Engine 4.27**.

This repository contains **0.9.0-beta** source, including the save-and-quit cleanup fix and camera-relative minimap, scrolling compass and native map-pin icons. The original **0.8-beta** Nexus package source is preserved at [commit 5e3e670](https://github.com/D3MediaCoding/MidgardPOV/tree/5e3e670f4af83a000807cc6c43dcf279ed5e67e0). Compiled UE4SS loader binaries are upstream dependencies and are not committed here.

**Nexus page:** https://www.nexusmods.com/tribesofmidgard/mods/4

The Nexus page is currently unpublished and the installer ZIP is quarantined pending moderation review. This source repository does not establish that the package has passed Nexus review.

## Features

### Camera-relative minimap and compass

While first- or third-person mode is active, the HUD minimap rotates with camera yaw so forward travel points toward the top of the map. A horizontal compass at the top center scrolls cardinal labels and intermediate bearings beneath a fixed center indicator. The heading includes the 180-degree correction identified during in-game testing. Original view restores the previous map angle and pivot and removes the compass; world-exit cleanup restores these before travel. The full-screen map is unchanged.

Place a pin using the game's own map controls. Its selected star, sword, shield, chest or skull artwork also appears on the compass and follows the bearing to the pin. Persistent pins use their canvas position and the game's native MapToWorldPosition conversion; their default Info coordinates do not provide their actual position. The compass copies the pin's native image brush, including changes to the selected icon, and uses a gold diamond if artwork is unavailable. Pins behind you or outside the compass strip are hidden. There are no separate waypoint controls.

Widget discovery runs once per camera activation/attachment. Native pin data is sampled every 15 frames, with up to 32 symbols. Updates use cached widgets, copy positions, and change image brushes only when the source icon changes. Regression checks cover both camera modes, native coordinate conversion, existing pins, pin removal, icon changes, destroyed widgets, unrelated HUD isolation and travel cleanup. The user confirmed that map-pin tracking and matching artwork worked in-game.

### Native movement and rudder controls

When the character uses disabled/custom native movement, is attached to a boat, or the game switches to a vessel view target, the mod yields character movement and weapon aiming to the game. It keeps the mod camera available and does not consume WASD, force walking or remove the game's own movement lock. Leaving native control resumes camera-relative walking. These paths have stand-in regression coverage; actual workbench crashes and rudder transitions still require gameplay verification on the current build.

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
- Saved render-distance slider from 1x to 3x the existing draw-distance setting.
- Camera-relative minimap rotation, a scrolling compass and matching native map-pin icons in first/third person.
- Experimental vertical launch steering for locally owned projectiles using Unreal's standard ProjectileMovementComponent.

The mod adjusts existing rendering. It does not replace textures, models or lighting assets. Custom weapons, multiplayer behavior and damage across elevations need more testing. The original game assets can clip or look incomplete from these camera positions. No FPS improvement is guaranteed.

## Installation and controls

Download the installer ZIP from [GitHub Releases](https://github.com/D3MediaCoding/MidgardPOV/releases/tag/v0.9.0-beta). This first release is a beta. Close the game, extract the whole ZIP, and run `Install.cmd`. Select the game folder and click **Install / Update**. A clean install uses the loader bundled in the release; unrelated loader installations are rejected for manual merging.

When setup opens, it checks the public GitHub main branch and downloads the current Lua mod modules from a single pinned commit. Files are verified against GitHub's Git blob hashes before use. Existing installations update automatically when the game is closed; a running game or edited file stops the update. Your preferences and saves remain. Open the same Install.cmd again to check future source pushes. If GitHub is unavailable, existing installs are kept; new installs can use the bundled files offline. Changes to loader binaries or the installer require a new release download.

In a world, click **Mod settings** near the upper-right corner when the cursor is visible, or press **Insert**. Choose first person or third person. Adjust FOV, sensitivity, crosshair, graphics and inverted look. Press the middle mouse button to reveal the cursor or return to mouse look while the mod camera is active. F8 remains an alternative. The toggle leaves the settings panel usable while it is open. Rapid presses are coalesced and debounced. Native game input-mode changes take priority, so the mod does not recapture focus while a workbench or other game UI owns input. Camera and weapon input pause during native UI control. Preferences save automatically. **Save & return to game** or Escape closes the panel.

| Key | Action |
| --- | --- |
| Insert | Open/close settings |
| F6 | Toggle mod camera |
| F7 | Write cached diagnostics |
| Middle mouse button | Release/resume mouse cursor |
| F8 | Release/resume mouse cursor (alternative) |
| F9 | Switch first/third person |
| F10 | Toggle crosshair |
| F11 | Cycle graphics presets |
| Page Up / Down | Increase/decrease FOV |
| Home / End | Increase/decrease sensitivity |

To uninstall, close the game and use **Uninstall** in the setup window. The installer checks hashes and removes only recorded mod files; preferences, backups, logs and saves remain. This release does not edit `Engine.ini`. The render-distance slider temporarily multiplies `r.ViewDistanceScale` by 1–3 while the mod camera is active, independently of the color preset. Original view and normal world exit restore the previous console value. This extends distance-culling thresholds; it does not increase game-specific world streaming, and higher values can reduce performance.

## Source layout

- `Mods/MidgardFirstPerson/Scripts/`: ten active Lua modules.
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

The installer copies an offline payload into the selected game's `TOM/Binaries/Win64` directory. It checks for a running game and unrelated existing loaders, records relative owned paths and hashes, and supports backup/update/uninstall. The loader is bundled offline. Setup downloads only the public repository Lua modules over HTTPS, pinned to one commit and checked against its Git blob hashes; it does not fetch or execute replacement setup scripts. The CMD launcher starts the PowerShell UI with process-scoped `-ExecutionPolicy Bypass`; it does not change the machine's policy. Normal installation does not request administrator privileges.

Concept, direction and gameplay testing: **botDanka**. Lua implementation, packaging, tests and documentation were generated with AI assistance through **OpenAI Codex**. UE4SS is developed by its upstream contributors and is distributed under its included MIT license. See [LICENSE.md](LICENSE.md) for the distinction between this mod's permissions and third-party permissions.

Tribes of Midgard belongs to its respective rights holders. This project is not affiliated with or endorsed by Norsfell or Nexus Mods.

For issues, include mod/game version, solo/co-op status, camera mode, weapon if relevant and reproduction steps. Share only relevant log excerpts with personal information removed.
