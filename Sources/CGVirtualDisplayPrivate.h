// CGVirtualDisplayPrivate.h
// Private CoreGraphics APIs for virtual display creation
// Based on class-dump headers from macOS
// Use at your own risk - these are undocumented APIs

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

// MARK: - CGVirtualDisplayMode

@interface CGVirtualDisplayMode : NSObject

@property (readonly, nonatomic) unsigned int width;
@property (readonly, nonatomic) unsigned int height;
@property (readonly, nonatomic) double refreshRate;

- (instancetype)initWithWidth:(unsigned int)width
                       height:(unsigned int)height
                  refreshRate:(double)refreshRate;

@end

// MARK: - CGVirtualDisplaySettings

@interface CGVirtualDisplaySettings : NSObject

@property (nonatomic) unsigned int hiDPI;
@property (nonatomic, retain) NSArray<CGVirtualDisplayMode *> *modes;

- (instancetype)init;

@end

// MARK: - CGVirtualDisplayDescriptor

@interface CGVirtualDisplayDescriptor : NSObject

@property (nonatomic) unsigned int vendorID;
@property (nonatomic) unsigned int productID;
@property (nonatomic) unsigned int serialNum;
@property (nonatomic, retain) NSString *name;
@property (nonatomic) CGSize sizeInMillimeters;
@property (nonatomic) unsigned int maxPixelsWide;
@property (nonatomic) unsigned int maxPixelsHigh;
@property (nonatomic) CGPoint redPrimary;
@property (nonatomic) CGPoint greenPrimary;
@property (nonatomic) CGPoint bluePrimary;
@property (nonatomic) CGPoint whitePoint;
@property (nonatomic, retain) dispatch_queue_t queue;
@property (nonatomic, copy, nullable) void (^terminationHandler)(id, id);

- (instancetype)init;

@end

// MARK: - CGVirtualDisplay

@interface CGVirtualDisplay : NSObject

@property (readonly, nonatomic) unsigned int displayID;
@property (readonly, nonatomic) unsigned int hiDPI;
@property (readonly, nonatomic) NSArray<CGVirtualDisplayMode *> *modes;

- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;

@end

NS_ASSUME_NONNULL_END
