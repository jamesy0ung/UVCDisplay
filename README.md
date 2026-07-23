# UVCDisplay

UVCDisplay is an app that allows you to use a jailbroken or trollstore'd iOS device to view the output of a UVC device.

Currently it's hardcoded to the VID/PID of the MS2130, but it should be extensible to other UVC class devices.

It works by using libusb to talk to the device through the IOUSBHost IOKit user client, then libuvc is used to negotiate the UVC stream. The app then requests YUY2 video from the device. Frames from libuvc are converted into metal textures and a shader (YUY2Shaders.metal) converts the YUY2 colours into RGB colours. The SwiftUI layer shows the feed fullscreen and drops to a diagnostic console if no frames arrive in 4 seconds.

This is redundant on iOS 17 and above, you already have UVC support. iOS <17 does not.

You will need to be jailbroken or have trollstore installed, as it requires 2 private entitlements, `com.apple.security.exception.iokit-user-client-class`, and `com.apple.system.diagnostics.iokit-properties`.

To build, clone this repo `git clone --recurse-submodules https://github.com/jamesy0ung/UVCDisplay.git`, then run `./build_deps.sh` and `./build_tipa.sh`.
