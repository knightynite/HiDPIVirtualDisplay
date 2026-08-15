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

### Homebrew

```bash
brew install knightynite/g9-helper/g9-helper
```

### Manual

Grab [`G9.Helper-v1.2.6.dmg`](https://github.com/knightynite/HiDPIVirtualDisplay/releases/download/v1.2.6/G9.Helper-v1.2.6.dmg) from [Releases](https://github.com/knightynite/HiDPIVirtualDisplay/releases), open it, drag to Applications.

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

### HDR (beta)

If your monitor supports HDR, G9 Helper can keep it enabled across logins and reconnects, which macOS otherwise resets on every login. Hold Option, open the menu, go to **Settings**, and turn on **Keep HDR On (Beta)**. It is off by default and stays hidden unless you hold Option. Note that HDR makes the SDR desktop look dimmer and warmer, so it suits HDR video and games more than plain desktop and text work.

## Keep external as main display

If you make your external monitor the primary display (the one with the menu bar), macOS moves it back to the built-in screen after every sleep/wake. Open the menu, go to **Settings**, and turn on **Keep External as Main Display**. G9 Helper then re-asserts your external monitor as the main display whenever it sets up the mirror, including after waking from sleep. It is off by default.

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

## Monitor-aware auto-apply

When you apply a preset, G9 Helper remembers which monitor was connected (by vendor and model ID). Auto-apply on reconnect, crash recovery, and wake-from-sleep will only activate if the same monitor is plugged in. If you switch locations and plug into a different display, the app stays idle instead of trying to apply the wrong configuration. Manually applying a preset on a new monitor updates the binding.

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
- Universal binary, runs on both Apple Silicon and Intel Macs
- Apple Silicon horizontal limits:
  - Base chips (M1/M2/M3/M4): up to 6144px horizontal
  - Pro/Max/Ultra: 7680px+ horizontal
- Intel support is new in 1.2.1; if you hit a problem, please open an issue

## Known issues & limitations

- Uses private macOS APIs — could break with future macOS updates
- HDR is beta. It can be kept on across logins from Settings (hold Option), but it dims and warms the SDR desktop, which is normal HDR behavior on this panel
- Since 1.2.3, sleep/wake and brief monitor dropouts keep the existing setup (and your window layout) instead of rebuilding it; if HiDPI ever fails to come back, re-apply the preset from the menu
- Switching presets or disabling HiDPI briefly restarts the app (virtual displays can only be fully torn down when the process exits)
- Refresh rate is auto-detected; if your monitor flickers, set it manually under Settings > Refresh Rate
- Since 1.2.6, resolution wins over refresh rate. If your cable or port can't carry the panel's native resolution at the rate you picked, the app uses the fastest rate that *does* run at native instead of shrinking the desktop. Bandwidth-limited HDMI links hit this most often
- Mirroring resamples unless the preset's framebuffer matches the panel exactly. On a 7680x2160 panel only the 3840x1080 (2.0x) preset is a 1:1 mirror; every other preset trades a little sharpness for smaller text

## Troubleshooting

**App won't open** — right-click, select "Open", confirm in the security dialog.

**Resolution doesn't apply** — disable HiDPI first, wait a few seconds, try again.

**Phantom displays showing up in System Settings** — the app auto-cleans these on launch, but if you see extras, use **Clean Up Phantom Displays** from the menu bar.

**Flickering** — go to Settings > Refresh Rate and manually match your monitor (common with 165Hz/240Hz displays).

**Picture looks soft, or lower resolution than it should** — check `/tmp/g9helper.log` for the `Panel N: native ...` line. It prints the panel's native size and which refresh rates that panel actually offers at that size. If the rate you want isn't listed there, the link can't carry it at full resolution: try a different port or cable, or drop the rate. To rule out the mirror resample entirely, switch to the 3840x1080 (2.0x) preset, which mirrors 1:1 on a 7680x2160 panel.

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
