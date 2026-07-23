//
//  UVCBridge.h
//  UVCDisplay
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface UVCBridge : NSObject

/// Receives diagnostic output on an arbitrary thread.
@property (nonatomic, copy, nullable) void (^logHandler)(NSString *line);

/// Receives YUY2 data on the libuvc callback thread.
/// The data pointer is valid only during the callback.
@property (nonatomic, copy, nullable) void (^frameHandler)(const void *data,
                                                           int width,
                                                           int height,
                                                           size_t length);

/// Prints the IOKit USB inventory.
- (void)scan;

/// Opens the MS2130 and starts a YUY2 stream.
- (BOOL)startStreaming;

/// Stops streaming and releases USB resources.
- (void)stopStreaming;

/// Frames received since the last call to startStreaming.
@property (nonatomic, readonly) int frameCount;

@end

NS_ASSUME_NONNULL_END
