# HiDPI Display

A macOS menu bar app that enables HiDPI (Retina) scaling on external monitors that don't natively support it.

**Perfect for:**
- Samsung Odyssey G9 57" (7680x2160)
- Samsung Odyssey G9 49" (5120x1440)
- 34" Ultrawides (3440x1440)
- 4K monitors where macOS scaling looks blurry

## How It Works

macOS only enables crisp HiDPI rendering on displays that meet certain pixel density requirements. Large monitors like the Samsung G9 don't qualify, so you're stuck with either:
- Tiny text at native resolution
- Blurry scaled text

**This app fixes that** by:
1. Creating a virtual display with HiDPI enabled at your desired "looks like" resolution
2. Mirroring the virtual display to your physical monitor
3. macOS renders everything at 2x in the virtual display's framebuffer
4. The result: **crisp, Retina-quality text** on any monitor

## Screenshots

The app lives in your menu bar. Click the display icon to:
- See current status
- Choose from preset resolutions
- Enter custom resolutions
- Enable/disable HiDPI mode
- Set to launch at login

## Installation

### Option 1: Download Release
1. Download the latest `HiDPI.Display.dmg` from Releases
2. Open the DMG
3. Drag `HiDPI Display.app` to Applications
4. Launch from Applications or Spotlight

### Option 2: Build from Source
```bash
cd App
./build.sh
cp -r "build/HiDPI Display.app" /Applications/
```

## Usage

1. **Launch the app** - Look for the display icon in your menu bar
2. **Select your monitor type** - Expand the category matching your display
3. **Choose a preset** - Or enter a custom "looks like" resolution
4. **Done!** - Your display now has HiDPI scaling

### Preset Guide

#### Samsung G9 57" (7680x2160 native)
| Preset | Looks Like | Best For |
|--------|-----------|----------|
| Native 2x HiDPI | 3840x1080 | Maximum sharpness, larger UI |
| **5120x1440 HiDPI** | 5120x1440 | **Recommended** - Good balance |
| 4800x1350 HiDPI | 4800x1350 | Slightly larger UI |
| 4480x1260 HiDPI | 4480x1260 | Even larger UI |

#### Samsung G9 49" (5120x1440 native)
| Preset | Looks Like | Best For |
|--------|-----------|----------|
| Native 2x HiDPI | 2560x720 | Maximum sharpness |
| 3840x1080 HiDPI | 3840x1080 | More workspace |

## Requirements

- **macOS 12.0 (Monterey)** or later
- **Apple Silicon Mac** (M1/M2/M3/M4) recommended
  - M1/M2 base: Max 6144px horizontal HiDPI
  - M1/M2/M3/M4 Pro/Max/Ultra: Max 7680px+ horizontal HiDPI
- Intel Macs may work but with limitations

## Limitations

- **Refresh rate**: Virtual display mirroring typically limits you to 60Hz
- **HDR**: May not work in mirrored mode
- **Sleep/wake**: Virtual display may need to be re-created after sleep
- **Private APIs**: Uses undocumented macOS APIs that could break with updates

## Troubleshooting

### App won't create virtual display
- The app uses private macOS APIs that may require special entitlements
- Try running from Terminal to see error messages:
  ```bash
  /Applications/HiDPI\ Display.app/Contents/MacOS/HiDPIDisplay
  ```

### Display looks wrong after enabling
- Try a different preset
- Use "Disable" to return to normal, then try again

### Virtual display disappears after sleep
- This is a known limitation of the mirroring approach
- The app will attempt to re-create the display automatically
- If not, toggle the preset off and on again

## Technical Details

The app uses these macOS APIs:
- **CGVirtualDisplay** (private) - Creates virtual displays
- **CGVirtualDisplayDescriptor** (private) - Configures display properties
- **CGConfigureDisplayMirrorOfDisplay** (public) - Sets up mirroring

## Building

Requirements:
- Xcode Command Line Tools
- macOS 12.0+ SDK

```bash
# Clone the repo
git clone https://github.com/yourusername/HiDPIVirtualDisplay.git
cd HiDPIVirtualDisplay/App

# Build
./build.sh

# The app will be at: build/HiDPI Display.app
```

## Credits

Inspired by and based on research from:
- [BetterDisplay](https://github.com/waydabber/BetterDisplay)
- [FluffyDisplay](https://github.com/tml1024/FluffyDisplay)
- [macOS Headers](https://github.com/w0lfschild/macOS_headers)

## License

MIT License - Use at your own risk.

---

**Note**: This app uses undocumented/private macOS APIs. It may break with future macOS updates. Use at your own risk.
