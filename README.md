# G9 Helper

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform: macOS](https://img.shields.io/badge/Platform-macOS%2012%2B-lightgrey.svg)](https://www.apple.com/macos/)

Menu bar app that gets you HiDPI (Retina) rendering on the Samsung Odyssey G9 and other monitors that macOS won't give it to natively.

macOS gates HiDPI on pixel density, so big monitors like the G9 don't qualify — you're stuck with either tiny native-res text or blurry scaled rendering. G9 Helper works around this by creating a virtual display with the HiDPI flag set, then mirroring it to your physical monitor. macOS renders at 2x into the virtual framebuffer, and you get sharp text at whatever effective resolution you pick.

## Supported Monitors

| Monitor | Native Resolution | Recommended Setting |
|---------|------------------|---------------------|
| Samsung Odyssey G9 57" | 7680x2160 | 5120x1440 HiDPI |
| Samsung Odyssey G9 49" | 5120x1440 | 3840x1080 HiDPI |
| 34" Ultrawide | 3440x1440 | 2560x1080 HiDPI |
| 4K Displays | 3840x2160 | 2560x1440 HiDPI |

Should work with any external display, though it was built for the G9.

## Install

Grab [`G9.Helper-v1.1.0.dmg`](https://github.com/knightynite/HiDPIVirtualDisplay/releases/download/v1.1.0/G9.Helper-v1.1.0.dmg) from [Releases](https://github.com/knightynite/HiDPIVirtualDisplay/releases), open it, drag to Applications.

macOS will probably block it on first launch — right-click the app, hit "Open", confirm in the dialog.

### Build from source

```bash
git clone https://github.com/knightynite/HiDPIVirtualDisplay.git
cd HiDPIVirtualDisplay/App
./build.sh
cp -r "build/G9 Helper.app" /Applications/
```

## Usage

Click the display icon in your menu bar, pick your monitor, pick a resolution preset. Takes a few seconds to apply. To turn it off, select **Disable HiDPI** from the same menu.

### Custom scale

Every monitor submenu has a **Custom Scale...** option — it opens a slider for any factor between 1.1x and 2.0x. The resolution preview updates as you drag.

## Resolution Presets

### Samsung G9 57" (7680x2160)

| Preset | Scale | Notes |
|--------|-------|-------|
| 6144x1728 | 1.25x | More space |
| 5908x1662 | 1.3x | |
| 5632x1584 | 1.36x | |
| 5486x1543 | 1.4x | |
| 5297x1490 | 1.45x | |
| 5120x1440 | 1.5x | Recommended — best balance |
| 4800x1350 | 1.6x | Slightly larger UI |
| 4389x1234 | 1.75x | |
| 3840x1080 | 2.0x | Larger text |

### Samsung G9 49" (5120x1440)

| Preset | Notes |
|--------|-------|
| 3840x1080 | Recommended |
| 2560x720 | Native 2x |

## Auto-start & crash recovery

The app uses private macOS APIs for the virtual display stuff, and those APIs can occasionally crash. So there's a built-in restart mechanism:

**Settings > Start at Login** — this installs a launchd agent that auto-restarts the app after a crash, restores your last preset, and cleans up any orphaned virtual displays.

If you built from source, you can also do it from the command line:

```bash
cd /path/to/HiDPIVirtualDisplay/App
./install-launchd.sh install    # enable
./install-launchd.sh uninstall  # disable
```

## Requirements

- macOS 12+ (Monterey or later)
- Apple Silicon recommended
  - Base chips (M1/M2/M3/M4): up to 6144px horizontal
  - Pro/Max/Ultra: 7680px+ horizontal
- Intel Macs may work but not well tested

## Known issues & limitations

- Uses private macOS APIs — could break with future macOS updates
- HDR doesn't work in mirrored mode
- Sometimes needs re-enabling after sleep/wake
- Switching presets or disabling HiDPI briefly restarts the app (virtual displays can only be fully torn down when the process exits)
- Refresh rate is auto-detected; if your monitor flickers, set it manually under Settings > Refresh Rate

## Troubleshooting

**App won't open** — right-click, select "Open", confirm in the security dialog.

**Resolution doesn't apply** — disable HiDPI first, wait a few seconds, try again.

**Phantom displays showing up in System Settings** — the app auto-cleans these on launch, but if you see extras, use **Clean Up Phantom Displays** from the menu bar.

**Flickering** — go to Settings > Refresh Rate and manually match your monitor (common with 165Hz/240Hz displays).

## How it works

1. Creates a virtual display with the HiDPI flag and a 2x framebuffer
2. Mirrors the virtual display to your physical monitor
3. macOS renders at 2x into the virtual framebuffer
4. The framebuffer gets scaled to your monitor's native resolution

Built with Swift (UI) and Objective-C (display management). The VirtualDisplayManager is compiled without ARC (`-fno-objc-arc`) because the private CGVirtualDisplay APIs need manual memory control.

## Uninstall

1. Menu bar icon > Settings > toggle off **Start at Login**
2. Menu bar icon > **Quit**
3. Trash the app from /Applications

## License

MIT — free software, use at your own risk. This relies on undocumented macOS APIs that Apple could change at any time.

---

Made by AL in Dallas
