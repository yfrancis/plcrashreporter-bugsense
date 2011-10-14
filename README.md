# BugSense for iOS

This is the source code for BugSense-iOS, a crash reporting service for mobile applications. This framework is based on plcrashreporter, AFNetworking and JSONKit. (Also Reachability, which is Apple's source code, but everybody uses that). 

plcrashreporter is by Plausible Labs, maintained by Landon Fuller and hosted [here](http://code.google.com/p/plcrashreporter/). AFNetworking is by Gowalla, was created by [Scott Raymond](https://github.com/sco/) and [Mattt Thompson](https://github.com/mattt) and hosted [here](https://github.com/gowalla/AFNetworking). JSONKit is the work of [John Engelhart](https://github.com/johnezang) and you can find it [here](https://github.com/johnezang/JSONKit).


## Project status

The framework has been updated to work properly for iOS 3.0+ and both armv6 and armv7. Unfortunately, after the recent updates, we haven't been able to fully support the iOS Simulator. You need to get the source code to do that. We have fixed any conflicts that could arise by using JSONKit, Reachability and AFNetworking. 
