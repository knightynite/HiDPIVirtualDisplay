# G9 Helper

A macOS menu bar app that enables HiDPI (Retina) scaling on Samsung G9 and other external monitors.

Made with love by AL in Dallas

## The Problem

macOS only enables crisp HiDPI rendering on displays meeting certain pixel density requirements. Large monitors like the Samsung Odyssey G9 57" (7680x2160) don't qualify, leaving you with:
- **Tiny text** at native resolution, or
- **Blurry text** with macOS scaling

## The Solution

G9 Helper creates a virtual display with HiDPI enabled, then mirrors it to your physical monitor. macOS renders everything at 2x resolution, giving you crisp, Retina-quality text on any display.

## Supported Monitors

| Monitor | Native Resolution | Recommended HiDPI |
|---------|------------------|-------------------|
| Samsung G9 57" | 7680x2160 | 5120x1440 |
| Samsung G9 49" | 5120x1440 | 3840x1080 |
| 34" Ultrawide | 3440x1440 | 2560x1080 |
| 4K Displays | 3840x2160 | 2560x1440 |

## Installation

### From DMG (Recommended)

1. Download the latest DMG from [Releases](https://github.com/knightynite/HiDPIVirtualDisplay/releases)
2. Open the DMG file
3. Drag **G9 Helper.app** to the **Applications** folder
4. Launch G9 Helper from Applications or Spotlight
5. Look for the display icon in your menu bar

### From Source

```bash
# Clone the repository
git clone https://github.com/knightynite/HiDPIVirtualDisplay.git
cd HiDPIVirtualDisplay/App

# Build the app
./build.sh

# Install to Applications
cp -r "build/G9 Helper.app" /Applications/
```

### First Launch

On first launch, macOS may show a security warning. To open the app:
1. Right-click (or Control-click) on G9 Helper in Applications
2. Select "Open" from the context menu
3. Click "Open" in the dialog

## Uninstallation

1. Click the G9 Helper icon in the menu bar
2. Select **Quit** to close the app
3. Open **Applications** folder in Finder
4. Drag **G9 Helper.app** to Trash
5. Empty Trash

## Usage

1. Launch G9 Helper - a display icon appears in your menu bar
2. Click the icon to see available presets
3. Select your monitor type (Samsung G9 57", G9 49", etc.)
4. Choose a resolution preset
5. Wait a few seconds for the display to configure

To disable HiDPI, click the menu bar icon and select **Disable HiDPI**.

## Requirements

- macOS 12.0 (Monterey) or later
- Apple Silicon recommended (M1/M2/M3/M4)
  - Base chips: Max 6144px horizontal HiDPI
  - Pro/Max/Ultra: Max 7680px+ horizontal HiDPI
- Intel Macs may work with limitations

## How It Works

1. Creates a virtual display using private macOS APIs
2. Configures HiDPI mode with a 2x framebuffer
3. Mirrors the virtual display to your physical monitor
4. macOS renders at 2x, then scales to your display's native resolution

## Presets

### Samsung G9 57" (7680x2160)

| Preset | Looks Like | Notes |
|--------|-----------|-------|
| Native 2x | 3840x1080 | Largest UI, sharpest |
| 5120x1440 | 5120x1440 | Recommended |
| 4800x1350 | 4800x1350 | Balanced |
| 4480x1260 | 4480x1260 | Larger UI |

### Samsung G9 49" (5120x1440)

| Preset | Looks Like |
|--------|-----------|
| 3840x1080 | Recommended |
| Native 2x | 2560x720 |

## Limitations

- Refresh rate limited to 60Hz in mirrored mode
- HDR may not work in mirrored mode
- May need to re-enable after sleep/wake
- Uses private APIs that could break with macOS updates

## Troubleshooting

### App won't open
Right-click the app and select "Open", then click "Open" in the security dialog.

### Resolution doesn't change
1. Click "Disable HiDPI" first
2. Wait a few seconds
3. Try selecting the preset again

### Display configuration changed and app stopped working
The app resets display configuration on launch. Quit and relaunch the app.

### Virtual display persists after quit
Restart your Mac to clear orphaned virtual displays.

## Building from Source

### Requirements
- Xcode Command Line Tools: `xcode-select --install`
- macOS 12.0+ SDK

### Build Commands

```bash
# Build the app
cd App && ./build.sh

# Create distributable DMG
./create-dmg.sh
```

## Technical Details

Uses private CoreGraphics APIs:
- `CGVirtualDisplay` - Creates virtual displays
- `CGVirtualDisplayDescriptor` - Display properties
- `CGVirtualDisplaySettings` - HiDPI configuration

Public APIs:
- `CGConfigureDisplayMirrorOfDisplay` - Display mirroring

## License

MIT License - Use at your own risk.

This tool uses undocumented macOS APIs that may break with future updates.

---

Made with love by AL in Dallas
