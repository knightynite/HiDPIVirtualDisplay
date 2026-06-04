// VirtualDisplayManager.m
// Implementation of virtual display creation using private CoreGraphics APIs
// Compiled with -fno-objc-arc - uses manual retain/release

#import "VirtualDisplayManager.h"
#import "CGVirtualDisplayPrivate.h"
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import <IOKit/IOKitLib.h>
#import <dlfcn.h>

// Compatibility for older SDKs
#ifndef kIOMainPortDefault
#define kIOMainPortDefault 0
#endif

// Global array to retain windows that appear during display operations
// This prevents the CGVirtualDisplay framework's internal windows from being over-released
static NSMutableArray *_retainedWindows = nil;
static id _windowObserver = nil;

@interface VirtualDisplayManager () {
    CGVirtualDisplay *_display;
    CGVirtualDisplayDescriptor *_descriptor;
    CGVirtualDisplaySettings *_settings;
    CGVirtualDisplayMode *_mode;
    NSArray *_modesArray;
    NSString *_displayName;
    CGDirectDisplayID _currentDisplayID;
}
@end

/// Read a 16-bit fixed-point chromaticity value from a nested CF dictionary.
/// DisplayAttributes stores chromaticity as integers in [0, 65536] range.
static CGFloat cfDictGetFixed16(CFDictionaryRef dict, CFStringRef key) {
    CFNumberRef ref = CFDictionaryGetValue(dict, key);
    if (!ref) return 0;
    int32_t raw = 0;
    CFNumberGetValue(ref, kCFNumberSInt32Type, &raw);
    return (CGFloat)raw / 65536.0;
}

@implementation VirtualDisplayManager

// Helper function to retain a window if not already retained
static void retainWindowIfNeeded(NSWindow *window) {
    if (window && ![_retainedWindows containsObject:window]) {
        [window retain];
        [_retainedWindows addObject:window];
        NSLog(@"VDM: Retained window: %p (class: %@, title: %@)",
              window, [window class], [window title] ?: @"<untitled>");
    }
}

+ (void)initialize {
    if (self == [VirtualDisplayManager class]) {
        // Initialize the retained windows array
        _retainedWindows = [[NSMutableArray alloc] init];
        [_retainedWindows retain];
        NSLog(@"VDM: Window retention array initialized");

        // Observe multiple window notifications to catch framework-created windows
        NSArray *notifications = @[
            NSWindowDidBecomeMainNotification,
            NSWindowDidBecomeKeyNotification,
            NSWindowDidUpdateNotification,
            NSWindowDidChangeScreenNotification,
            NSWindowDidExposeNotification
        ];

        for (NSNotificationName notifName in notifications) {
            [[NSNotificationCenter defaultCenter]
                addObserverForName:notifName
                object:nil
                queue:nil
                usingBlock:^(NSNotification *notification) {
                    retainWindowIfNeeded(notification.object);
                }];
        }

        // Also prevent windows from being released when they close
        [[NSNotificationCenter defaultCenter]
            addObserverForName:NSWindowWillCloseNotification
            object:nil
            queue:nil
            usingBlock:^(NSNotification *notification) {
                NSWindow *window = notification.object;
                if (window) {
                    // Extra retain to counteract the close release
                    [window retain];
                    NSLog(@"VDM: Extra retain on closing window: %p", window);
                }
            }];

        NSLog(@"VDM: Window observers installed");
    }
}

+ (instancetype)sharedManager {
    static VirtualDisplayManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[VirtualDisplayManager alloc] init];
        [sharedManager retain];
        NSLog(@"VDM: Shared manager created");
    });
    return sharedManager;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _display = nil;
        _descriptor = nil;
        _settings = nil;
        _mode = nil;
        _modesArray = nil;
        _displayName = nil;
        _currentDisplayID = kCGNullDirectDisplay;

        // Retain all existing windows to prevent crash from framework window over-release
        for (NSWindow *window in [NSApp windows]) {
            retainWindowIfNeeded(window);
        }

        // Scan for windows once at init. The notification observers above will
        // catch any new windows going forward. The previous 2-second repeating
        // timer added unnecessary main-thread load during display operations.

        NSLog(@"VDM: Manager initialized");
    }
    return self;
}

- (CGDirectDisplayID)currentDisplayID {
    return _currentDisplayID;
}

// Internal creation method that accepts explicit color primaries.
// Both public create methods delegate to this.
- (CGDirectDisplayID)_createDisplayInternalWithWidth:(unsigned int)width
                                              height:(unsigned int)height
                                                 ppi:(unsigned int)ppi
                                               hiDPI:(BOOL)hiDPI
                                                name:(NSString *)name
                                         refreshRate:(double)refreshRate
                                          whitePoint:(CGPoint)whitePoint
                                          redPrimary:(CGPoint)redPrimary
                                        greenPrimary:(CGPoint)greenPrimary
                                         bluePrimary:(CGPoint)bluePrimary {

    NSLog(@"VDM: ========== CREATE START ==========");
    NSLog(@"VDM: %ux%u @ %u PPI, HiDPI=%@", width, height, ppi, hiDPI ? @"YES" : @"NO");
    NSLog(@"VDM: Primaries: R(%.4f,%.4f) G(%.4f,%.4f) B(%.4f,%.4f) W(%.4f,%.4f)",
          redPrimary.x, redPrimary.y, greenPrimary.x, greenPrimary.y,
          bluePrimary.x, bluePrimary.y, whitePoint.x, whitePoint.y);

    @try {
        // Create settings and retain
        CGVirtualDisplaySettings *settings = [[CGVirtualDisplaySettings alloc] init];
        [settings retain];
        settings.hiDPI = hiDPI ? 1 : 0;
        _settings = settings;

        // Create descriptor and retain
        CGVirtualDisplayDescriptor *descriptor = [[CGVirtualDisplayDescriptor alloc] init];
        [descriptor retain];
        // Use a dedicated serial queue instead of the main queue.
        // Main queue contention between virtual display callbacks and UI/timer
        // work contributed to the WindowServer deadlock.
        descriptor.queue = dispatch_queue_create("com.hidpi.virtualdisplay.events",
                                                  DISPATCH_QUEUE_SERIAL);

        _displayName = [[name copy] retain];
        descriptor.name = _displayName;

        // Set color primaries — when these match the physical display's EDID,
        // ColorSync can use an identity transform (no per-frame color conversion).
        descriptor.whitePoint = whitePoint;
        descriptor.redPrimary = redPrimary;
        descriptor.greenPrimary = greenPrimary;
        descriptor.bluePrimary = bluePrimary;

        float widthInInches = (float)width / (float)ppi;
        float heightInInches = (float)height / (float)ppi;
        descriptor.sizeInMillimeters = CGSizeMake(widthInInches * 25.4f, heightInInches * 25.4f);

        descriptor.maxPixelsWide = width;
        descriptor.maxPixelsHigh = height;
        descriptor.vendorID = 0x1234;
        descriptor.productID = 0x5678;
        // Use a fixed serial so ColorSync can reuse the same ICC profile
        // across restarts. arc4random() was generating a new serial every time,
        // causing ColorSync to create thousands of unique ICC profiles (4000+)
        // which made colorsync.displayservices spin at 60%+ CPU.
        descriptor.serialNum = 0x4731;
        descriptor.terminationHandler = nil;

        _descriptor = descriptor;

        unsigned int modeWidth = hiDPI ? width / 2 : width;
        unsigned int modeHeight = hiDPI ? height / 2 : height;
        NSLog(@"VDM: Mode: %ux%u", modeWidth, modeHeight);

        CGVirtualDisplayMode *mode = [[CGVirtualDisplayMode alloc] initWithWidth:modeWidth
                                                                          height:modeHeight
                                                                     refreshRate:refreshRate];
        if (!mode) {
            NSLog(@"VDM: ERROR - Failed to create mode");
            return kCGNullDirectDisplay;
        }
        [mode retain];
        _mode = mode;

        // Single-mode array — adding a 60 Hz fallback caused macOS to silently
        // pick the fallback over the requested rate after some mirror configs,
        // making the virtual render at 60 Hz even when the user asked for 120
        // (the panel scanned at 120 but content only updated 60 times/sec).
        // The caller is now responsible for clamping the requested rate to a
        // value the panel actually supports (via maxSupportedRefreshRate).
        NSMutableArray *modes = [NSMutableArray arrayWithObject:_mode];
        _modesArray = [modes retain];
        _settings.modes = _modesArray;

        NSLog(@"VDM: Creating display...");
        CGVirtualDisplay *display = [[CGVirtualDisplay alloc] initWithDescriptor:_descriptor];
        if (!display) {
            NSLog(@"VDM: ERROR - Failed to create display");
            return kCGNullDirectDisplay;
        }
        [display retain];
        _display = display;
        NSLog(@"VDM: Display created: %p", _display);

        NSLog(@"VDM: Applying settings...");
        BOOL applied = [_display applySettings:_settings];
        if (!applied) {
            NSLog(@"VDM: ERROR - Failed to apply settings");
            return kCGNullDirectDisplay;
        }
        NSLog(@"VDM: Settings applied");

        CGDirectDisplayID displayID = _display.displayID;
        _currentDisplayID = displayID;
        NSLog(@"VDM: Display ID: %u", displayID);

        if (displayID == 0 || displayID == kCGNullDirectDisplay) {
            NSLog(@"VDM: ERROR - Invalid display ID");
            return kCGNullDirectDisplay;
        }

        NSLog(@"VDM: ========== CREATE COMPLETE ==========");
        return displayID;

    } @catch (NSException *exception) {
        NSLog(@"VDM: EXCEPTION: %@", exception);
        return kCGNullDirectDisplay;
    }
}

- (CGDirectDisplayID)createVirtualDisplayWithWidth:(unsigned int)width
                                            height:(unsigned int)height
                                               ppi:(unsigned int)ppi
                                             hiDPI:(BOOL)hiDPI
                                              name:(NSString *)name
                                       refreshRate:(double)refreshRate {
    // Default to sRGB primaries when no target display is specified
    return [self _createDisplayInternalWithWidth:width height:height ppi:ppi
                                          hiDPI:hiDPI name:name refreshRate:refreshRate
                                     whitePoint:CGPointMake(0.3127, 0.3290)
                                     redPrimary:CGPointMake(0.6400, 0.3300)
                                   greenPrimary:CGPointMake(0.3000, 0.6000)
                                    bluePrimary:CGPointMake(0.1500, 0.0600)];
}

- (CGDirectDisplayID)createG9VirtualDisplayWithScaledWidth:(unsigned int)scaledWidth
                                              scaledHeight:(unsigned int)scaledHeight {
    // Detect refresh rate from the actual external display, not the built-in screen
    double refreshRate = 60.0;
    CGDirectDisplayID displayList[32];
    uint32_t displayCount;
    if (CGGetOnlineDisplayList(32, displayList, &displayCount) == kCGErrorSuccess) {
        for (uint32_t i = 0; i < displayCount; i++) {
            if (!CGDisplayIsBuiltin(displayList[i]) && CGDisplayVendorNumber(displayList[i]) != 0x1234) {
                CGDisplayModeRef mode = CGDisplayCopyDisplayMode(displayList[i]);
                if (mode) {
                    double rate = CGDisplayModeGetRefreshRate(mode);
                    CGDisplayModeRelease(mode);
                    if (rate > 0) {
                        refreshRate = rate;
                        NSLog(@"VDM: Detected external monitor refresh rate: %.0f Hz", rate);
                        break;
                    }
                }
            }
        }
    }
    NSLog(@"VDM: G9 convenience method using refresh rate: %.1f Hz", refreshRate);

    return [self createVirtualDisplayWithWidth:scaledWidth * 2
                                        height:scaledHeight * 2
                                           ppi:140
                                         hiDPI:YES
                                          name:@"G9 HiDPI Virtual"
                                   refreshRate:refreshRate];
}

- (BOOL)mirrorDisplay:(CGDirectDisplayID)sourceDisplayID
            toDisplay:(CGDirectDisplayID)targetDisplayID {
    return [self mirrorDisplay:sourceDisplayID toDisplay:targetDisplayID atRate:0.0];
}

/// Find the largest-pixel-count mode on `displayID` whose refresh rate matches
/// `refreshRate` within 0.5 Hz. Returns NULL if no match. Caller owns the
/// returned mode and must release it via CGDisplayModeRelease().
static CGDisplayModeRef CopyBestModeAtRate(CGDirectDisplayID displayID, double refreshRate) {
    NSDictionary *opts = @{ (__bridge NSString *)kCGDisplayShowDuplicateLowResolutionModes: @YES };
    CFArrayRef modes = CGDisplayCopyAllDisplayModes(displayID, (__bridge CFDictionaryRef)opts);
    if (!modes) return NULL;

    CGDisplayModeRef best = NULL;
    size_t bestPixels = 0;
    CFIndex count = CFArrayGetCount(modes);
    for (CFIndex i = 0; i < count; i++) {
        CGDisplayModeRef mode = (CGDisplayModeRef)CFArrayGetValueAtIndex(modes, i);
        double rate = CGDisplayModeGetRefreshRate(mode);
        if (fabs(rate - refreshRate) > 0.5) continue;
        size_t pixels = CGDisplayModeGetWidth(mode) * CGDisplayModeGetHeight(mode);
        if (pixels > bestPixels) {
            bestPixels = pixels;
            best = mode;
        }
    }
    CGDisplayModeRef retained = best ? (CGDisplayModeRef)CGDisplayModeRetain(best) : NULL;
    CFRelease(modes);
    return retained;
}

- (BOOL)mirrorDisplay:(CGDirectDisplayID)sourceDisplayID
            toDisplay:(CGDirectDisplayID)targetDisplayID
               atRate:(double)refreshRate {

    NSLog(@"VDM: Mirror %u -> %u (pin target to %.1f Hz)",
          sourceDisplayID, targetDisplayID, refreshRate);

    // Step 1 — pin the physical target to a fixed-rate native mode in its
    // OWN config block BEFORE the mirror is set up. Combining pin + mirror
    // in one config block conflicts (the mirror call resets target mode and
    // rejects the whole config). Doing it first ensures the panel is in a
    // stable fixed scanout when the mirror call attaches it to the source.
    if (refreshRate > 0) {
        CGDisplayModeRef pinMode = CopyBestModeAtRate(targetDisplayID, refreshRate);
        if (pinMode) {
            CGDisplayConfigRef pinConfig;
            if (CGBeginDisplayConfiguration(&pinConfig) == kCGErrorSuccess) {
                NSLog(@"VDM: Pinning target to %zux%zu @ %.1f Hz",
                      CGDisplayModeGetWidth(pinMode),
                      CGDisplayModeGetHeight(pinMode),
                      CGDisplayModeGetRefreshRate(pinMode));
                CGError pinErr = CGConfigureDisplayWithDisplayMode(pinConfig, targetDisplayID, pinMode, NULL);
                if (pinErr == kCGErrorSuccess) {
                    pinErr = CGCompleteDisplayConfiguration(pinConfig, kCGConfigureForSession);
                    if (pinErr != kCGErrorSuccess) {
                        NSLog(@"VDM: WARN - Pin complete failed: %d", pinErr);
                    }
                } else {
                    NSLog(@"VDM: WARN - Pin configure failed: %d", pinErr);
                    CGCancelDisplayConfiguration(pinConfig);
                }
            }
            CGDisplayModeRelease(pinMode);
        } else {
            NSLog(@"VDM: WARN - No %.1f Hz mode found on target %u",
                  refreshRate, targetDisplayID);
        }
    }

    // Step 2 — configure the mirror in its own config block.
    CGDisplayConfigRef configRef;
    CGError err = CGBeginDisplayConfiguration(&configRef);
    if (err != kCGErrorSuccess) {
        NSLog(@"VDM: ERROR - Begin config failed: %d", err);
        return NO;
    }

    err = CGConfigureDisplayMirrorOfDisplay(configRef, targetDisplayID, sourceDisplayID);
    if (err != kCGErrorSuccess) {
        NSLog(@"VDM: ERROR - Configure mirror failed: %d", err);
        CGCancelDisplayConfiguration(configRef);
        return NO;
    }

    // Use kCGConfigureForSession instead of kCGConfigurePermanently to avoid
    // triggering ColorSync profile persistence I/O that can stall the daemon.
    err = CGCompleteDisplayConfiguration(configRef, kCGConfigureForSession);
    if (err != kCGErrorSuccess) {
        NSLog(@"VDM: ERROR - Complete config failed: %d", err);
        return NO;
    }

    // Verify what the panel ended up at — this is the ground truth for
    // whether the pin survived. Log so we can confirm without needing to
    // perceive the difference visually.
    CGDisplayModeRef actual = CGDisplayCopyDisplayMode(targetDisplayID);
    if (actual) {
        NSLog(@"VDM: Mirror success — target %u now at %zux%zu @ %.1f Hz",
              targetDisplayID,
              CGDisplayModeGetWidth(actual),
              CGDisplayModeGetHeight(actual),
              CGDisplayModeGetRefreshRate(actual));
        CGDisplayModeRelease(actual);
    } else {
        NSLog(@"VDM: Mirror success (could not read back target mode)");
    }
    return YES;
}

- (BOOL)stopMirroringForDisplay:(CGDirectDisplayID)displayID {
    NSLog(@"VDM: Stop mirror for %u", displayID);

    CGDisplayConfigRef configRef;
    CGError err = CGBeginDisplayConfiguration(&configRef);
    if (err != kCGErrorSuccess) return NO;

    err = CGConfigureDisplayMirrorOfDisplay(configRef, displayID, kCGNullDirectDisplay);
    if (err != kCGErrorSuccess) {
        CGCancelDisplayConfiguration(configRef);
        return NO;
    }

    err = CGCompleteDisplayConfiguration(configRef, kCGConfigureForSession);
    if (err != kCGErrorSuccess) return NO;

    NSLog(@"VDM: Stop mirror success");
    return YES;
}

- (void)destroyVirtualDisplay:(CGDirectDisplayID)displayID {
    NSLog(@"VDM: destroyVirtualDisplay called for %u", displayID);
    if (displayID == _currentDisplayID) {
        [self releaseDisplayObjects];
    }
}

- (void)destroyAllVirtualDisplays {
    NSLog(@"VDM: destroyAllVirtualDisplays called");
    [self releaseDisplayObjects];
}

- (void)releaseDisplayObjects {
    NSLog(@"VDM: Releasing display objects...");

    // Release in reverse order of creation
    if (_display) {
        NSLog(@"VDM: Releasing _display %p", _display);
        [_display release];
        _display = nil;
    }

    if (_modesArray) {
        [_modesArray release];
        _modesArray = nil;
    }

    if (_mode) {
        [_mode release];
        _mode = nil;
    }

    if (_settings) {
        [_settings release];
        _settings = nil;
    }

    if (_descriptor) {
        [_descriptor release];
        _descriptor = nil;
    }

    if (_displayName) {
        [_displayName release];
        _displayName = nil;
    }

    _currentDisplayID = kCGNullDirectDisplay;
    NSLog(@"VDM: Display objects released");
}

- (void)resetAllMirroring {
    NSLog(@"VDM: resetAllMirroring called");
    CGDirectDisplayID displayList[32];
    uint32_t displayCount;

    CGError err = CGGetOnlineDisplayList(32, displayList, &displayCount);
    if (err != kCGErrorSuccess) return;

    for (uint32_t i = 0; i < displayCount; i++) {
        CGDirectDisplayID displayID = displayList[i];
        CGDirectDisplayID mirrorOf = CGDisplayMirrorsDisplay(displayID);
        if (mirrorOf != kCGNullDirectDisplay) {
            [self stopMirroringForDisplay:displayID];
        }
    }
    NSLog(@"VDM: Reset mirroring complete");
}

- (NSArray<NSDictionary *> *)listAllDisplays {
    NSMutableArray *displays = [NSMutableArray array];
    CGDirectDisplayID displayList[32];
    uint32_t displayCount;

    if (CGGetOnlineDisplayList(32, displayList, &displayCount) != kCGErrorSuccess) {
        return displays;
    }

    for (uint32_t i = 0; i < displayCount; i++) {
        CGDirectDisplayID displayID = displayList[i];
        CGDisplayModeRef mode = CGDisplayCopyDisplayMode(displayID);
        if (mode) {
            [displays addObject:@{
                @"id": @(displayID),
                @"width": @(CGDisplayModeGetWidth(mode)),
                @"height": @(CGDisplayModeGetHeight(mode)),
                @"isMain": @(CGDisplayIsMain(displayID)),
                @"isBuiltin": @(CGDisplayIsBuiltin(displayID)),
                @"mirrorOf": @(CGDisplayMirrorsDisplay(displayID)),
                @"isVirtual": @(displayID == _currentDisplayID)
            }];
            CGDisplayModeRelease(mode);
        }
    }
    return displays;
}

- (CGDirectDisplayID)mainDisplayID {
    return CGMainDisplayID();
}

- (BOOL)isVirtualDisplay:(CGDirectDisplayID)displayID {
    return displayID == _currentDisplayID;
}

#pragma mark - EDID Chromaticity Reading

- (BOOL)getChromaticityForDisplay:(CGDirectDisplayID)displayID
                            redX:(CGFloat *)redX redY:(CGFloat *)redY
                          greenX:(CGFloat *)greenX greenY:(CGFloat *)greenY
                           blueX:(CGFloat *)blueX blueY:(CGFloat *)blueY
                          whiteX:(CGFloat *)whiteX whiteY:(CGFloat *)whiteY {

    uint32_t targetVendor = CGDisplayVendorNumber(displayID);
    uint32_t targetProduct = CGDisplayModelNumber(displayID);
    NSLog(@"VDM: Reading EDID chromaticity for display %u (vendor=%u, product=%u)",
          displayID, targetVendor, targetProduct);

    // Strategy 1: Apple Silicon — read DisplayAttributes from IOMobileFramebufferShim.
    // On Apple Silicon Macs, display metadata (including parsed EDID chromaticity)
    // lives in the DisplayAttributes dictionary on IOMobileFramebufferShim services.
    io_iterator_t iter;
    kern_return_t kr = IOServiceGetMatchingServices(kIOMainPortDefault,
                                                     IOServiceMatching("IOMobileFramebufferShim"),
                                                     &iter);
    if (kr == KERN_SUCCESS) {
        io_service_t service;
        while ((service = IOIteratorNext(iter)) != 0) {
            CFDictionaryRef attrs = IORegistryEntryCreateCFProperty(
                service, CFSTR("DisplayAttributes"), kCFAllocatorDefault, 0);
            IOObjectRelease(service);
            if (!attrs) continue;

            CFDictionaryRef productAttrs = CFDictionaryGetValue(attrs, CFSTR("ProductAttributes"));
            if (!productAttrs) { CFRelease(attrs); continue; }

            uint32_t vendor = 0, product = 0;
            CFNumberRef numRef;

            numRef = CFDictionaryGetValue(productAttrs, CFSTR("LegacyManufacturerID"));
            if (numRef) CFNumberGetValue(numRef, kCFNumberSInt32Type, &vendor);

            numRef = CFDictionaryGetValue(productAttrs, CFSTR("ProductID"));
            if (numRef) CFNumberGetValue(numRef, kCFNumberSInt32Type, &product);

            if (vendor != targetVendor || product != targetProduct) {
                CFRelease(attrs);
                continue;
            }

            // Found the matching display — extract chromaticity
            CFDictionaryRef chroma = CFDictionaryGetValue(attrs, CFSTR("Chromaticity"));
            CFDictionaryRef wp = CFDictionaryGetValue(attrs, CFSTR("DefaultWhitePoint"));

            if (chroma && wp) {
                CFDictionaryRef red = CFDictionaryGetValue(chroma, CFSTR("Red"));
                CFDictionaryRef green = CFDictionaryGetValue(chroma, CFSTR("Green"));
                CFDictionaryRef blue = CFDictionaryGetValue(chroma, CFSTR("Blue"));

                if (red && green && blue) {
                    *redX   = cfDictGetFixed16(red,   CFSTR("X"));
                    *redY   = cfDictGetFixed16(red,   CFSTR("Y"));
                    *greenX = cfDictGetFixed16(green, CFSTR("X"));
                    *greenY = cfDictGetFixed16(green, CFSTR("Y"));
                    *blueX  = cfDictGetFixed16(blue,  CFSTR("X"));
                    *blueY  = cfDictGetFixed16(blue,  CFSTR("Y"));
                    *whiteX = cfDictGetFixed16(wp,    CFSTR("X"));
                    *whiteY = cfDictGetFixed16(wp,    CFSTR("Y"));

                    NSLog(@"VDM: EDID chromaticity (DisplayAttributes):");
                    NSLog(@"VDM:   Red:   (%.4f, %.4f)", *redX, *redY);
                    NSLog(@"VDM:   Green: (%.4f, %.4f)", *greenX, *greenY);
                    NSLog(@"VDM:   Blue:  (%.4f, %.4f)", *blueX, *blueY);
                    NSLog(@"VDM:   White: (%.4f, %.4f)", *whiteX, *whiteY);

                    CFRelease(attrs);
                    IOObjectRelease(iter);
                    return YES;
                }
            }
            CFRelease(attrs);
        }
        IOObjectRelease(iter);
    }

    // Strategy 2: Intel fallback — read raw EDID from IODisplayConnect services.
    kr = IOServiceGetMatchingServices(kIOMainPortDefault,
                                       IOServiceMatching("IODisplayConnect"),
                                       &iter);
    if (kr == KERN_SUCCESS) {
        io_service_t service;
        while ((service = IOIteratorNext(iter)) != 0) {
            CFDataRef edidData = IORegistryEntryCreateCFProperty(
                service, CFSTR("IODisplayEDID"), kCFAllocatorDefault, 0);
            IOObjectRelease(service);
            if (!edidData) continue;

            const UInt8 *bytes = CFDataGetBytePtr(edidData);
            CFIndex len = CFDataGetLength(edidData);

            if (len >= 12) {
                // EDID manufacturer ID: bytes 8-9 (big-endian PnP compressed ASCII)
                uint16_t mfg  = ((uint16_t)bytes[8] << 8) | bytes[9];
                // EDID product code: bytes 10-11 (little-endian)
                uint16_t prod = ((uint16_t)bytes[11] << 8) | bytes[10];

                if (mfg == targetVendor && prod == targetProduct && len >= 35) {
                    // EDID chromaticity: bytes 25-34 (10-bit values, /1024)
                    UInt8 b25 = bytes[25], b26 = bytes[26];
                    uint16_t rx = ((uint16_t)bytes[27] << 2) | ((b25 >> 6) & 0x03);
                    uint16_t ry = ((uint16_t)bytes[28] << 2) | ((b25 >> 4) & 0x03);
                    uint16_t gx = ((uint16_t)bytes[29] << 2) | ((b25 >> 2) & 0x03);
                    uint16_t gy = ((uint16_t)bytes[30] << 2) | ((b25 >> 0) & 0x03);
                    uint16_t bx = ((uint16_t)bytes[31] << 2) | ((b26 >> 6) & 0x03);
                    uint16_t by = ((uint16_t)bytes[32] << 2) | ((b26 >> 4) & 0x03);
                    uint16_t wx = ((uint16_t)bytes[33] << 2) | ((b26 >> 2) & 0x03);
                    uint16_t wy = ((uint16_t)bytes[34] << 2) | ((b26 >> 0) & 0x03);

                    *redX   = (CGFloat)rx / 1024.0;
                    *redY   = (CGFloat)ry / 1024.0;
                    *greenX = (CGFloat)gx / 1024.0;
                    *greenY = (CGFloat)gy / 1024.0;
                    *blueX  = (CGFloat)bx / 1024.0;
                    *blueY  = (CGFloat)by / 1024.0;
                    *whiteX = (CGFloat)wx / 1024.0;
                    *whiteY = (CGFloat)wy / 1024.0;

                    NSLog(@"VDM: EDID chromaticity (IODisplayEDID):");
                    NSLog(@"VDM:   Red:   (%.4f, %.4f)", *redX, *redY);
                    NSLog(@"VDM:   Green: (%.4f, %.4f)", *greenX, *greenY);
                    NSLog(@"VDM:   Blue:  (%.4f, %.4f)", *blueX, *blueY);
                    NSLog(@"VDM:   White: (%.4f, %.4f)", *whiteX, *whiteY);

                    CFRelease(edidData);
                    IOObjectRelease(iter);
                    return YES;
                }
            }
            CFRelease(edidData);
        }
        IOObjectRelease(iter);
    }

    NSLog(@"VDM: WARNING - Could not read chromaticity for display %u", displayID);
    return NO;
}

#pragma mark - Color-Matched Virtual Display Creation

- (CGDirectDisplayID)createVirtualDisplayWithWidth:(unsigned int)width
                                            height:(unsigned int)height
                                               ppi:(unsigned int)ppi
                                             hiDPI:(BOOL)hiDPI
                                              name:(NSString *)name
                                       refreshRate:(double)refreshRate
                              matchingDisplay:(CGDirectDisplayID)targetDisplayID {

    NSLog(@"VDM: Creating virtual display matching physical display %u", targetDisplayID);

    CGFloat rX, rY, gX, gY, bX, bY, wX, wY;
    CGPoint white, red, green, blue;

    if ([self getChromaticityForDisplay:targetDisplayID
                                  redX:&rX redY:&rY
                                greenX:&gX greenY:&gY
                                 blueX:&bX blueY:&bY
                                whiteX:&wX whiteY:&wY]) {
        NSLog(@"VDM: Using target display's EDID chromaticity → identity ColorSync transform");
        white = CGPointMake(wX, wY);
        red   = CGPointMake(rX, rY);
        green = CGPointMake(gX, gY);
        blue  = CGPointMake(bX, bY);
    } else {
        NSLog(@"VDM: WARNING - EDID read failed, falling back to sRGB primaries");
        white = CGPointMake(0.3127, 0.3290);
        red   = CGPointMake(0.6400, 0.3300);
        green = CGPointMake(0.3000, 0.6000);
        blue  = CGPointMake(0.1500, 0.0600);
    }

    return [self _createDisplayInternalWithWidth:width height:height ppi:ppi
                                          hiDPI:hiDPI name:name refreshRate:refreshRate
                                     whitePoint:white
                                     redPrimary:red
                                   greenPrimary:green
                                    bluePrimary:blue];
}

#pragma mark - HDR control (Beta)

// SkyLight exposes per-display HDR control that stays in sync with the
// System Settings ▸ Displays "High Dynamic Range" checkbox. SkyLight is a
// private framework, so we resolve the symbols at runtime rather than link it.
typedef bool (*SLHDRQueryFn)(CGDirectDisplayID);
typedef int  (*SLHDRSetFn)(CGDirectDisplayID, bool);

static void *VDMSkyLightHandle(void) {
    static void *handle = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY);
        if (!handle) {
            NSLog(@"VDM: WARNING - could not dlopen SkyLight for HDR control");
        }
    });
    return handle;
}

- (BOOL)displaySupportsHDR:(CGDirectDisplayID)displayID {
    SLHDRQueryFn fn = (SLHDRQueryFn)dlsym(VDMSkyLightHandle(), "SLSDisplaySupportsHDRMode");
    return fn ? (fn(displayID) ? YES : NO) : NO;
}

- (BOOL)isHDREnabledForDisplay:(CGDirectDisplayID)displayID {
    SLHDRQueryFn fn = (SLHDRQueryFn)dlsym(VDMSkyLightHandle(), "SLSDisplayIsHDRModeEnabled");
    return fn ? (fn(displayID) ? YES : NO) : NO;
}

- (BOOL)setHDREnabled:(BOOL)enabled forDisplay:(CGDirectDisplayID)displayID {
    SLHDRSetFn fn = (SLHDRSetFn)dlsym(VDMSkyLightHandle(), "SLSDisplaySetHDRModeEnabled");
    if (!fn) {
        NSLog(@"VDM: ERROR - SLSDisplaySetHDRModeEnabled unavailable");
        return NO;
    }
    int rc = fn(displayID, enabled ? true : false);
    NSLog(@"VDM: setHDREnabled(%d) for display %u -> rc=%d", enabled, displayID, rc);
    return rc == 0;
}

@end
