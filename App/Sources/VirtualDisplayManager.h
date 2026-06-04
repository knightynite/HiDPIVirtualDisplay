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

/// Mirror a virtual display to a physical display, pinning the physical target
/// to a native-resolution mode at the requested refresh rate. This prevents
/// macOS from leaving the physical panel in a variable-refresh (Adaptive Sync)
/// scanout mode, which causes hardware-cursor glitches and effective refresh
/// rate downgrades when mirroring from a virtual source.
/// @param sourceDisplayID The virtual display ID (mirror source)
/// @param targetDisplayID The physical display ID (mirror target)
/// @param refreshRate Refresh rate in Hz to pin the physical target to
/// @return YES if successful
- (BOOL)mirrorDisplay:(CGDirectDisplayID)sourceDisplayID
            toDisplay:(CGDirectDisplayID)targetDisplayID
               atRate:(double)refreshRate;

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

/// Read the chromaticity primaries from a physical display's EDID via IOKit.
/// Returns YES if successful, filling in the out parameters with CIE xy values.
/// When mirroring, the virtual display should use these exact primaries to avoid
/// expensive ColorSync color transforms on every frame.
- (BOOL)getChromaticityForDisplay:(CGDirectDisplayID)displayID
                          redX:(CGFloat *)redX redY:(CGFloat *)redY
                        greenX:(CGFloat *)greenX greenY:(CGFloat *)greenY
                         blueX:(CGFloat *)blueX blueY:(CGFloat *)blueY
                        whiteX:(CGFloat *)whiteX whiteY:(CGFloat *)whiteY;

/// Create a virtual display matching a target physical display's color profile.
/// Reads the target display's EDID primaries and uses them for the virtual display
/// so ColorSync can use an identity transform (no per-frame color conversion).
- (CGDirectDisplayID)createVirtualDisplayWithWidth:(unsigned int)width
                                            height:(unsigned int)height
                                               ppi:(unsigned int)ppi
                                             hiDPI:(BOOL)hiDPI
                                              name:(NSString *)name
                                       refreshRate:(double)refreshRate
                              matchingDisplay:(CGDirectDisplayID)targetDisplayID;

#pragma mark - HDR control (Beta)

/// Whether a physical display advertises HDR capability.
/// Apply HDR to the PHYSICAL mirror target, not the virtual display — the
/// virtual display reports no HDR support.
- (BOOL)displaySupportsHDR:(CGDirectDisplayID)displayID;

/// Whether HDR mode is currently enabled on a physical display.
- (BOOL)isHDREnabledForDisplay:(CGDirectDisplayID)displayID;

/// Enable or disable HDR mode on a physical display via the SkyLight path,
/// which keeps the System Settings "High Dynamic Range" checkbox in sync.
/// Returns YES on success.
- (BOOL)setHDREnabled:(BOOL)enabled forDisplay:(CGDirectDisplayID)displayID;

@end

NS_ASSUME_NONNULL_END
