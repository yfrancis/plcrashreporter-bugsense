# BugSense for iOS

This is the source code for the iOS version of the BugSense plugin.

*Latest updates*: Compatible with iOS 4.0+. Provides accurate program counter offset for each line in the stacktrace. Bug fixes for possible misreportings. Improvements across the board. Major refactorings to support additional future functionality.

*Issues*: https://github.com/bugsense/plcrashreporter-bugsense/issues 

*Note*: The source code/project works best with Xcode 4.2 and LLVM 3.0. The static library target builds with THUMB support disabled. Uses blocks extensively, but can be adapted to work with iOS 3.0 with some effort.


### Project status
 
The framework has been updated to work properly for iOS 4.0+ and both armv6 and armv7 in devices and the simulator. Symbolication on the device works much more accurately than before.


### Summary

This is the source code for BugSense-iOS, a crash reporting service for mobile applications. This framework is based on plcrashreporter, AFNetworking, JSONKit, and Apple's Reachability. 

plcrashreporter is by [Plausible Labs](http://plausible.coop/), maintained by [Landon Fuller](http://landonf.bikemonkey.org/) and hosted [here](http://code.google.com/p/plcrashreporter/). AFNetworking is by [Gowalla](http://gowalla.com/), was created by [Scott Raymond](https://github.com/sco/) and [Mattt Thompson](https://github.com/mattt) and hosted [here](https://github.com/gowalla/AFNetworking). JSONKit is the work of [John Engelhart](https://github.com/johnezang) and you can find it [here](https://github.com/johnezang/JSONKit).


### Requirements 

In order to build the framework, you need to use [Karl Stenerud](https://github.com/kstenerud)'s [iOS-Universal-Framework] (https://github.com/kstenerud/iOS-Universal-Framework), which updates your development environment with a few additional templates and settings for creating frameworks.
