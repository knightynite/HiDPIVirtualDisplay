# HiDPI Virtual Display

A macOS tool that enables HiDPI (Retina) scaling on external monitors that don't natively support it. Includes both a **menu bar app** and a **command-line tool**.

## The Problem

macOS only enables crisp HiDPI rendering on displays meeting certain pixel density requirements. Large monitors like the Samsung Odyssey G9 57" (7680x2160) don't qualify, leaving you with:
- **Tiny text** at native resolution, or
- **Blurry text** with macOS scaling

## The Solution

This tool creates a virtual display with HiDPI enabled, then mirrors it to your physical monitor. macOS renders everything at 2x resolution, giving you **crisp, Retina-quality text** on any display.

## Supported Monitors

| Monitor | Native Resolution | Recommended HiDPI |
|---------|------------------|-------------------|
| Samsung G9 57" | 7680x2160 | 5120x1440 |
| Samsung G9 49" | 5120x1440 | 3840x1080 |
| 34" Ultrawide | 3440x1440 | 2560x1080 |
| 4K Displays | 3840x2160 | 2560x1440 |

## Installation

### Menu Bar App (Recommended)

```bash
# Build the app
cd App
./build.sh

# Install to Applications
cp -r "build/HiDPI Display.app" /Applications/

# Or create a DMG for distribution
./create-dmg.sh
```

### Command-Line Tool

```bash
# Build
make

# Install (optional)
sudo make install
```

## Usage

### Menu Bar App

1. Launch **HiDPI Display** from Applications
2. Click the display icon in your menu bar
3. Select your monitor type and choose a preset
4. Done! Your display now has HiDPI scaling

### Command-Line Tool

```bash
# List connected displays
hidpi-virtual-display list

# Show available presets
hidpi-virtual-display presets

# Create virtual display with preset
hidpi-virtual-display create g9-5120x1440

# Mirror to your monitor (in another terminal)
hidpi-virtual-display mirror <virtual-id> <monitor-id>

# Disable
hidpi-virtual-display unmirror <monitor-id>
hidpi-virtual-display destroy-all
```

## Requirements

- **macOS 12.0** (Monterey) or later
- **Apple Silicon** recommended (M1/M2/M3/M4)
  - Base chips: Max 6144px horizontal HiDPI
  - Pro/Max/Ultra: Max 7680px+ horizontal HiDPI
- Intel Macs may work with limitations

## Project Structure

```
HiDPIVirtualDisplay/
├── App/                          # Menu bar application
│   ├── Sources/
│   │   ├── HiDPIDisplayApp.swift # SwiftUI app
│   │   ├── VirtualDisplayManager.m
│   │   └── CGVirtualDisplayPrivate.h
│   ├── build.sh                  # Build script
│   ├── create-dmg.sh             # DMG creator
│   └── README.md
├── Sources/                      # CLI tool
│   ├── main.swift
│   ├── VirtualDisplayManager.m
│   └── CGVirtualDisplayPrivate.h
├── Makefile
└── README.md
```

## How It Works

1. **Creates a virtual display** using private `CGVirtualDisplay` APIs
2. **Configures HiDPI mode** with a 2x framebuffer (e.g., 10240x2880 for "5120x1440")
3. **Mirrors the virtual display** to your physical monitor using `CGConfigureDisplayMirrorOfDisplay`
4. **macOS renders at 2x** then scales to your display's native resolution

## Presets

### Samsung G9 57" (7680x2160)

| Preset | Looks Like | Framebuffer | Notes |
|--------|-----------|-------------|-------|
| Native 2x | 3840x1080 | 7680x2160 | Sharpest, larger UI |
| **5120x1440** | 5120x1440 | 10240x2880 | **Recommended** |
| 4800x1350 | 4800x1350 | 9600x2700 | Balanced |
| 4480x1260 | 4480x1260 | 8960x2520 | Larger UI |

### Samsung G9 49" (5120x1440)

| Preset | Looks Like | Framebuffer |
|--------|-----------|-------------|
| Native 2x | 2560x720 | 5120x1440 |
| 3840x1080 | 3840x1080 | 7680x2160 |

## Limitations

- **Refresh rate**: Mirroring typically limits to 60Hz
- **HDR**: May not work in mirrored mode
- **Sleep/wake**: May need to re-enable after sleep
- **Private APIs**: Could break with macOS updates

## Troubleshooting

### "Failed to create virtual display"
- The app uses private macOS APIs
- Try running from Terminal to see error messages
- May require disabling SIP (not recommended)

### Display looks wrong
- Try a different preset
- Disable and re-enable

### Virtual display disappears after sleep
- Toggle the preset off and on again

## Technical Details

### APIs Used

**Private (undocumented):**
- `CGVirtualDisplay` - Creates virtual displays
- `CGVirtualDisplayDescriptor` - Display properties
- `CGVirtualDisplaySettings` - HiDPI configuration
- `CGVirtualDisplayMode` - Resolution/refresh rate

**Public:**
- `CGConfigureDisplayMirrorOfDisplay` - Display mirroring
- `CGBeginDisplayConfiguration` - Configuration transactions

### References

- [BetterDisplay](https://github.com/waydabber/BetterDisplay) - Inspiration
- [FluffyDisplay](https://github.com/tml1024/FluffyDisplay) - Reference implementation
- [macOS Headers](https://github.com/w0lfschild/macOS_headers) - API definitions

## Building from Source

### Requirements
- Xcode Command Line Tools (`xcode-select --install`)
- macOS 12.0+ SDK

### Build Commands

```bash
# Menu bar app
cd App && ./build.sh

# CLI tool
make

# Create distributable DMG
cd App && ./create-dmg.sh
```

## License

MIT License - Use at your own risk.

**Warning**: This tool uses undocumented macOS APIs that may break with future updates.

---

Made for the Samsung Odyssey G9 57" and other high-resolution monitors that deserve proper HiDPI support on macOS.
