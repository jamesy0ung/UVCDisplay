//
//  UVCBridge.mm
//  UVCDisplay
//

#import "UVCBridge.h"
#import "IOKitShim.h"
#import <libuvc/libuvc.h>
#import <stdatomic.h>

static const uint32_t kMS2130VID = 0x345F;
static const uint32_t kMS2130PID = 0x2130;

typedef struct { int width; int height; int fps; } UVCMode;
static const UVCMode kModes[] = {
    {1920, 1080, 60},
    {1920, 1080, 30},
    {1280,  720, 60},
    {1280,  720, 30},
};
static const int kModeCount    = (int)(sizeof(kModes) / sizeof(kModes[0]));
static const int kTargetFrames = 300;

@implementation UVCBridge {
    uvc_context_t       *_ctx;
    uvc_device_t        *_dev;
    uvc_device_handle_t *_devh;
    uvc_stream_ctrl_t    _ctrl;
    _Atomic int          _frameCount;
    BOOL                 _streaming;
}

#pragma mark - Logging

- (void)log:(NSString *)line {
    NSLog(@"[UVCBridge] %@", line);
    void (^handler)(NSString *) = self.logHandler;
    if (handler) {
        handler(line);
    }
}

- (void)logFormat:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2) {
    va_list args;
    va_start(args, format);
    NSString *line = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    [self log:line];
}

#pragma mark - CF property helpers

- (BOOL)readNumberProperty:(const char *)key
                    ofEntry:(io_registry_entry_t)entry
                       into:(long long *)out {
    CFStringRef cfKey = CFStringCreateWithCString(kCFAllocatorDefault, key,
                                                  kCFStringEncodingUTF8);
    if (!cfKey) return NO;
    CFTypeRef value = IORegistryEntryCreateCFProperty(entry, cfKey,
                                                      kCFAllocatorDefault, 0);
    CFRelease(cfKey);

    BOOL ok = NO;
    if (value && CFGetTypeID(value) == CFNumberGetTypeID()) {
        long long n = 0;
        if (CFNumberGetValue((CFNumberRef)value, kCFNumberLongLongType, &n)) {
            if (out) *out = n;
            ok = YES;
        }
    }
    if (value) CFRelease(value);
    return ok;
}

- (nullable NSString *)readStringProperty:(const char *)key
                                  ofEntry:(io_registry_entry_t)entry {
    CFStringRef cfKey = CFStringCreateWithCString(kCFAllocatorDefault, key,
                                                  kCFStringEncodingUTF8);
    if (!cfKey) return nil;
    CFTypeRef value = IORegistryEntryCreateCFProperty(entry, cfKey,
                                                      kCFAllocatorDefault, 0);
    CFRelease(cfKey);

    NSString *result = nil;
    if (value && CFGetTypeID(value) == CFStringGetTypeID()) {
        result = [(__bridge NSString *)value copy];
    }
    if (value) CFRelease(value);
    return result;
}

#pragma mark - Public API

- (void)scan {
    [self log:@"=== IOKit inventory probe (read-only) ==="];

    CFMutableDictionaryRef matching = IOServiceMatching("IOUSBHostDevice");
    if (!matching) {
        [self log:@"ERROR: IOServiceMatching(\"IOUSBHostDevice\") returned NULL"];
        return;
    }

    // IOServiceGetMatchingServices consumes a reference on `matching`.
    io_iterator_t iter = 0;
    kern_return_t kr = IOServiceGetMatchingServices(kIOMainPortDefault,
                                                    matching, &iter);
    if (kr != KERN_SUCCESS) {
        [self logFormat:@"ERROR: IOServiceGetMatchingServices kr=0x%08x", kr];
        return;
    }

    int deviceCount = 0;
    io_service_t device = 0;
    while ((device = IOIteratorNext(iter))) {
        deviceCount++;
        [self reportDevice:device index:deviceCount];
        IOObjectRelease(device);
    }
    IOObjectRelease(iter);

    if (deviceCount == 0) {
        [self log:@"No IOUSBHostDevice services found."];
        [self log:@"(If ioreg sees the device, suspect sandbox / entitlements / matching.)"];
    }
    [self logFormat:@"=== Probe complete: %d IOUSBHostDevice(s) ===", deviceCount];
}

#pragma mark - Device reporting

- (void)reportDevice:(io_service_t)device index:(int)index {
    // Registry entry ID
    uint64_t entryID = 0;
    IORegistryEntryGetRegistryEntryID(device, &entryID);

    // Class name
    io_name_t className = {0};
    IOObjectGetClass(device, className);

    // Registry path (IOService plane)
    io_string_t path = {0};
    IORegistryEntryGetPath(device, kIOServicePlane, path);

    long long vid = -1, pid = -1, locationID = -1, speed = -1;
    [self readNumberProperty:"idVendor" ofEntry:device into:&vid];
    [self readNumberProperty:"idProduct" ofEntry:device into:&pid];
    [self readNumberProperty:"locationID" ofEntry:device into:&locationID];
    [self readNumberProperty:"Device Speed" ofEntry:device into:&speed];

    NSString *name = [self readStringProperty:"USB Product Name" ofEntry:device];
    if (!name) name = [self readStringProperty:"kUSBProductString" ofEntry:device];
    NSString *serial = [self readStringProperty:"USB Serial Number" ofEntry:device];
    if (!serial) serial = [self readStringProperty:"kUSBSerialNumberString" ofEntry:device];

    [self log:@"----------------------------------------"];
    [self logFormat:@"Device #%d", index];
    [self logFormat:@"  entryID  = 0x%llx", entryID];
    [self logFormat:@"  class    = %s", className];
    [self logFormat:@"  path     = %s", path];
    [self logFormat:@"  VID      = %@", vid  >= 0 ? [NSString stringWithFormat:@"0x%04llX", vid]  : @"?"];
    [self logFormat:@"  PID      = %@", pid  >= 0 ? [NSString stringWithFormat:@"0x%04llX", pid]  : @"?"];
    [self logFormat:@"  Name     = %@", name ?: @"?"];
    [self logFormat:@"  Location = %@", locationID >= 0 ? [NSString stringWithFormat:@"0x%llx", locationID] : @"?"];
    [self logFormat:@"  Speed    = %@", speed >= 0 ? @(speed).stringValue : @"?"];
    [self logFormat:@"  Serial   = %@", serial ?: @"?"];

    BOOL isTarget = (vid == (long long)kMS2130VID && pid == (long long)kMS2130PID);

    if (isTarget) {
        [self logFormat:@"  >> MATCH %04X:%04X: dumping full properties + interfaces",
                        kMS2130VID, kMS2130PID];
        [self dumpAllProperties:device];
        [self log:@"  Interfaces:"];
        [self recurseInterfacesOf:device depth:1];
    }
}

- (void)dumpAllProperties:(io_registry_entry_t)entry {
    CFMutableDictionaryRef props = NULL;
    kern_return_t kr = IORegistryEntryCreateCFProperties(entry, &props,
                                                         kCFAllocatorDefault, 0);
    if (kr != KERN_SUCCESS || !props) {
        [self logFormat:@"  (could not read full property dict, kr=0x%08x)", kr];
        if (props) CFRelease(props);
        return;
    }
    NSDictionary *dict = (__bridge NSDictionary *)props;
    [self log:@"  --- full property dictionary ---"];
    for (id key in [dict.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        [self logFormat:@"    %@ = %@", key, dict[key]];
    }
    [self log:@"  --- end property dictionary ---"];
    CFRelease(props);
}

- (void)recurseInterfacesOf:(io_registry_entry_t)entry depth:(int)depth {
    io_iterator_t children = 0;
    kern_return_t kr = IORegistryEntryGetChildIterator(entry, kIOServicePlane,
                                                       &children);
    if (kr != KERN_SUCCESS) {
        [self logFormat:@"    (child iterator failed, kr=0x%08x)", kr];
        return;
    }

    io_object_t child = 0;
    while ((child = IOIteratorNext(children))) {
        io_name_t childClass = {0};
        IOObjectGetClass(child, childClass);

        long long ifaceNum = -1;
        BOOL hasIfaceNum = [self readNumberProperty:"bInterfaceNumber"
                                            ofEntry:child into:&ifaceNum];
        BOOL looksLikeInterface =
            hasIfaceNum || (strstr(childClass, "Interface") != NULL);

        if (looksLikeInterface) {
            long long cls = -1, sub = -1, proto = -1, alt = -1;
            [self readNumberProperty:"bInterfaceClass" ofEntry:child into:&cls];
            [self readNumberProperty:"bInterfaceSubClass" ofEntry:child into:&sub];
            [self readNumberProperty:"bInterfaceProtocol" ofEntry:child into:&proto];
            [self readNumberProperty:"bAlternateSetting" ofEntry:child into:&alt];

            [self logFormat:@"    Interface %@  (class %s)",
                            hasIfaceNum ? @(ifaceNum).stringValue : @"?", childClass];
            [self logFormat:@"      bInterfaceClass    = %@",
                            cls   >= 0 ? [NSString stringWithFormat:@"0x%02llX", cls]   : @"?"];
            [self logFormat:@"      bInterfaceSubClass = %@",
                            sub   >= 0 ? [NSString stringWithFormat:@"0x%02llX", sub]   : @"?"];
            [self logFormat:@"      bInterfaceProtocol = %@",
                            proto >= 0 ? [NSString stringWithFormat:@"0x%02llX", proto] : @"?"];
            [self logFormat:@"      bAlternateSetting  = %@",
                            alt   >= 0 ? @(alt).stringValue : @"?"];
        }

        [self recurseInterfacesOf:child depth:depth + 1];
        IOObjectRelease(child);
    }
    IOObjectRelease(children);
}

#pragma mark - Streaming (libuvc)

static void uvc_frame_callback(uvc_frame_t *frame, void *ptr) {
    UVCBridge *bridge = (__bridge UVCBridge *)ptr;
    [bridge handleFrame:frame];
}

- (void)handleFrame:(uvc_frame_t *)frame {
    int n = atomic_fetch_add(&_frameCount, 1) + 1;

    if (n == 1) {
        size_t expected = (size_t)frame->width * frame->height * 2; // YUY2 = 2 bytes/px
        const char *fmt =
            frame->frame_format == UVC_FRAME_FORMAT_YUYV ? "YUYV/YUY2" :
            frame->frame_format == UVC_FRAME_FORMAT_UYVY ? "UYVY" :
            frame->frame_format == UVC_FRAME_FORMAT_MJPEG ? "MJPEG" : "OTHER";
        [self logFormat:@"First frame: %ux%u, %zu bytes (expect %zu), fmt=%s(%d), seq=%u",
                        frame->width, frame->height, frame->data_bytes, expected,
                        fmt, (int)frame->frame_format, frame->sequence];
        if (frame->frame_format != UVC_FRAME_FORMAT_YUYV) {
            [self logFormat:@"WARNING: preview conversion expects YUY2"];
        } else if (frame->data_bytes != expected) {
            [self logFormat:@"WARNING: YUY2 byte count mismatch (padding/stride?)"];
        }
    }
    if (n % 60 == 0) {
        [self logFormat:@"…%d frames received", n];
    }
    if (n == kTargetFrames) {
        [self logFormat:@"SUCCESS: received %d valid frames", kTargetFrames];
    }

    void (^handler)(const void *, int, int, size_t) = self.frameHandler;
    if (handler) {
        handler(frame->data, (int)frame->width, (int)frame->height, frame->data_bytes);
    }
}

- (int)frameCount {
    return atomic_load(&_frameCount);
}

- (BOOL)startStreaming {
    if (_streaming) {
        [self log:@"Already streaming."];
        return YES;
    }
    atomic_store(&_frameCount, 0);
    [self log:@"=== Connecting (YUY2, prefer 1080p60) ==="];

    uvc_error_t res = uvc_init(&_ctx, NULL);
    if (res < 0) { [self logFormat:@"uvc_init failed: %s", uvc_strerror(res)]; return NO; }

    res = uvc_find_device(_ctx, &_dev, (int)kMS2130VID, (int)kMS2130PID, NULL);
    if (res < 0) {
        [self logFormat:@"uvc_find_device failed: %s (device connected?)", uvc_strerror(res)];
        [self teardown];
        return NO;
    }
    [self log:@"Device found."];

    res = uvc_open(_dev, &_devh);
    if (res < 0) {
        [self logFormat:@"uvc_open failed: %s (entitlements? interface claim?)",
                        uvc_strerror(res)];
        [self teardown];
        return NO;
    }
    [self log:@"Device opened; video interfaces claimed."];

    BOOL negotiated = NO;
    for (int i = 0; i < kModeCount; i++) {
        UVCMode m = kModes[i];
        res = uvc_get_stream_ctrl_format_size(_devh, &_ctrl, UVC_FRAME_FORMAT_YUYV,
                                              m.width, m.height, m.fps);
        if (res == UVC_SUCCESS) {
            [self logFormat:@"Negotiated %dx%d YUY2 @ %dfps", m.width, m.height, m.fps];
            negotiated = YES;
            break;
        }
        [self logFormat:@"  %dx%d@%d unavailable (%s)", m.width, m.height, m.fps,
                        uvc_strerror(res)];
    }
    if (!negotiated) {
        [self log:@"No supported YUY2 mode found."];
        [self teardown];
        return NO;
    }
    unsigned fps = _ctrl.dwFrameInterval ? (10000000u / _ctrl.dwFrameInterval) : 0;
    [self logFormat:@"ctrl: fmtIdx=%u frameIdx=%u ~%u fps maxFrame=%u maxPayload=%u",
                    _ctrl.bFormatIndex, _ctrl.bFrameIndex, fps,
                    _ctrl.dwMaxVideoFrameSize, _ctrl.dwMaxPayloadTransferSize];

    res = uvc_start_streaming(_devh, &_ctrl, uvc_frame_callback,
                              (__bridge void *)self, 0);
    if (res < 0) {
        [self logFormat:@"uvc_start_streaming failed: %s", uvc_strerror(res)];
        [self teardown];
        return NO;
    }
    _streaming = YES;
    [self log:@"Streaming started."];
    return YES;
}

- (void)stopStreaming {
    if (!_streaming && !_ctx) {
        [self log:@"Not streaming."];
        return;
    }
    if (_streaming && _devh) {
        uvc_stop_streaming(_devh);
        [self logFormat:@"Streaming stopped after %d frames.", atomic_load(&_frameCount)];
    }
    _streaming = NO;
    [self teardown];
}

- (void)teardown {
    if (_devh) { uvc_close(_devh); _devh = NULL; }
    if (_dev)  { uvc_unref_device(_dev); _dev = NULL; }
    if (_ctx)  { uvc_exit(_ctx); _ctx = NULL; }
}

@end
