// VirtualDisplayManager.m
// Implementation of virtual display creation using private CoreGraphics APIs

#import "VirtualDisplayManager.h"
#import "CGVirtualDisplayPrivate.h"

@interface VirtualDisplayManager ()
// Store just one virtual display at a time
@property (nonatomic, strong) CGVirtualDisplay *currentDisplay;
@property (nonatomic, assign) CGDirectDisplayID currentDisplayID;
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
        _currentDisplay = nil;
        _currentDisplayID = kCGNullDirectDisplay;
    }
    return self;
}

- (CGDirectDisplayID)createVirtualDisplayWithWidth:(unsigned int)width
                                            height:(unsigned int)height
                                               ppi:(unsigned int)ppi
                                             hiDPI:(BOOL)hiDPI
                                              name:(NSString *)name
                                       refreshRate:(double)refreshRate {

    NSLog(@"VDM: Creating virtual display: %ux%u @ %u PPI, HiDPI: %@, Refresh: %.0fHz",
          width, height, ppi, hiDPI ? @"YES" : @"NO", refreshRate);

    // Destroy any existing display first
    if (self.currentDisplay != nil) {
        NSLog(@"VDM: Destroying existing display %u before creating new one", self.currentDisplayID);
        self.currentDisplay = nil;
        self.currentDisplayID = kCGNullDirectDisplay;
        // Give system time to clean up
        [NSThread sleepForTimeInterval:0.5];
    }

    @try {
        // Create settings
        CGVirtualDisplaySettings *settings = [[CGVirtualDisplaySettings alloc] init];
        settings.hiDPI = hiDPI ? 1 : 0;

        // Create descriptor
        CGVirtualDisplayDescriptor *descriptor = [[CGVirtualDisplayDescriptor alloc] init];
        descriptor.queue = dispatch_get_main_queue();  // Use main queue for stability
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

        NSLog(@"VDM: Physical size: %.1f x %.1f mm",
              descriptor.sizeInMillimeters.width,
              descriptor.sizeInMillimeters.height);

        // Set maximum pixel dimensions (framebuffer size)
        descriptor.maxPixelsWide = width;
        descriptor.maxPixelsHigh = height;

        // Vendor/Product/Serial
        descriptor.vendorID = 0x1234;
        descriptor.productID = 0x5678;
        descriptor.serialNum = arc4random();  // Random serial for uniqueness

        // Termination handler (no weak reference since we're not using ARC)
        descriptor.terminationHandler = ^(id display, id reason) {
            NSLog(@"VDM: Virtual display terminated: %@", reason);
        };

        // Calculate mode dimensions
        unsigned int modeWidth = hiDPI ? width / 2 : width;
        unsigned int modeHeight = hiDPI ? height / 2 : height;

        NSLog(@"VDM: Mode resolution: %ux%u (logical), Framebuffer: %ux%u",
              modeWidth, modeHeight, width, height);

        // Create the display mode
        CGVirtualDisplayMode *mode = [[CGVirtualDisplayMode alloc] initWithWidth:modeWidth
                                                                          height:modeHeight
                                                                     refreshRate:refreshRate];
        if (!mode) {
            NSLog(@"VDM: Failed to create display mode");
            return kCGNullDirectDisplay;
        }
        settings.modes = @[mode];

        // Create the virtual display
        NSLog(@"VDM: Allocating CGVirtualDisplay...");
        CGVirtualDisplay *display = [[CGVirtualDisplay alloc] initWithDescriptor:descriptor];
        if (!display) {
            NSLog(@"VDM: Failed to create virtual display - initWithDescriptor returned nil");
            return kCGNullDirectDisplay;
        }
        NSLog(@"VDM: CGVirtualDisplay allocated");

        // Apply settings
        NSLog(@"VDM: Applying settings...");
        BOOL settingsApplied = [display applySettings:settings];
        if (!settingsApplied) {
            NSLog(@"VDM: Failed to apply settings to virtual display");
            return kCGNullDirectDisplay;
        }
        NSLog(@"VDM: Settings applied");

        // Get the display ID
        NSLog(@"VDM: Getting display ID...");
        CGDirectDisplayID displayID = display.displayID;
        NSLog(@"VDM: Display ID is: %u", displayID);

        if (displayID == 0 || displayID == kCGNullDirectDisplay) {
            NSLog(@"VDM: Invalid display ID returned");
            return kCGNullDirectDisplay;
        }

        // Store reference to keep it alive
        NSLog(@"VDM: Storing display reference...");
        self.currentDisplay = display;
        self.currentDisplayID = displayID;
        NSLog(@"VDM: Virtual display created successfully with ID: %u", displayID);

        return displayID;

    } @catch (NSException *exception) {
        NSLog(@"VDM: Exception creating virtual display: %@", exception);
        return kCGNullDirectDisplay;
    }
}

- (CGDirectDisplayID)createG9VirtualDisplayWithScaledWidth:(unsigned int)scaledWidth
                                              scaledHeight:(unsigned int)scaledHeight {
    // G9 57" preset - framebuffer = 2x the "looks like" resolution
    unsigned int framebufferWidth = scaledWidth * 2;
    unsigned int framebufferHeight = scaledHeight * 2;

    return [self createVirtualDisplayWithWidth:framebufferWidth
                                        height:framebufferHeight
                                           ppi:140
                                         hiDPI:YES
                                          name:@"G9 HiDPI Virtual"
                                   refreshRate:60.0];
}

- (BOOL)mirrorDisplay:(CGDirectDisplayID)sourceDisplayID
            toDisplay:(CGDirectDisplayID)targetDisplayID {

    NSLog(@"VDM: Setting up mirror: %u -> %u", sourceDisplayID, targetDisplayID);

    CGDisplayConfigRef configRef;
    CGError err = CGBeginDisplayConfiguration(&configRef);
    if (err != kCGErrorSuccess) {
        NSLog(@"VDM: Failed to begin display configuration: %d", err);
        return NO;
    }

    // Set target to mirror source
    err = CGConfigureDisplayMirrorOfDisplay(configRef, targetDisplayID, sourceDisplayID);
    if (err != kCGErrorSuccess) {
        NSLog(@"VDM: Failed to configure mirror: %d", err);
        CGCancelDisplayConfiguration(configRef);
        return NO;
    }

    // Apply the configuration
    err = CGCompleteDisplayConfiguration(configRef, kCGConfigurePermanently);
    if (err != kCGErrorSuccess) {
        NSLog(@"VDM: Failed to complete display configuration: %d", err);
        return NO;
    }

    NSLog(@"VDM: Mirror configuration applied successfully");
    return YES;
}

- (BOOL)stopMirroringForDisplay:(CGDirectDisplayID)displayID {
    NSLog(@"VDM: Stopping mirror for display: %u", displayID);

    CGDisplayConfigRef configRef;
    CGError err = CGBeginDisplayConfiguration(&configRef);
    if (err != kCGErrorSuccess) {
        NSLog(@"VDM: Failed to begin display configuration: %d", err);
        return NO;
    }

    // Pass kCGNullDirectDisplay to stop mirroring
    err = CGConfigureDisplayMirrorOfDisplay(configRef, displayID, kCGNullDirectDisplay);
    if (err != kCGErrorSuccess) {
        NSLog(@"VDM: Failed to stop mirror: %d", err);
        CGCancelDisplayConfiguration(configRef);
        return NO;
    }

    err = CGCompleteDisplayConfiguration(configRef, kCGConfigurePermanently);
    if (err != kCGErrorSuccess) {
        NSLog(@"VDM: Failed to complete display configuration: %d", err);
        return NO;
    }

    NSLog(@"VDM: Mirror stopped successfully");
    return YES;
}

- (void)destroyVirtualDisplay:(CGDirectDisplayID)displayID {
    NSLog(@"VDM: Destroying virtual display: %u (current: %u)", displayID, self.currentDisplayID);
    if (displayID == self.currentDisplayID) {
        self.currentDisplay = nil;
        self.currentDisplayID = kCGNullDirectDisplay;
        NSLog(@"VDM: Virtual display destroyed");
    } else {
        NSLog(@"VDM: Display ID mismatch, not destroying");
    }
}

- (void)destroyAllVirtualDisplays {
    NSLog(@"VDM: Destroying all virtual displays (current: %u)", self.currentDisplayID);
    self.currentDisplay = nil;
    self.currentDisplayID = kCGNullDirectDisplay;
    NSLog(@"VDM: All virtual displays destroyed");
}

- (void)resetAllMirroring {
    NSLog(@"VDM: Resetting all display mirroring...");

    CGDirectDisplayID displayList[32];
    uint32_t displayCount;

    CGError err = CGGetOnlineDisplayList(32, displayList, &displayCount);
    if (err != kCGErrorSuccess) {
        NSLog(@"VDM: Failed to get display list: %d", err);
        return;
    }

    // Find all displays that are currently mirroring something
    for (uint32_t i = 0; i < displayCount; i++) {
        CGDirectDisplayID displayID = displayList[i];
        CGDirectDisplayID mirrorOf = CGDisplayMirrorsDisplay(displayID);

        if (mirrorOf != kCGNullDirectDisplay) {
            NSLog(@"VDM: Display %u is mirroring %u, stopping...", displayID, mirrorOf);
            [self stopMirroringForDisplay:displayID];
        }
    }

    NSLog(@"VDM: All mirroring reset complete");
}

- (NSArray<NSDictionary *> *)listAllDisplays {
    NSMutableArray *displays = [NSMutableArray array];

    CGDirectDisplayID displayList[32];
    uint32_t displayCount;

    CGError err = CGGetOnlineDisplayList(32, displayList, &displayCount);
    if (err != kCGErrorSuccess) {
        NSLog(@"VDM: Failed to get display list: %d", err);
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
        BOOL isVirtual = (displayID == self.currentDisplayID);

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
    return displayID == self.currentDisplayID;
}

@end
