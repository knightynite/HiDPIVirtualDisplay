// VirtualDisplayManager.m
// Implementation of virtual display creation using private CoreGraphics APIs
// Compiled with -fno-objc-arc - uses manual retain/release

#import "VirtualDisplayManager.h"
#import "CGVirtualDisplayPrivate.h"
#import <AppKit/AppKit.h>
#import <objc/runtime.h>

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

        // Periodically scan for new windows (catches any created without notifications)
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSTimer scheduledTimerWithTimeInterval:2.0
                                            repeats:YES
                                              block:^(NSTimer *timer) {
                for (NSWindow *window in [NSApp windows]) {
                    retainWindowIfNeeded(window);
                }
            }];
        });

        NSLog(@"VDM: Manager initialized");
    }
    return self;
}

- (CGDirectDisplayID)currentDisplayID {
    return _currentDisplayID;
}

- (CGDirectDisplayID)createVirtualDisplayWithWidth:(unsigned int)width
                                            height:(unsigned int)height
                                               ppi:(unsigned int)ppi
                                             hiDPI:(BOOL)hiDPI
                                              name:(NSString *)name
                                       refreshRate:(double)refreshRate {

    NSLog(@"VDM: ========== CREATE START ==========");
    NSLog(@"VDM: %ux%u @ %u PPI, HiDPI=%@", width, height, ppi, hiDPI ? @"YES" : @"NO");

    @try {
        // Create settings and retain
        CGVirtualDisplaySettings *settings = [[CGVirtualDisplaySettings alloc] init];
        [settings retain];
        settings.hiDPI = hiDPI ? 1 : 0;
        _settings = settings;

        // Create descriptor and retain
        CGVirtualDisplayDescriptor *descriptor = [[CGVirtualDisplayDescriptor alloc] init];
        [descriptor retain];
        descriptor.queue = dispatch_get_main_queue();

        _displayName = [[name copy] retain];
        descriptor.name = _displayName;

        descriptor.whitePoint = CGPointMake(0.3125, 0.3291);
        descriptor.redPrimary = CGPointMake(0.6797, 0.3203);
        descriptor.greenPrimary = CGPointMake(0.2100, 0.7100);
        descriptor.bluePrimary = CGPointMake(0.1500, 0.0600);

        float widthInInches = (float)width / (float)ppi;
        float heightInInches = (float)height / (float)ppi;
        descriptor.sizeInMillimeters = CGSizeMake(widthInInches * 25.4f, heightInInches * 25.4f);

        descriptor.maxPixelsWide = width;
        descriptor.maxPixelsHigh = height;
        descriptor.vendorID = 0x1234;
        descriptor.productID = 0x5678;
        descriptor.serialNum = arc4random();
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

        _modesArray = [@[_mode] retain];
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

- (CGDirectDisplayID)createG9VirtualDisplayWithScaledWidth:(unsigned int)scaledWidth
                                              scaledHeight:(unsigned int)scaledHeight {
    return [self createVirtualDisplayWithWidth:scaledWidth * 2
                                        height:scaledHeight * 2
                                           ppi:140
                                         hiDPI:YES
                                          name:@"G9 HiDPI Virtual"
                                   refreshRate:60.0];
}

- (BOOL)mirrorDisplay:(CGDirectDisplayID)sourceDisplayID
            toDisplay:(CGDirectDisplayID)targetDisplayID {

    NSLog(@"VDM: Mirror %u -> %u", sourceDisplayID, targetDisplayID);

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

    err = CGCompleteDisplayConfiguration(configRef, kCGConfigurePermanently);
    if (err != kCGErrorSuccess) {
        NSLog(@"VDM: ERROR - Complete config failed: %d", err);
        return NO;
    }

    NSLog(@"VDM: Mirror success");
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

    err = CGCompleteDisplayConfiguration(configRef, kCGConfigurePermanently);
    if (err != kCGErrorSuccess) return NO;

    NSLog(@"VDM: Stop mirror success");
    return YES;
}

- (void)destroyVirtualDisplay:(CGDirectDisplayID)displayID {
    NSLog(@"VDM: destroyVirtualDisplay called for %u (NO-OP)", displayID);
    if (displayID == _currentDisplayID) {
        _currentDisplayID = kCGNullDirectDisplay;
    }
}

- (void)destroyAllVirtualDisplays {
    NSLog(@"VDM: destroyAllVirtualDisplays called (NO-OP)");
    _currentDisplayID = kCGNullDirectDisplay;
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

@end
