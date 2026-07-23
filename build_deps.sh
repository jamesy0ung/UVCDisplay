#!/bin/bash
#
# Cross-compile libusb and libuvc as static libraries for
# arm64 iOS, and vendor the macOS-only IOKit USB headers the libusb darwin
# backend needs (the iOS SDK ships core IOKit headers but not the USB ones).
#
# Outputs:
#   Vendor/include/IOKit/{IOCFPlugIn.h,IOCFBundle.h,usb/*.h}   (vendored headers)
#   Vendor/gen/config.h                                         (libusb config)
#   Vendor/gen/libuvc/libuvc_config.h                           (libuvc config)
#   Vendor/lib/libusb-1.0.a
#   Vendor/lib/libuvc.a
#
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(pwd)"

LIBUSB="$ROOT/Vendor/libusb"
LIBUVC="$ROOT/Vendor/libuvc"
GEN="$ROOT/Vendor/gen"
INC="$ROOT/Vendor/include"
LIB="$ROOT/Vendor/lib"
OBJ="$ROOT/Vendor/build/obj"

MINVER=16.0
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
CLANG="$(xcrun --sdk iphoneos -f clang)"
AR="$(xcrun --sdk iphoneos -f ar)"
MAC_IOKIT="$(xcrun --sdk macosx --show-sdk-path)/System/Library/Frameworks/IOKit.framework/Headers"

echo ">> 0. Applying iOS patches to submodules…"
# Idempotent: only apply if not already applied (reverse-check succeeds when applied).
apply_patch() {  # $1 = submodule dir, $2 = patch file
  if git -C "$1" apply --reverse --check "$2" >/dev/null 2>&1; then
    echo "   $(basename "$2") already applied"
  else
    git -C "$1" apply "$2" && echo "   $(basename "$2") applied"
  fi
}
apply_patch "$LIBUSB" "$ROOT/patches/libusb-ios.patch"
apply_patch "$LIBUVC" "$ROOT/patches/libuvc-ios.patch"

echo ">> 1. Vendoring macOS IOKit USB headers…"
mkdir -p "$INC/IOKit/usb"
cp "$MAC_IOKIT/IOCFPlugIn.h" "$INC/IOKit/"
cp "$MAC_IOKIT/IOCFBundle.h" "$INC/IOKit/"
cp "$MAC_IOKIT"/usb/*.h      "$INC/IOKit/usb/"

echo ">> 2. Generating configs…"
mkdir -p "$GEN/libuvc"

cat > "$GEN/config.h" <<'EOF'
/* Hand-generated libusb config for arm64 iOS. */
#include <AvailabilityMacros.h>
#define DEFAULT_VISIBILITY __attribute__ ((visibility ("default")))
#define ENABLE_LOGGING 1
#define HAVE_PTHREAD_THREADID_NP 1
#define HAVE_NFDS_T 1
#define HAVE_SYS_TIME_H 1
#define PLATFORM_POSIX 1
#define PRINTF_FORMAT(a, b) __attribute__ ((__format__ (__printf__, a, b)))
#define _GNU_SOURCE 1
EOF

# version_describe.h is normally produced by bootstrap.sh from `git describe`.
echo '#define LIBUSB_DESCRIBE ""' > "$GEN/version_describe.h"

cat > "$GEN/libuvc/libuvc_config.h" <<'EOF'
#ifndef LIBUVC_CONFIG_H
#define LIBUVC_CONFIG_H
#define LIBUVC_VERSION_MAJOR 0
#define LIBUVC_VERSION_MINOR 0
#define LIBUVC_VERSION_PATCH 7
#define LIBUVC_VERSION_STR "0.0.7"
#define LIBUVC_VERSION_INT ((0 << 16) | (0 << 8) | (7))
#define LIBUVC_VERSION_GTE(major, minor, patch) \
  (LIBUVC_VERSION_INT >= (((major) << 16) | ((minor) << 8) | (patch)))
/* JPEG/MJPEG is disabled because UVCDisplay currently accepts YUY2 only. */
#endif
EOF

CFLAGS_COMMON="-arch arm64 -isysroot $SDK -miphoneos-version-min=$MINVER -O2 -fno-common \
 -include TargetConditionals.h -Wno-nullability-completeness -Wno-deprecated-declarations \
 -Wno-unused-function"

echo ">> 3. Compiling libusb…"
rm -rf "$OBJ/libusb"; mkdir -p "$OBJ/libusb"
USB_INC="-I$GEN -I$LIBUSB/libusb -I$INC"
for f in core descriptor hotplug io strerror sync \
         os/darwin_usb os/events_posix os/threads_posix; do
  echo "   CC libusb/$f.c"
  $CLANG $CFLAGS_COMMON $USB_INC -c "$LIBUSB/libusb/$f.c" -o "$OBJ/libusb/$(basename "$f").o"
done
mkdir -p "$LIB"
rm -f "$LIB/libusb-1.0.a"
$AR rcs "$LIB/libusb-1.0.a" "$OBJ/libusb"/*.o
echo "   -> $LIB/libusb-1.0.a"

echo ">> 4. Compiling libuvc…"
rm -rf "$OBJ/libuvc"; mkdir -p "$OBJ/libuvc"
UVC_INC="-I$GEN -I$LIBUVC/include -I$LIBUSB/libusb"
for f in ctrl ctrl-gen device diag frame init stream misc; do
  echo "   CC src/$f.c"
  $CLANG $CFLAGS_COMMON $UVC_INC -c "$LIBUVC/src/$f.c" -o "$OBJ/libuvc/$f.o"
done
rm -f "$LIB/libuvc.a"
$AR rcs "$LIB/libuvc.a" "$OBJ/libuvc"/*.o
echo "   -> $LIB/libuvc.a"

echo ""
echo "Done. Static libs in Vendor/lib:"
ls -lh "$LIB"
echo "Arch check:"
lipo -archs "$LIB/libusb-1.0.a" "$LIB/libuvc.a" 2>/dev/null || true
