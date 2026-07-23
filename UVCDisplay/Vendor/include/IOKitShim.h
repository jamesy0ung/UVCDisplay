//
//  IOKitShim.h
//  UVCDisplay
//
//  IOKit declarations missing from the iOS SDK.
//

#ifndef IOKitShim_h
#define IOKitShim_h

#include <mach/mach.h>
#include <CoreFoundation/CoreFoundation.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef mach_port_t     io_object_t;
typedef io_object_t     io_iterator_t;
typedef io_object_t     io_service_t;
typedef io_object_t     io_registry_entry_t;

typedef char            io_name_t[128];
typedef char            io_string_t[512];

typedef uint32_t        IOOptionBits;

#define kIOMainPortDefault  ((mach_port_t)0)

#define kIOServicePlane     "IOService"
#define kIOUSBPlane         "IOUSB"

CFMutableDictionaryRef IOServiceMatching(const char *name);

kern_return_t IOServiceGetMatchingServices(mach_port_t mainPort,
                                           CFDictionaryRef matching,
                                           io_iterator_t *existing);

io_object_t   IOIteratorNext(io_iterator_t iterator);

kern_return_t IOObjectRelease(io_object_t object);

kern_return_t IOObjectGetClass(io_object_t object, io_name_t className);

CFTypeRef     IORegistryEntryCreateCFProperty(io_registry_entry_t entry,
                                              CFStringRef key,
                                              CFAllocatorRef allocator,
                                              IOOptionBits options);

kern_return_t IORegistryEntryCreateCFProperties(io_registry_entry_t entry,
                                                CFMutableDictionaryRef *properties,
                                                CFAllocatorRef allocator,
                                                IOOptionBits options);

kern_return_t IORegistryEntryGetRegistryEntryID(io_registry_entry_t entry,
                                                uint64_t *entryID);

kern_return_t IORegistryEntryGetPath(io_registry_entry_t entry,
                                     const io_name_t plane,
                                     io_string_t path);

kern_return_t IORegistryEntryGetChildIterator(io_registry_entry_t entry,
                                              const io_name_t plane,
                                              io_iterator_t *iterator);

kern_return_t IORegistryEntryGetName(io_registry_entry_t entry, io_name_t name);

#ifdef __cplusplus
}
#endif

#endif /* IOKitShim_h */
