// VirtualDisplayManager.m
// Implementation of virtual display creation using private CoreGraphics APIs

#import "VirtualDisplayManager.h"
#import "CGVirtualDisplayPrivate.h"

@interface VirtualDisplayManager ()
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, id> *virtualDisplays;
@end

@implementation VirtualDisplayManager

+ (instancetype)sharedManager {
    static VirtualDisplayManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[VirtualDisplayManager alloc] init];
    });
    return sharedManager;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _virtualDisplays = [NSMutableDictionary dictionary];
    }
    return self;
}

- (CGDirectDisplayID)createVirtualDisplayWithWidth:(unsigned int)width
                                            height:(unsigned int)height
                                               ppi:(unsigned int)ppi
                                             hiDPI:(BOOL)hiDPI
                                              name:(NSString *)name
                                       refreshRate:(double)refreshRate {

    NSLog(@"Creating virtual display: %ux%u @ %u PPI, HiDPI: %@, Refresh: %.0fHz",
          width, height, ppi, hiDPI ? @"YES" : @"NO", refreshRate);

    // Create settings
    CGVirtualDisplaySettings *settings = [[CGVirtualDisplaySettings alloc] init];
    settings.hiDPI = hiDPI ? 1 : 0;

    // Create descriptor
    CGVirtualDisplayDescriptor *descriptor = [[CGVirtualDisplayDescriptor alloc] init];
    descriptor.queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
    descriptor.name = name;

    // Standard Apple display color profile (P3-ish)
    descriptor.whitePoint = CGPointMake(0.3125, 0.3291);
    descriptor.redPrimary = CGPointMake(0.6797, 0.3203);
    descriptor.greenPrimary = CGPointMake(0.2100, 0.7100);
    descriptor.bluePrimary = CGPointMake(0.1500, 0.0600);

    // Calculate physical size in millimeters from pixels and PPI
    float widthInInches = (float)width / (float)ppi;
    float heightInInches = (float)height / (float)ppi;
    descriptor.sizeInMillimeters = CGSizeMake(widthInInches * 25.4f, heightInInches * 25.4f);

    NSLog(@"Physical size: %.1f x %.1f mm",
          descriptor.sizeInMillimeters.width,
          descriptor.sizeInMillimeters.height);

    // Set maximum pixel dimensions (framebuffer size)
    descriptor.maxPixelsWide = width;
    descriptor.maxPixelsHigh = height;

    // Vendor/Product/Serial - can be customized
    descriptor.vendorID = 0x1234;  // Custom vendor
    descriptor.productID = 0x5678; // Custom product
    descriptor.serialNum = 1;

    // Termination handler
    descriptor.terminationHandler = ^(id display, id reason) {
        NSLog(@"Virtual display terminated: %@", reason);
    };

    // Calculate mode dimensions
    // For HiDPI, the mode width/height represent the "looks like" logical resolution
    // The framebuffer is 2x this in each dimension
    unsigned int modeWidth = hiDPI ? width / 2 : width;
    unsigned int modeHeight = hiDPI ? height / 2 : height;

    NSLog(@"Mode resolution: %ux%u (logical), Framebuffer: %ux%u",
          modeWidth, modeHeight, width, height);

    // Create the display mode
    CGVirtualDisplayMode *mode = [[CGVirtualDisplayMode alloc] initWithWidth:modeWidth
                                                                      height:modeHeight
                                                                 refreshRate:refreshRate];
    // Add 60 Hz fallback mode for better compatibility
    NSMutableArray *modes = [NSMutableArray arrayWithObject:mode];
    if (refreshRate != 60.0) {
        CGVirtualDisplayMode *fallbackMode = [[CGVirtualDisplayMode alloc] initWithWidth:modeWidth
                                                                                  height:modeHeight
                                                                             refreshRate:60.0];
        if (fallbackMode) {
            [modes addObject:fallbackMode];
        }
    }
    settings.modes = modes;

    // Create the virtual display
    CGVirtualDisplay *display = [[CGVirtualDisplay alloc] initWithDescriptor:descriptor];
    if (!display) {
        NSLog(@"Failed to create virtual display");
        return kCGNullDirectDisplay;
    }

    // Apply settings
    if (![display applySettings:settings]) {
        NSLog(@"Failed to apply settings to virtual display");
        return kCGNullDirectDisplay;
    }

    CGDirectDisplayID displayID = display.displayID;
    NSLog(@"Created virtual display with ID: %u", displayID);

    // Store reference to keep it alive
    self.virtualDisplays[@(displayID)] = display;

    return displayID;
}

- (CGDirectDisplayID)createG9VirtualDisplayWithScaledWidth:(unsigned int)scaledWidth
                                              scaledHeight:(unsigned int)scaledHeight {
    // Samsung G9 57" specs:
    // - Physical: 1419.5mm x 406.4mm (approximately)
    // - Native: 7680x2160
    // - PPI: ~140

    // For HiDPI, framebuffer = 2x the "looks like" resolution
    unsigned int framebufferWidth = scaledWidth * 2;
    unsigned int framebufferHeight = scaledHeight * 2;

    NSLog(@"G9 Virtual Display: 'Looks like' %ux%u, Framebuffer: %ux%u",
          scaledWidth, scaledHeight, framebufferWidth, framebufferHeight);

    // G9 57" is approximately 140 PPI at native resolution
    // But we set PPI based on the virtual framebuffer to get correct physical size appearance
    unsigned int effectivePPI = 140;

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
                        NSLog(@"Detected external monitor refresh rate: %.0f Hz", rate);
                        break;
                    }
                }
            }
        }
    }
    NSLog(@"G9 convenience method using refresh rate: %.1f Hz", refreshRate);

    return [self createVirtualDisplayWithWidth:framebufferWidth
                                        height:framebufferHeight
                                           ppi:effectivePPI
                                         hiDPI:YES
                                          name:@"G9 HiDPI Virtual"
                                   refreshRate:refreshRate];
}

- (BOOL)mirrorDisplay:(CGDirectDisplayID)sourceDisplayID
            toDisplay:(CGDirectDisplayID)targetDisplayID {

    NSLog(@"Setting up mirror: %u -> %u", sourceDisplayID, targetDisplayID);

    CGDisplayConfigRef configRef;
    CGError err = CGBeginDisplayConfiguration(&configRef);
    if (err != kCGErrorSuccess) {
        NSLog(@"Failed to begin display configuration: %d", err);
        return NO;
    }

    // Set target to mirror source
    err = CGConfigureDisplayMirrorOfDisplay(configRef, targetDisplayID, sourceDisplayID);
    if (err != kCGErrorSuccess) {
        NSLog(@"Failed to configure mirror: %d", err);
        CGCancelDisplayConfiguration(configRef);
        return NO;
    }

    // Apply the configuration
    err = CGCompleteDisplayConfiguration(configRef, kCGConfigurePermanently);
    if (err != kCGErrorSuccess) {
        NSLog(@"Failed to complete display configuration: %d", err);
        return NO;
    }

    NSLog(@"Mirror configuration applied successfully");
    return YES;
}

- (BOOL)stopMirroringForDisplay:(CGDirectDisplayID)displayID {
    NSLog(@"Stopping mirror for display: %u", displayID);

    CGDisplayConfigRef configRef;
    CGError err = CGBeginDisplayConfiguration(&configRef);
    if (err != kCGErrorSuccess) {
        NSLog(@"Failed to begin display configuration: %d", err);
        return NO;
    }

    // Pass kCGNullDirectDisplay to stop mirroring
    err = CGConfigureDisplayMirrorOfDisplay(configRef, displayID, kCGNullDirectDisplay);
    if (err != kCGErrorSuccess) {
        NSLog(@"Failed to stop mirror: %d", err);
        CGCancelDisplayConfiguration(configRef);
        return NO;
    }

    err = CGCompleteDisplayConfiguration(configRef, kCGConfigurePermanently);
    if (err != kCGErrorSuccess) {
        NSLog(@"Failed to complete display configuration: %d", err);
        return NO;
    }

    NSLog(@"Mirror stopped successfully");
    return YES;
}

- (void)destroyVirtualDisplay:(CGDirectDisplayID)displayID {
    NSLog(@"Destroying virtual display: %u", displayID);
    [self.virtualDisplays removeObjectForKey:@(displayID)];
}

- (void)destroyAllVirtualDisplays {
    NSLog(@"Destroying all virtual displays (%lu total)",
          (unsigned long)self.virtualDisplays.count);
    [self.virtualDisplays removeAllObjects];
}

- (NSArray<NSDictionary *> *)listAllDisplays {
    NSMutableArray *displays = [NSMutableArray array];

    CGDirectDisplayID displayList[32];
    uint32_t displayCount;

    CGError err = CGGetOnlineDisplayList(32, displayList, &displayCount);
    if (err != kCGErrorSuccess) {
        NSLog(@"Failed to get display list: %d", err);
        return displays;
    }

    for (uint32_t i = 0; i < displayCount; i++) {
        CGDirectDisplayID displayID = displayList[i];

        CGDisplayModeRef mode = CGDisplayCopyDisplayMode(displayID);
        size_t width = CGDisplayModeGetWidth(mode);
        size_t height = CGDisplayModeGetHeight(mode);
        double refreshRate = CGDisplayModeGetRefreshRate(mode);
        CGDisplayModeRelease(mode);

        CGSize physicalSize = CGDisplayScreenSize(displayID);
        BOOL isMain = CGDisplayIsMain(displayID);
        BOOL isBuiltin = CGDisplayIsBuiltin(displayID);
        CGDirectDisplayID mirrorOf = CGDisplayMirrorsDisplay(displayID);
        BOOL isVirtual = [self isVirtualDisplay:displayID];

        [displays addObject:@{
            @"id": @(displayID),
            @"width": @(width),
            @"height": @(height),
            @"refreshRate": @(refreshRate),
            @"physicalWidth": @(physicalSize.width),
            @"physicalHeight": @(physicalSize.height),
            @"isMain": @(isMain),
            @"isBuiltin": @(isBuiltin),
            @"mirrorOf": @(mirrorOf),
            @"isVirtual": @(isVirtual)
        }];
    }

    return displays;
}

- (CGDirectDisplayID)mainDisplayID {
    return CGMainDisplayID();
}

- (BOOL)isVirtualDisplay:(CGDirectDisplayID)displayID {
    return self.virtualDisplays[@(displayID)] != nil;
}

@end
