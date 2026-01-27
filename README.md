# G9 Helper

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform: macOS](https://img.shields.io/badge/Platform-macOS%2012%2B-lightgrey.svg)](https://www.apple.com/macos/)
[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-☕-orange.svg)](https://buymeacoffee.com/alcybr)

A lightweight macOS menu bar utility that unlocks crisp HiDPI (Retina) scaling on Samsung Odyssey G9 and other large monitors.

**Free and open source** - if you find it useful, consider [buying me a coffee](https://buymeacoffee.com/alcybr)!

## The Problem

macOS only enables HiDPI rendering on displays meeting certain pixel density thresholds. Large monitors like the Samsung Odyssey G9 (57" or 49") don't qualify, forcing you to choose between:

- **Native resolution** with text too small to read comfortably
- **Scaled resolution** with blurry, non-Retina rendering

## The Solution

G9 Helper creates a virtual display with HiDPI enabled at your preferred resolution, then mirrors it to your monitor. macOS renders everything at 2x into the virtual framebuffer, giving you sharp, Retina-quality text on any display.

## Supported Monitors

| Monitor | Native Resolution | Recommended Setting |
|---------|------------------|---------------------|
| Samsung Odyssey G9 57" | 7680x2160 | 5120x1440 HiDPI |
| Samsung Odyssey G9 49" | 5120x1440 | 3840x1080 HiDPI |
| 34" Ultrawide | 3440x1440 | 2560x1080 HiDPI |
| 4K Displays | 3840x2160 | 2560x1440 HiDPI |

## Installation

### Download

1. Download [`G9.Helper-v1.0.0.dmg`](https://github.com/knightynite/HiDPIVirtualDisplay/releases/download/v1.0.0/G9.Helper-v1.0.0.dmg) from [Releases](https://github.com/knightynite/HiDPIVirtualDisplay/releases)
2. Open the DMG and drag **G9 Helper** to **Applications**
3. Launch from Applications or Spotlight
4. Look for the display icon in your menu bar

### Build from Source

```bash
git clone https://github.com/knightynite/HiDPIVirtualDisplay.git
cd HiDPIVirtualDisplay/App
./build.sh
cp -r "build/G9 Helper.app" /Applications/
```

### First Launch

macOS may block the app on first run. Right-click the app, select "Open", then click "Open" in the dialog.

## Usage

1. Click the display icon in your menu bar
2. Select your monitor type from the submenu
3. Choose a resolution preset
4. Wait a few seconds for the configuration to apply

To disable, click the menu bar icon and select **Disable HiDPI**.

## Resolution Presets

### Samsung G9 57" (7680x2160)

| Preset | Effective Resolution | Notes |
|--------|---------------------|-------|
| Native 2x | 3840x1080 | Largest UI, sharpest text |
| 5120x1440 | 5120x1440 | Best balance (recommended) |
| 4800x1350 | 4800x1350 | Slightly larger UI |
| 4480x1260 | 4480x1260 | Larger UI elements |

### Samsung G9 49" (5120x1440)

| Preset | Effective Resolution |
|--------|---------------------|
| 3840x1080 | 3840x1080 (recommended) |
| Native 2x | 2560x720 |

## Auto-Start & Crash Recovery

The app includes built-in crash recovery. If enabled, your HiDPI settings will automatically restore after a crash or system restart.

### Enable Auto-Start (Recommended)

```bash
cd /path/to/HiDPIVirtualDisplay/App
./install-launchd.sh install
```

This will:
- Start G9 Helper automatically at login
- Auto-restart if the app crashes
- Automatically restore your last HiDPI preset

### Disable Auto-Start

```bash
./install-launchd.sh uninstall
```

### Check Status

```bash
./install-launchd.sh status
```

## Requirements

- macOS 12.0 Monterey or later
- Apple Silicon recommended (M1/M2/M3/M4)
  - Base chips support up to 6144px horizontal
  - Pro/Max/Ultra support 7680px+ horizontal
- Intel Macs may work with limitations

## Known Issues

### Periodic Crashes

The app uses private macOS APIs for virtual display creation. These APIs have internal memory management that can occasionally cause crashes. The app is designed to handle this gracefully:

1. **Auto-restart**: With the launch agent installed, crashes restart automatically within seconds
2. **State preservation**: Your preset is saved and restored on restart
3. **Transparent recovery**: Most users won't notice the brief restart

This is a known limitation of using private APIs. The display configuration persists through crashes.

## Limitations

- Refresh rate depends on resolution and hardware configuration
- HDR may not function in mirrored mode
- May require re-enabling after sleep/wake cycles
- Uses private macOS APIs (may break with future updates)

## Uninstall

1. Remove auto-start (if enabled):
   ```bash
   ./install-launchd.sh uninstall
   ```
2. Click the G9 Helper menu bar icon and select **Quit**
3. Drag **G9 Helper.app** from Applications to Trash
4. Empty Trash

## Project Structure

```
HiDPIVirtualDisplay/
├── App/                          # Menu bar GUI application
│   ├── Sources/                  # Swift & Objective-C source
│   │   ├── HiDPIDisplayApp.swift # Main app with SwiftUI
│   │   ├── VirtualDisplayManager.m # Display management (no-ARC)
│   │   └── CGVirtualDisplayPrivate.h # Private API declarations
│   ├── Resources/                # App icon
│   ├── launch-agent/             # launchd auto-start plist
│   ├── build.sh                  # Build script
│   ├── install-launchd.sh        # Auto-start installer
│   └── Info.plist                # App bundle config
├── Sources/                      # Command-line tool (alternative)
│   ├── main.swift                # CLI entry point
│   └── VirtualDisplayManager.*   # Shared display management
├── Makefile                      # CLI build system
└── README.md
```

## Troubleshooting

**App won't open**: Right-click and select "Open", then confirm in the security dialog.

**Resolution doesn't apply**: Disable HiDPI first, wait a few seconds, then try again.

**Display issues after changing monitor settings**: Quit and relaunch the app.

**Virtual display persists after quit**: Restart your Mac to clear orphaned displays.

**Frequent crashes**: Install the launch agent for automatic recovery:
```bash
./install-launchd.sh install
```

## How It Works

The app leverages macOS private APIs to create virtual displays with custom properties:

1. Creates a virtual display with HiDPI flag and 2x framebuffer
2. Configures display mirroring from virtual to physical display
3. macOS renders at 2x resolution into the virtual framebuffer
4. The framebuffer is scaled to your monitor's native resolution

## Technical Notes

- Built with Swift (UI) and Objective-C (display management)
- VirtualDisplayManager compiled without ARC (`-fno-objc-arc`) for manual memory control
- Window tracking to prevent framework-related crashes
- UserDefaults for state persistence across crashes

## Support

If G9 Helper improves your workflow, consider supporting development:

[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-☕-orange.svg?style=for-the-badge)](https://buymeacoffee.com/alcybr)

## License

MIT License - Free software, use at your own risk.

This software uses undocumented macOS APIs that may change or break with future updates.

---

Created with ❤️ by AL in Dallas
