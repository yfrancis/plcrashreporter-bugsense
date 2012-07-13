/*
 
 BugSenseJSONGenerator.m
 BugSense-iOS
 
 Copyright (c) 2012 BugSense Inc.
 
 Permission is hereby granted, free of charge, to any person
 obtaining a copy of this software and associated documentation
 files (the "Software"), to deal in the Software without
 restriction, including without limitation the rights to use,
 copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the
 Software is furnished to do so, subject to the following
 conditions:
 
 The above copyright notice and this permission notice shall be
 included in all copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 OTHER DEALINGS IN THE SOFTWARE.
 
 Author: Nick Toumpelis, nick@bugsense.com
 Author: John Lianeris, jl@bugsense.com
 
 */

#include <ifaddrs.h>
#include <arpa/inet.h>
#include <sys/types.h>
#include <sys/sysctl.h>

#import "CrashReporter.h"
#import "BSReachability.h"
#import "BugSenseSymbolicator.h"
#import "BSOpenUDID.h"
#import "JSONKit.h"
#import <objc/runtime.h>
#import <objc/message.h>

#import "BugSenseJSONGenerator.h"

#define kNoAddressStatus        @"Could not be found."
#define kAppNameNotFoundStatus  @"App name not found."
#define kProcessPathNotFoundStatus @"Process path not found."
#define kCarrierNotFoundStatus  @"Carrier could not be determined."
#define kGeneratingJSONDataMsg  @"BugSense --> Generating JSON data from crash report..."
#define kJSONErrorMsg           @"BugSense --> Something unusual happened during the generation of JSON data!"
#define kGeneratingProcessMsg   @"BugSense --> Generating JSON data from crash report: %d/14"

#define kBugSenseFrameworkVersion @"2.0.4"
#define kBugSensePlatform @"iOS"

@implementation BugSenseJSONGenerator

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
+ (NSString *) frameworkVersion {
    return kBugSenseFrameworkVersion;
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
+ (NSString *) frameworkPlatform {
    return kBugSensePlatform;
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
+ (NSString *) applicationNameForReport:(PLCrashReport *)report {
    NSArray *identifierComponents = [report.applicationInfo.applicationIdentifier componentsSeparatedByString:@"."];
    if (identifierComponents && identifierComponents.count > 0) {
        return [identifierComponents lastObject];
    } else {
        return kAppNameNotFoundStatus;
    }
}

+ (NSString *) executableNameForReport:(PLCrashReport *)report {
    NSArray *pathComponents = [report.processInfo.processPath componentsSeparatedByString:@"/"];
    if (pathComponents && pathComponents.count > 0) {
        return [pathComponents lastObject];
    } else {
        return kProcessPathNotFoundStatus;
    }
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
+ (NSString *) applicationName {
    NSBundle *mainBundle = [NSBundle mainBundle];
    if (mainBundle) {
        NSArray *identifierComponents = [mainBundle.bundleIdentifier componentsSeparatedByString:@"."];
        if (identifierComponents && identifierComponents.count > 0) {
            return [identifierComponents lastObject];
        } else {
            return kAppNameNotFoundStatus;
        }
    } else {
        return kAppNameNotFoundStatus;
    }
}

+ (NSString *) executableName {
    return [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleExecutable"];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
+ (NSString *) applicationBuildNumberForReport:(PLCrashReport *)report {
    CFBundleRef bundle = CFBundleGetBundleWithIdentifier((CFStringRef)report.applicationInfo.applicationIdentifier);
    CFDictionaryRef bundleInfoDict = CFBundleGetInfoDictionary(bundle);
    CFStringRef buildNumber;
    
    // If we succeeded, look for our property.
    if (bundleInfoDict != NULL) {
        buildNumber = CFDictionaryGetValue(bundleInfoDict, CFSTR("CFBundleShortVersionString"));
        if (buildNumber) {
            return (NSString *)buildNumber;
        } else {
            return @"";
        }
    } else {
        return @"";
    }
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
+ (NSString *) applicationBuildNumber {
    NSBundle *mainBundle = [NSBundle mainBundle];
    NSDictionary *infoDictionary = mainBundle.infoDictionary;
    NSString *buildNumber = nil;
    if (infoDictionary && infoDictionary.count) {
        buildNumber = [infoDictionary objectForKey:@"CFBundleShortVersionString"];
        if (buildNumber) {
            return buildNumber;
        } else {
            return @"";
        }
    } else {
        return @"";
    }
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
+ (NSString *) applicationVersionNumberForReport:(PLCrashReport *)report {
    return report.applicationInfo.applicationVersion;
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
+ (NSString *) applicationVersionNumber {
    NSBundle *mainBundle = [NSBundle mainBundle];
    NSDictionary *infoDictionary = mainBundle.infoDictionary;
    NSString *versionNumber = nil;
    if (infoDictionary && infoDictionary.count) {
        versionNumber = [infoDictionary objectForKey:@"CFBundleVersion"];
        if (versionNumber) {
            return versionNumber;
        } else {
            return @"";
        }
    } else {
        return @"";
    }
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
+ (NSString *) IPAddress {
    NSString *address = kNoAddressStatus;
    
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp_addr = NULL;
    int success = 0;
    
    success = getifaddrs(&interfaces);
    if (success == 0) {
        temp_addr = interfaces;
        while (temp_addr != NULL) {
            if (temp_addr->ifa_addr->sa_family == AF_INET) {
                // Check if interface is en0 which is the wifi connection on the iPhone
                if ([[NSString stringWithUTF8String:temp_addr->ifa_name] isEqualToString:@"en0"]) {
                    address = [NSString 
                               stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)temp_addr->ifa_addr)->sin_addr)];
                }
            }
            temp_addr = temp_addr->ifa_next;
        }
    }
    
    // Free memory
    freeifaddrs(interfaces);
    
    return address;
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
+ (NSString *) device {
    int mib[2];
    size_t len;
    char *machine;
    
    mib[0] = CTL_HW;
    mib[1] = HW_MACHINE;
    sysctl(mib, 2, NULL, &len, NULL, 0);
    machine = malloc(len);
    sysctl(mib, 2, machine, &len, NULL, 0);
    
    NSString *platform = [NSString stringWithCString:machine encoding:NSASCIIStringEncoding];
    free(machine);
    
    NSString *device = nil;
    
    // iPhone
    if ([platform isEqualToString:@"iPhone1,1"]) {
        device = @"iPhone [iPhone1,1]";
    }
    
    if ([platform isEqualToString:@"iPhone1,2"]) {
        device = @"iPhone 3G [iPhone1,2]";
    }
    
    if ([platform isEqualToString:@"iPhone2,1"]) {
        device = @"iPhone 3GS [iPhone2,1]";
    }
    
    if ([platform isEqualToString:@"iPhone3,1"]) {
        device = @"iPhone 4 (GSM) [iPhone3,1]";
    }
    
    if ([platform isEqualToString:@"iPhone3,3"]) {
        device = @"iPhone 4 (CDMA) [iPhone3,3]";
    }
    
    if ([platform isEqualToString:@"iPhone4,1"]) {
        device = @"iPhone 4S [iPhone4,1]";
    }
    
    // iPod touch
    if ([platform isEqualToString:@"iPod1,1"]) {
        device = @"iPod Touch [iPod1,1]";
    }
    
    if ([platform isEqualToString:@"iPod2,1"]) {
        device = @"iPod Touch (2nd generation) [iPod2,1]";
    }
    
    if ([platform isEqualToString:@"iPod3,1"]) {
        device = @"iPod Touch (3rd generation) [iPod3,1]";
    }
    
    if ([platform isEqualToString:@"iPod4,1"]) {
        device = @"iPod Touch (4th generation) [iPod4,1]";
    }
    
    // iPad
    if ([platform isEqualToString:@"iPad1,1"]) {
        device = @"iPad [iPad1,1]";
    }
    
    if ([platform isEqualToString:@"iPad2,1"]) {
        device = @"iPad 2 (Wi-Fi) [iPad2,1]";
    }
    
    if ([platform isEqualToString:@"iPad2,2"]) {
        device = @"iPad 2 (Wi-Fi + 3G GSM) [iPad2,2]";
    }
    
    if ([platform isEqualToString:@"iPad2,3"]) {
        device = @"iPad 2 (Wi-Fi + 3G CDMA) [iPad2,3]";
    }
    
    // Apple TV
    if ([platform isEqualToString:@"AppleTV1,1"]) {
        device = @"Apple TV [AppleTV1,1]";
    }
    
    if ([platform isEqualToString:@"AppleTV2,1"]) {
        device = @"Apple TV (2nd generation) [AppleTV2,1]";
    }
    
    if ([platform isEqualToString:@"i386"]) {
        device = @"iPhone Simulator";
    }
    
    if (!device) {
        device = [UIDevice currentDevice].model;
    }
    
    if (!device) {
        if (!platform) {
            return @"";
        } else {
            return platform;
        }
    } else {
        return device;
    }
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
+ (NSString *) carrierName {
    Class telephonyNetworkInfoClass = NSClassFromString(@"CTTelephonyNetworkInfo");
    Class carrierClass = NSClassFromString(@"CTCarrier");
    if (telephonyNetworkInfoClass && carrierClass) {
        id telephonyNetworkInfo = [[[telephonyNetworkInfoClass alloc] init] autorelease];
        id carrier = objc_msgSend(telephonyNetworkInfo, sel_getUid("subscriberCellularProvider"));
        NSString *carrierName = (NSString *)objc_msgSend(carrier, sel_getUid("carrierName"));
        return carrierName;
    } else {
        return kCarrierNotFoundStatus;
    }
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
+ (NSString *) languagesForReport:(PLCrashReport *)report {
    CFBundleRef bundle = CFBundleGetBundleWithIdentifier((CFStringRef)report.applicationInfo.applicationIdentifier);
    CFDictionaryRef bundleInfoDict = CFBundleGetInfoDictionary(bundle);
    if (bundleInfoDict != NULL) {
        NSMutableString *languages = [[[NSMutableString alloc] init] autorelease];
        CFStringRef baseLanguage = CFDictionaryGetValue(bundleInfoDict, kCFBundleDevelopmentRegionKey);
        if (baseLanguage) {
            [languages appendString:(NSString *)baseLanguage];
        }
        
        CFStringRef allLanguages = CFDictionaryGetValue(bundleInfoDict, kCFBundleLocalizationsKey);
        if (allLanguages) {
            [languages appendString:(NSString *)allLanguages];
        }
        
        if (languages) {
            return languages;
        } else {
            return @"";
        }
    } else {
        return @"";
    }
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
+ (NSString *) languages {
    CFBundleRef bundle = CFBundleGetBundleWithIdentifier((CFStringRef)[NSBundle mainBundle].bundleIdentifier);
    CFDictionaryRef bundleInfoDict = CFBundleGetInfoDictionary(bundle);
    if (bundleInfoDict != NULL) {
        NSMutableString *languages = [[[NSMutableString alloc] init] autorelease];
        CFStringRef baseLanguage = CFDictionaryGetValue(bundleInfoDict, kCFBundleDevelopmentRegionKey);
        if (baseLanguage) {
            [languages appendString:(NSString *)baseLanguage];
        }
        
        CFStringRef allLanguages = CFDictionaryGetValue(bundleInfoDict, kCFBundleLocalizationsKey);
        if (allLanguages) {
            [languages appendString:(NSString *)allLanguages];
        }
        
        if (languages) {
            return languages;
        } else {
            return @"";
        }
    } else {
        return @"";
    }
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
+ (NSData *) JSONDataFromCrashReport:(PLCrashReport *)report userDictionary:(NSDictionary *)userDictionary {
    if (!report) {
        return nil;
    }
    
    @try {
        NSLog(kGeneratingJSONDataMsg);
        
        // --application_environment
        NSMutableDictionary *application_environment = [[[NSMutableDictionary alloc] init] autorelease];
        
        // ----bugsense_version
        [application_environment setObject:[self frameworkVersion] forKey:@"version"];
        
        // ----bugsense_name
        [application_environment setObject:[self frameworkPlatform] forKey:@"name"];
        
        // ----appname
        [application_environment setObject:[self applicationNameForReport:report] forKey:@"appname"];
        
        // ----appver
        [application_environment setObject:[self applicationBuildNumberForReport:report] forKey:@"appver"];
        
        // ----internal_version
        [application_environment setObject:[self applicationVersionNumberForReport:report] forKey:@"internal_version"];
        
        // ----gps_on
        Class locationManagerClass = NSClassFromString(@"CLLocationManager");
        if (locationManagerClass) {
            [application_environment setObject:[NSNumber numberWithBool:(BOOL)[locationManagerClass locationServicesEnabled]] 
                                        forKey:@"gps_on"];
        }
        
        NSLog(kGeneratingProcessMsg, 1);
              
        if ([self carrierName])
            [application_environment setObject:[self carrierName] forKey:@"carrier"];
        
        [application_environment setObject:[self languagesForReport:report] forKey:@"languages"];

        // ----locale
        [application_environment setObject:[[NSLocale currentLocale] localeIdentifier] forKey:@"locale"];

        // ----mobile_net_on, wifi_on
        BSReachability *reach = [BSReachability reachabilityForInternetConnection];
        NetworkStatus status = [reach currentReachabilityStatus];
        switch (status) {
            case NotReachable:
                [application_environment setObject:[NSNumber numberWithBool:NO] forKey:@"mobile_net_on"];
                [application_environment setObject:[NSNumber numberWithBool:NO] forKey:@"wifi_on"];
                break;
            case ReachableViaWiFi:
                [application_environment setObject:[NSNumber numberWithBool:NO] forKey:@"mobile_net_on"];
                [application_environment setObject:[NSNumber numberWithBool:YES] forKey:@"wifi_on"];
                break;
            case ReachableViaWWAN:
                [application_environment setObject:[NSNumber numberWithBool:YES] forKey:@"mobile_net_on"];
                [application_environment setObject:[NSNumber numberWithBool:NO] forKey:@"wifi_on"];
                break;
        }
        
        NSLog(kGeneratingProcessMsg, 2);
        
        // ----osver
        [application_environment setObject:report.systemInfo.operatingSystemVersion forKey:@"osver"];
        
        // ----phone
        [application_environment setObject:[self device] forKey:@"phone"];
        
        // ----timestamp
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        [formatter setDateFormat:@"YYYY-MM-dd HH:mm:ss zzzzz"];
        [application_environment setObject:[formatter stringFromDate:report.systemInfo.timestamp] 
                                    forKey:@"timestamp"];
        [formatter release];
        
        // --exception
        NSMutableDictionary *exception = [[[NSMutableDictionary alloc] init] autorelease];
        
        // ----backtrace, where
        PLCrashReportThreadInfo *crashedThreadInfo = nil;
        for (PLCrashReportThreadInfo *threadInfo in report.threads) {
            if (threadInfo.crashed) {
                crashedThreadInfo = threadInfo;
                break;
            }
        }
        
        NSLog(kGeneratingProcessMsg, 3);
        
        if (!crashedThreadInfo) {
            if (report.threads.count > 0) {
                crashedThreadInfo = [report.threads objectAtIndex:0];
            }
        }
        
        NSLog(kGeneratingProcessMsg, 4);

        NSMutableArray *stacktrace = [[[NSMutableArray alloc] init] autorelease];
        if (report.hasExceptionInfo) {
            PLCrashReportExceptionInfo *exceptionInfo = report.exceptionInfo;
            NSInteger pos = -1;
            
            for (NSUInteger frameIndex = 0; frameIndex < [exceptionInfo.stackFrames count]; frameIndex++) {
                PLCrashReportStackFrameInfo *frameInfo = [exceptionInfo.stackFrames objectAtIndex:frameIndex];
                PLCrashReportBinaryImageInfo *imageInfo;
                
                uint64_t baseAddress = 0x0;
                uint64_t pcOffset = 0x0;
                const char *imageName = "\?\?\?";
                
                imageInfo = [report imageForAddress:frameInfo.instructionPointer];
                if (imageInfo != nil) {
                    imageName = [[imageInfo.imageName lastPathComponent] UTF8String];
                    baseAddress = imageInfo.imageBaseAddress;
                    pcOffset = frameInfo.instructionPointer - imageInfo.imageBaseAddress;
                }
                
                //Dl_info theInfo;
                NSString *stackframe = nil;
                NSString *commandName = nil;
                NSArray *symbolAndOffset = 
                [BugSenseSymbolicator symbolAndOffsetForInstructionPointer:frameInfo.instructionPointer];
                if (symbolAndOffset && symbolAndOffset.count > 1) {
                    commandName = [symbolAndOffset objectAtIndex:0];
                    pcOffset = ((NSString *)[symbolAndOffset objectAtIndex:1]).integerValue;
                    stackframe = [NSString stringWithFormat:@"%-4ld%-36s0x%08" PRIx64 " %@ + %" PRId64 "",
                                  (long)frameIndex, imageName, frameInfo.instructionPointer, commandName, pcOffset];
                } else {
                    stackframe = [NSString stringWithFormat:@"%-4ld%-36s0x%08" PRIx64 " 0x%" PRIx64 " + %" PRId64 "", 
                                  (long)frameIndex, imageName, frameInfo.instructionPointer, baseAddress, pcOffset];
                }
                
                [stacktrace addObject:stackframe];
                
                if ([commandName hasPrefix:@"+[NSException raise:"]) {
                    pos = frameIndex+1;
                } else {
                    if (pos != -1 && pos == frameIndex) {
                        [exception setObject:stackframe forKey:@"where"];
                    }
                }
            }
        } else {
            for (NSUInteger frameIndex = 0; frameIndex < [crashedThreadInfo.stackFrames count]; frameIndex++) {
                PLCrashReportStackFrameInfo *frameInfo = [crashedThreadInfo.stackFrames objectAtIndex:frameIndex];
                PLCrashReportBinaryImageInfo *imageInfo;
                
                uint64_t baseAddress = 0x0;
                uint64_t pcOffset = 0x0;
                const char *imageName = "\?\?\?";
                
                imageInfo = [report imageForAddress:frameInfo.instructionPointer];
                if (imageInfo != nil) {
                    imageName = [[imageInfo.imageName lastPathComponent] UTF8String];
                    baseAddress = imageInfo.imageBaseAddress;
                    pcOffset = frameInfo.instructionPointer - imageInfo.imageBaseAddress;
                }
                
                //Dl_info theInfo;
                NSString *stackframe = nil;
                NSString *commandName = nil;
                NSArray *symbolAndOffset = 
                [BugSenseSymbolicator symbolAndOffsetForInstructionPointer:frameInfo.instructionPointer];
                if (symbolAndOffset && symbolAndOffset.count > 1) {
                    commandName = [symbolAndOffset objectAtIndex:0];
                    pcOffset = ((NSString *)[symbolAndOffset objectAtIndex:1]).integerValue;
                    stackframe = [NSString stringWithFormat:@"%-4ld%-36s0x%08" PRIx64 " %@ + %" PRId64 "",
                                  (long)frameIndex, imageName, frameInfo.instructionPointer, commandName, pcOffset];
                } else {
                    stackframe = [NSString stringWithFormat:@"%-4ld%-36s0x%08" PRIx64 " 0x%" PRIx64 " + %" PRId64 "", 
                                  (long)frameIndex, imageName, frameInfo.instructionPointer, baseAddress, pcOffset];
                }
                [stacktrace addObject:stackframe];
                
                if (report.signalInfo.address == frameInfo.instructionPointer) {
                    [exception setObject:stackframe forKey:@"where"];
                }
            }
        }
        
        NSLog(kGeneratingProcessMsg, 5);
        
        if (![exception objectForKey:@"where"] && stacktrace && stacktrace.count > 0) {
            [exception setObject:[stacktrace objectAtIndex:0] forKey:@"where"];
        }

        NSLog(kGeneratingProcessMsg, 6);
        
        if (stacktrace.count > 0) {
            [exception setObject:stacktrace forKey:@"backtrace"];
        } else {
            [exception setObject:@"No backtrace available [?]" forKey:@"backtrace"];
        }

        NSLog(kGeneratingProcessMsg, 7);
        
        // ----klass, message
        if (report.hasExceptionInfo) {
            [exception setObject:report.exceptionInfo.exceptionName forKey:@"klass"];
            [exception setObject:report.exceptionInfo.exceptionReason forKey:@"message"];
        } else {
            [exception setObject:@"SIGNAL" forKey:@"klass"];
            [exception setObject:report.signalInfo.name forKey:@"message"];
        }
        
        NSLog(kGeneratingProcessMsg, 8);
        
        // --request
        NSMutableDictionary *request = [[[NSMutableDictionary alloc] init] autorelease];
        
        // ----remote_ip
        [request setObject:[self IPAddress] forKey:@"remote_ip"];
        if (userDictionary) {
            [request setObject:userDictionary forKey:@"custom_data"];
        }
        
        NSLog(kGeneratingProcessMsg, 9);
        
        // --architecture
        NSArray *arch = [NSArray arrayWithObjects:@"x86_32", @"x86_64", @"armv6", @"ppc", @"ppc64", @"armv7", @"Unknown", nil];
        [application_environment setObject:[arch objectAtIndex:report.systemInfo.architecture] forKey:@"architecture"];
        
        // --registers & crashed thread number
        if (crashedThreadInfo) {
            NSMutableDictionary *registers = [[NSMutableDictionary alloc] initWithCapacity:crashedThreadInfo.registers.count];
            for (PLCrashReportRegisterInfo *reg in crashedThreadInfo.registers) {
                [registers setObject:[NSString stringWithFormat:@"0x%" PRIx64, reg.registerValue] forKey:reg.registerName];
            }
            [application_environment setObject:registers forKey:@"registers"];
            
            [exception setObject:[NSNumber numberWithInteger:crashedThreadInfo.threadNumber] forKey:@"thread_crashed"];
        }
        
        NSLog(kGeneratingProcessMsg, 10);
        
        // --signal
        [exception setObject:report.signalInfo.code forKey:@"signal_code"];
        [exception setObject:report.signalInfo.name forKey:@"signal_name"];
        
        // --execname
        [application_environment setObject:[self executableNameForReport:report] forKey:@"execname"];

        NSLog(kGeneratingProcessMsg, 11);
        
        // --image binary info
        for (PLCrashReportBinaryImageInfo *image in report.images) {
            NSArray *arr = [image.imageName componentsSeparatedByString:@"/"];
            
            if (([arr count] > 0) && [image.imageName hasPrefix:@"/var"]) {
                
                NSString *binary_filename = [arr lastObject];
                
                if ([binary_filename isEqualToString:[self executableNameForReport:report]]) {
                    
                    [application_environment setObject:[NSString stringWithFormat:@"0x%" PRIx64, image.imageBaseAddress] forKey:@"image_base_address"];
                    [application_environment setObject:[NSString stringWithFormat:@"0x%" PRIx64, image.imageSize] forKey:@"image_size"];
                    
                    [application_environment setObject:image.imageUUID forKey:@"build_uuid"];
                }
            }
        }
        
        NSLog(kGeneratingProcessMsg, 12);
        
        // --budid
        [application_environment setObject:[BSOpenUDID value] forKey:@"budid"];
        
        NSLog(kGeneratingProcessMsg, 13);
        
        // root
        NSMutableDictionary *rootDictionary = [[[NSMutableDictionary alloc] init] autorelease];
        [rootDictionary setObject:application_environment forKey:@"application_environment"];
        [rootDictionary setObject:exception forKey:@"exception"];
        [rootDictionary setObject:request forKey:@"request"];
        
        NSString *jsonString = 
        [(NSString *)CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault, (CFStringRef)[rootDictionary bs_JSONString],
                                                NULL, CFSTR("!*'();:@&=+$,/?%#[]"), kCFStringEncodingUTF8) autorelease];

        NSLog(kGeneratingProcessMsg, 14);
        
        return [jsonString dataUsingEncoding:NSUTF8StringEncoding];
    } @catch (NSException *exception) {
        NSLog(kJSONErrorMsg);
        return nil;
    }
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
+ (NSData *) JSONDataFromException:(NSException *)exception userDictionary:(NSDictionary *)userDictionary 
                               tag:(NSString *)tag {
    if (!exception) {
        return nil;
    }
    
    @try {
        NSLog(kGeneratingJSONDataMsg);
        
        // --application_environment
        NSMutableDictionary *application_environment = [[[NSMutableDictionary alloc] init] autorelease];
        
        // ----bugsense_version
        [application_environment setObject:[self frameworkVersion] forKey:@"version"];
        
        // ----bugsense_name
        [application_environment setObject:[self frameworkPlatform] forKey:@"name"];
        
        // ----appname
        [application_environment setObject:[self applicationName] forKey:@"appname"];
        
        // ----appver
        [application_environment setObject:[self applicationBuildNumber] forKey:@"appver"];
        
        // ----internal_version
        [application_environment setObject:[self applicationVersionNumber] forKey:@"internal_version"];
        
        // ----gps_on
        Class locationManagerClass = NSClassFromString(@"CLLocationManager");
        if (locationManagerClass) {
            [application_environment setObject:[NSNumber numberWithBool:(BOOL)[locationManagerClass locationServicesEnabled]] 
                                        forKey:@"gps_on"];
        }
        
        [application_environment setObject:[self carrierName] forKey:@"carrier"];
        
        [application_environment setObject:[self languages] forKey:@"languages"];
        
        // ----locale
        [application_environment setObject:[[NSLocale currentLocale] localeIdentifier] forKey:@"locale"];
        
        // ----mobile_net_on, wifi_on
        BSReachability *reach = [BSReachability reachabilityForInternetConnection];
        NetworkStatus status = [reach currentReachabilityStatus];
        switch (status) {
            case NotReachable:
                [application_environment setObject:[NSNumber numberWithBool:NO] forKey:@"mobile_net_on"];
                [application_environment setObject:[NSNumber numberWithBool:NO] forKey:@"wifi_on"];
                break;
            case ReachableViaWiFi:
                [application_environment setObject:[NSNumber numberWithBool:NO] forKey:@"mobile_net_on"];
                [application_environment setObject:[NSNumber numberWithBool:YES] forKey:@"wifi_on"];
                break;
            case ReachableViaWWAN:
                [application_environment setObject:[NSNumber numberWithBool:YES] forKey:@"mobile_net_on"];
                [application_environment setObject:[NSNumber numberWithBool:NO] forKey:@"wifi_on"];
                break;
        }
        
        // ----osver
        [application_environment setObject:[[UIDevice currentDevice] systemVersion] forKey:@"osver"];
        
        // ----phone
        [application_environment setObject:[self device] forKey:@"phone"];
        
        // ----timestamp
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        [formatter setDateFormat:@"YYYY-MM-dd HH:mm:ss zzzzz"];
        [application_environment setObject:[formatter stringFromDate:[NSDate date]] 
                                    forKey:@"timestamp"];
        [formatter release];
        
        
        // --exception
        NSMutableDictionary *exceptionDict = [[[NSMutableDictionary alloc] init] autorelease];
        
        // ----backtrace, where        
        NSArray *stacktrace = [exception callStackSymbols];
        
        if (![exceptionDict objectForKey:@"where"] && stacktrace && stacktrace.count > 0) {
            [exceptionDict setObject:[stacktrace objectAtIndex:0] forKey:@"where"];
        }
        
        if (stacktrace.count > 0) {
            [exceptionDict setObject:stacktrace forKey:@"backtrace"];
        } else {
            [exceptionDict setObject:@"No backtrace available [?]" forKey:@"backtrace"];
        }
        
        // ----klass, message
        [exceptionDict setObject:exception.name forKey:@"klass"];
        [exceptionDict setObject:exception.reason forKey:@"message"];
        
        // --request
        NSMutableDictionary *request = [[[NSMutableDictionary alloc] init] autorelease];
        
        // ----remote_ip
        [request setObject:[self IPAddress] forKey:@"remote_ip"];
        if (userDictionary) {
            [request setObject:userDictionary forKey:@"custom_data"];
            [request setObject:[NSString stringWithFormat:@"log-%@",tag] forKey:@"tag"];
        }
        
        // --execname
        [application_environment setObject:[self executableName] forKey:@"execname"];
        
        // --budid
        [application_environment setObject:[BSOpenUDID value] forKey:@"budid"];
        
        // root
        NSMutableDictionary *rootDictionary = [[[NSMutableDictionary alloc] init] autorelease];
        [rootDictionary setObject:application_environment forKey:@"application_environment"];
        [rootDictionary setObject:exceptionDict forKey:@"exception"];
        [rootDictionary setObject:request forKey:@"request"];
        
        NSString *jsonString = 
        [(NSString *)CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault, (CFStringRef)[rootDictionary bs_JSONString],
                                                NULL, CFSTR("!*'();:@&=+$,/?%#[]"), kCFStringEncodingUTF8) autorelease];
        return [jsonString dataUsingEncoding:NSUTF8StringEncoding];
    } @catch (NSException *jsonException) {
        NSLog(kJSONErrorMsg);
        return nil;
    }
}

@end
