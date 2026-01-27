// VirtualDisplayManager.h
// Manages creation and lifecycle of virtual displays

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

@interface VirtualDisplayManager : NSObject

/// Shared instance
+ (instancetype)sharedManager;

/// Currently active virtual display ID (or kCGNullDirectDisplay if none)
@property (nonatomic, readonly) CGDirectDisplayID currentDisplayID;

/// Create a virtual display with specified parameters
/// @param width Width in pixels
/// @param height Height in pixels
/// @param ppi Pixels per inch (affects physical size calculation)
/// @param hiDPI Whether to enable HiDPI mode
/// @param name Display name
/// @param refreshRate Refresh rate in Hz (default 60)
/// @return The CGDirectDisplayID of the created display, or kCGNullDirectDisplay on failure
- (CGDirectDisplayID)createVirtualDisplayWithWidth:(unsigned int)width
                                            height:(unsigned int)height
                                               ppi:(unsigned int)ppi
                                             hiDPI:(BOOL)hiDPI
                                              name:(NSString *)name
                                       refreshRate:(double)refreshRate;

/// Create a preset virtual display for Samsung G9 57" (7680x2160)
/// @param scaledResolution The "looks like" resolution (e.g., 3840x1080, 5120x1440)
/// @return The CGDirectDisplayID of the created display
- (CGDirectDisplayID)createG9VirtualDisplayWithScaledWidth:(unsigned int)scaledWidth
                                              scaledHeight:(unsigned int)scaledHeight;

/// Mirror a virtual display to a physical display
/// @param sourceDisplayID The virtual display ID (mirror source)
/// @param targetDisplayID The physical display ID (mirror target)
/// @return YES if successful
- (BOOL)mirrorDisplay:(CGDirectDisplayID)sourceDisplayID
            toDisplay:(CGDirectDisplayID)targetDisplayID;

/// Stop mirroring for a display
/// @param displayID The display to stop mirroring
/// @return YES if successful
- (BOOL)stopMirroringForDisplay:(CGDirectDisplayID)displayID;

/// Destroy a virtual display
/// @param displayID The display ID to destroy
- (void)destroyVirtualDisplay:(CGDirectDisplayID)displayID;

/// Destroy all virtual displays created by this manager
- (void)destroyAllVirtualDisplays;

/// Reset all display mirroring configurations
/// This stops mirroring on all non-builtin displays
- (void)resetAllMirroring;

/// List all active displays
- (NSArray<NSDictionary *> *)listAllDisplays;

/// Get the display ID of the main display
- (CGDirectDisplayID)mainDisplayID;

/// Check if a display is virtual
- (BOOL)isVirtualDisplay:(CGDirectDisplayID)displayID;

@end

NS_ASSUME_NONNULL_END
