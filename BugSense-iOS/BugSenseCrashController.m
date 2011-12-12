/*
 
 BugSenseCrashController.m
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
#include <dlfcn.h>
#include <execinfo.h>

#import "BugSenseCrashController.h"
#import "BugSenseSymbolicator.h"

#import <objc/runtime.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreLocation/CoreLocation.h>

#import "CrashReporter.h"
#import "PLCrashReportTextFormatter.h"
#import "JSONKit.h"
#import "BSReachability.h"
#import "BSAFHTTPRequestOperation.h"
#import "NSMutableURLRequest+AFNetworking.h"

#define BUGSENSE_REPORTING_SERVICE_URL  @"http://www.bugsense.com/api/errors"
#define BUGSENSE_HEADER                 @"X-BugSense-Api-Key"

#define kLoadErrorString                @"BugSense --> Error: Could not load crash report data due to: %@"
#define kParseErrorString               @"BugSense --> Error: Could not parse crash report due to: %@"
#define kJSONErrorString                @"BugSense --> Could not prepare JSON crash report string."
#define kWarningString                  @"BugSense --> Warning: %@"
#define kProcessingMsgString            @"BugSense --> Processing crash report..."
#define kCrashMsgString                 @"BugSense --> Crashed on %@, with signal %@ (code %@, address=0x%" PRIx64 ")"


#pragma mark - Private interface
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
@interface BugSenseCrashController (Private)

- (PLCrashReporter *) crashReporter;
- (PLCrashReport *) crashReport;
- (NSString *) currentIPAddress;

void post_crash_callback(siginfo_t *info, ucontext_t *uap, void *context);
- (void) performPostCrashOperations;

- (id) initWithAPIKey:(NSString *)bugSenseAPIKey 
       userDictionary:(NSDictionary *)userDictionary 
      sendImmediately:(BOOL)immediately;

- (void) retainSymbols;
- (void) processCrashReport;
- (void) initiateReportingProcess;
- (NSData *) JSONDataFromCrashReport:(PLCrashReport *)report;
- (BOOL) postJSONData:(NSData *)jsonData;
- (void) observeValueForKeyPath:(NSString *)keyPath 
                       ofObject:(id)object 
                         change:(NSDictionary *)change 
                        context:(void *)context;

@end


#pragma mark - Implementation
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
@implementation BugSenseCrashController {
    NSString        *_APIKey;
    NSDictionary    *_userDictionary;
    BOOL            _immediately;
    BOOL            _operationCompleted;
    
    PLCrashReporter *_crashReporter;
    PLCrashReport   *_crashReport;
}

static BugSenseCrashController *_sharedCrashController = nil;

#pragma mark - Common methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (PLCrashReporter *) crashReporter {
    if (!_crashReporter) {
        _crashReporter = [PLCrashReporter sharedReporter];
    }
    return _crashReporter;
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (PLCrashReport *) crashReport {
    if (!_crashReport) {
        NSError *error = nil;
        
        NSData *crashData = [[self crashReporter] loadPendingCrashReportDataAndReturnError:&error];
        if (!crashData) {
            NSLog(kLoadErrorString, error);
            [[self crashReporter] purgePendingCrashReport];
            return nil;
        } else {
            if (error != nil) {
                NSLog(kWarningString, error);
            }
        }
        
        _crashReport = [[PLCrashReport alloc] initWithData:crashData error:&error];
        if (!_crashReport) {
            NSLog(kParseErrorString, error);
            [[self crashReporter] purgePendingCrashReport];
            return nil;
        } else {
            if (error != nil) {
                NSLog(kWarningString, error);
            }
            return _crashReport;
        }
    } else {
        return _crashReport;
    }
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (NSString *) currentIPAddress {
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


#pragma mark - Crash callback function
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
void post_crash_callback(siginfo_t *info, ucontext_t *uap, void *context) {
    [_sharedCrashController performSelectorOnMainThread:@selector(performPostCrashOperations) 
                                             withObject:nil 
                                          waitUntilDone:YES];
}


#pragma mark - Crash callback method
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (void) performPostCrashOperations {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        [self retainSymbols];
    });
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        if (_immediately && [[self crashReporter] hasPendingCrashReport]) {
            [self processCrashReport];
        }
    });
    
    CFRunLoopRef runLoop = CFRunLoopGetCurrent();
	CFArrayRef allModes = CFRunLoopCopyAllModes(runLoop);
	
	while (!_operationCompleted) {
		for (NSString *mode in (NSArray *)allModes) {
			CFRunLoopRunInMode((CFStringRef)mode, 0.001, false);
		}
	}
	
	CFRelease(allModes);
    
	NSSetUncaughtExceptionHandler(NULL);
	signal(SIGABRT, SIG_DFL);
	signal(SIGILL, SIG_DFL);
	signal(SIGSEGV, SIG_DFL);
	signal(SIGFPE, SIG_DFL);
	signal(SIGBUS, SIG_DFL);
	signal(SIGPIPE, SIG_DFL);
    
    NSLog(@"BugSense --> Immediate dispatch completed!");
    
    abort();
}


#pragma mark - Object lifecycle
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
+ (BugSenseCrashController *) sharedInstanceWithBugSenseAPIKey:(NSString *)bugSenseAPIKey 
                                                userDictionary:(NSDictionary *)userDictionary
                                               sendImmediately:(BOOL)immediately {
    static dispatch_once_t oncePredicate;
    dispatch_once(&oncePredicate, ^{
        if (!_sharedCrashController) {
            [[self alloc] initWithAPIKey:bugSenseAPIKey userDictionary:userDictionary sendImmediately:immediately];
            [_sharedCrashController initiateReportingProcess];
        }
    });
    
    return _sharedCrashController;
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
+ (BugSenseCrashController *) sharedInstanceWithBugSenseAPIKey:(NSString *)bugSenseAPIKey 
                                                userDictionary:(NSDictionary *)userDictionary {
    return [self sharedInstanceWithBugSenseAPIKey:bugSenseAPIKey userDictionary:userDictionary sendImmediately:NO];
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
+ (BugSenseCrashController *) sharedInstanceWithBugSenseAPIKey:(NSString *)bugSenseAPIKey {
    return [self sharedInstanceWithBugSenseAPIKey:bugSenseAPIKey userDictionary:nil];
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (id) initWithAPIKey:(NSString *)bugSenseAPIKey 
       userDictionary:(NSDictionary *)userDictionary 
      sendImmediately:(BOOL)immediately {
    if ((self = [super init])) {
        _operationCompleted = NO;
        
        if (bugSenseAPIKey) {
            _APIKey = [bugSenseAPIKey retain];
        }
        
        if (userDictionary && userDictionary.count > 0) {
            _userDictionary = [userDictionary retain];
        } else {
            _userDictionary = nil;
        }
        
        _immediately = immediately;
    }
    return self;
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
+ (id) allocWithZone:(NSZone *)zone {
    @synchronized(self) {
        if (!_sharedCrashController) {
            _sharedCrashController = [super allocWithZone:zone];
            return _sharedCrashController;  // assignment and return on first allocation
        }
    }
    return nil; //on subsequent allocation attempts return nil
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (id) copyWithZone:(NSZone *)zone {
    return self;
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (id) retain { 
    return self; 
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (oneway void) release {

}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (id) autorelease { 
    return self; 
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (NSUInteger) retainCount { 
    return NSUIntegerMax; 
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (void) dealloc {
    [_APIKey release];
    [_userDictionary release];
    [_crashReporter release];
    [_crashReport release];
    
    [super dealloc];
}


#pragma mark - Process methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (void) retainSymbols {
    PLCrashReportThreadInfo *crashedThreadInfo = nil;
    for (PLCrashReportThreadInfo *threadInfo in [self crashReport].threads) {
        if (threadInfo.crashed) {
            crashedThreadInfo = threadInfo;
            break;
        }
    }
    
    if (!crashedThreadInfo) {
        if ([self crashReport].threads.count > 0) {
            crashedThreadInfo = [[self crashReport].threads objectAtIndex:0];
        }
    }
    
    if ([self crashReport].hasExceptionInfo) {
        PLCrashReportExceptionInfo *exceptionInfo = [self crashReport].exceptionInfo;
        [BugSenseSymbolicator retainSymbolsForStackFrames:exceptionInfo.stackFrames inReport:[self crashReport]];
    } else {
        [BugSenseSymbolicator retainSymbolsForStackFrames:crashedThreadInfo.stackFrames inReport:[self crashReport]];
    }
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (void) processCrashReport {
    NSLog(kProcessingMsgString);
    
    NSLog(kCrashMsgString, [self crashReport].systemInfo.timestamp, [self crashReport].signalInfo.name, 
          [self crashReport].signalInfo.code, [self crashReport].signalInfo.address);
    
    // Preparing the JSON string
    NSData *jsonData = [self JSONDataFromCrashReport:[self crashReport]];
    if (!jsonData) {
        NSLog(kJSONErrorString);
        return;
    }
    
    // Send the JSON string to the BugSense servers
    [self postJSONData:jsonData];
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (void) initiateReportingProcess {
    NSError *error = nil;
    
    PLCrashReporterCallbacks cb = {
        .version = 0,
        .context = (void *) 0xABABABAB,
        .handleSignal = post_crash_callback
    };
    [[self crashReporter] setCrashCallbacks:&cb];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        if ([[self crashReporter] hasPendingCrashReport]) {
            [self processCrashReport];
        }
    });
    
    if (![[self crashReporter] enableCrashReporterAndReturnError:&error]) {
        NSLog(@"BugSense --> Error: Could not enable crash reporterd due to: %@", error);
    } else {
        if (error != nil) {
            NSLog(kWarningString, error);
        }
    }
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (NSData *) JSONDataFromCrashReport:(PLCrashReport *)report {
    if (!report) {
        return nil;
    }
    
    @try {
        NSLog(@"BugSense --> Generating JSON data from crash report...");
    
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
        [application_environment setObject:[UIDevice currentDevice].model forKey:@"phone"];
    
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
        if (_userDictionary) {
            [request setObject:_userDictionary forKey:@"custom_data"];
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
        NSLog(@"BugSense --> Something unusual happened during the generation of JSON data");
        return nil;
    }
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (BOOL) postJSONData:(NSData *)jsonData {
    if (!jsonData) {
        NSLog(@"BugSense --> No JSON data was given to post.");
        return NO;
    } else {
        NSURL *bugsenseURL = [NSURL URLWithString:BUGSENSE_REPORTING_SERVICE_URL];
        NSMutableURLRequest *bugsenseRequest = [[[NSMutableURLRequest alloc] initWithURL:bugsenseURL 
            cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:10.0f] autorelease];
        [bugsenseRequest setHTTPMethod:@"POST"];
        [bugsenseRequest setValue:_APIKey forHTTPHeaderField:BUGSENSE_HEADER];
        [bugsenseRequest setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
        
        NSMutableData *postData = [NSMutableData data];
        [postData appendData:[@"data=" dataUsingEncoding:NSUTF8StringEncoding]];
        [postData appendData:jsonData];
        [bugsenseRequest setHTTPBody:postData];
        
        // This version employs blocks so this is only working under iOS 4.0+.
        /*AFHTTPRequestOperation *operation = 
            [AFHTTPRequestOperation operationWithRequest:bugsenseRequest 
                completion:^(NSURLRequest *request, NSHTTPURLResponse *response, NSData *data, NSError *error) {
                    NSLog(@"BugSense --> Server responded with: \nstatus code:%i\nheader fields: %@", 
                        response.statusCode, response.allHeaderFields);
                    if (error) {
                        NSLog(@"BugSense --> Error: %@", error);
                    } else {
                        BOOL statusCodeAcceptable = [[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(200, 100)] 
                                                     containsIndex:[response statusCode]];
                        if (statusCodeAcceptable) {
                            [[self crashReporter] purgePendingCrashReport];
                            [BugSenseSymbolicator clearSymbols];
                        }
                    }
            }];*/
        
        BSAFHTTPRequestOperation *operation = [BSAFHTTPRequestOperation operationWithRequest:bugsenseRequest 
                                                                                    observer:self];
        
        /// add operation to queue
        [[NSOperationQueue mainQueue] addOperation:operation];

        NSLog(@"BugSense --> Posting JSON data...");
        
        return YES;
    }
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (void) observeValueForKeyPath:(NSString *)keyPath 
                       ofObject:(id)object 
                         change:(NSDictionary *)change 
                        context:(void *)context {
    if ([keyPath isEqualToString:@"isFinished"] && [object isKindOfClass:[BSAFHTTPRequestOperation class]]) {
        BSAFHTTPRequestOperation *operation = object;
        NSLog(@"BugSense --> Server responded with status code: %i", operation.response.statusCode);
        if (operation.error) {
            NSLog(@"BugSense --> Error: %@", operation.error);
        } else {
            BOOL statusCodeAcceptable = [[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(200, 100)] 
                                         containsIndex:[operation.response statusCode]];
            if (statusCodeAcceptable) {
                [[self crashReporter] purgePendingCrashReport];
                [BugSenseSymbolicator clearSymbols];
            }
        }
        
        _operationCompleted = YES;
    }
}

@end
