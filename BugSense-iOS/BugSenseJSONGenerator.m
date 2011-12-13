/*
 
 BugSenseJSONGenerator.m
 BugSense-iOS
 
 Copyright (c) 2011 BugSense.com
 
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
 
 */

#include <ifaddrs.h>
#include <arpa/inet.h>
#include <sys/types.h>
#include <sys/sysctl.h>

#import <CoreLocation/CoreLocation.h>
#import "CrashReporter.h"
#import "BSReachability.h"
#import "BugSenseSymbolicator.h"
#import "JSONKit.h"

#import "BugSenseJSONGenerator.h"

#define kGeneratingJSONDataMsg  @"BugSense --> Generating JSON data from crash report..."
#define kJSONErrorMsg           @"BugSense --> Something unusual happened during the generation of JSON data!"

@implementation BugSenseJSONGenerator

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
+ (NSString *) currentIPAddress {
    NSString *address = @"Could not be found";
    
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
+ (NSData *) JSONDataFromCrashReport:(PLCrashReport *)report userDictionary:(NSDictionary *)userDictionary {
    if (!report) {
        return nil;
    }
    
    @try {
        NSLog(kGeneratingJSONDataMsg);
        
        // --application_environment
        NSMutableDictionary *application_environment = [[[NSMutableDictionary alloc] init] autorelease];
        
        // ----appname
        NSArray *identifierComponents = [report.applicationInfo.applicationIdentifier componentsSeparatedByString:@"."];
        if (identifierComponents && identifierComponents.count > 0) {
            [application_environment setObject:[identifierComponents lastObject] forKey:@"appname"];
        }
        
        // ----appver
        CFBundleRef bundle = CFBundleGetBundleWithIdentifier((CFStringRef)report.applicationInfo.applicationIdentifier);
        CFDictionaryRef bundleInfoDict = CFBundleGetInfoDictionary(bundle);
        CFStringRef buildNumber;
        
        // If we succeeded, look for our property.
        if (bundleInfoDict != NULL) {
            buildNumber = CFDictionaryGetValue(bundleInfoDict, CFSTR("CFBundleShortVersionString"));
            if (buildNumber) {
                [application_environment setObject:(NSString *)buildNumber forKey:@"appver"];
            }
        }
        
        // ----internal_version
        [application_environment setObject:report.applicationInfo.applicationVersion forKey:@"internal_version"];
        
        // ----gps_on
        [application_environment setObject:[NSNumber numberWithBool:[CLLocationManager locationServicesEnabled]] 
                                    forKey:@"gps_on"];
        
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
                [application_environment setObject:(NSString *)languages forKey:@"languages"];
            }
        }
        
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
        
        if (!crashedThreadInfo) {
            if (report.threads.count > 0) {
                crashedThreadInfo = [report.threads objectAtIndex:0];
            }
        }
        
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
        
        if (![exception objectForKey:@"where"] && stacktrace && stacktrace.count > 0) {
            [exception setObject:[stacktrace objectAtIndex:0] forKey:@"where"];
        }
        
        if (stacktrace.count > 0) {
            [exception setObject:stacktrace forKey:@"backtrace"];
        } else {
            [exception setObject:@"No backtrace available [?]" forKey:@"backtrace"];
        }
        
        // ----klass, message
        if (report.hasExceptionInfo) {
            [exception setObject:report.exceptionInfo.exceptionName forKey:@"klass"];
            [exception setObject:report.exceptionInfo.exceptionReason forKey:@"message"];
        } else {
            [exception setObject:@"SIGNAL" forKey:@"klass"];
            [exception setObject:report.signalInfo.name forKey:@"message"];
        }
        
        // --request
        NSMutableDictionary *request = [[[NSMutableDictionary alloc] init] autorelease];
        
        // ----remote_ip
        [request setObject:[self currentIPAddress] forKey:@"remote_ip"];
        if (userDictionary) {
            [request setObject:userDictionary forKey:@"custom_data"];
        }
        
        // root
        NSMutableDictionary *rootDictionary = [[[NSMutableDictionary alloc] init] autorelease];
        [rootDictionary setObject:application_environment forKey:@"application_environment"];
        [rootDictionary setObject:exception forKey:@"exception"];
        [rootDictionary setObject:request forKey:@"request"];
        
        NSString *jsonString = 
            [[rootDictionary JSONString] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        return [jsonString dataUsingEncoding:NSUTF8StringEncoding];
    } @catch (NSException *exception) {
        NSLog(kJSONErrorMsg);
        return nil;
    }
}

@end
