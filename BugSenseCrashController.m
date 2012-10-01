/*
 
 BugSenseCrashController.m
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

#include <dlfcn.h>
#include <execinfo.h>

#import "BugSenseCrashController.h"
#import "BugSenseSymbolicator.h"
#import "BugSenseJSONGenerator.h"
#import "BugSenseDataDispatcher.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "CrashReporter.h"
#import "PLCrashReportTextFormatter.h"
#import "NSMutableURLRequest+AFNetworking.h"
#import "JSONKit.h"

#define kLoadErrorString                @"BugSense --> Error: Could not load crash report data due to: %@"
#define kParseErrorString               @"BugSense --> Error: Could not parse crash report due to: %@"
#define kJSONErrorString                @"BugSense --> Could not prepare JSON crash report string."
#define kWarningString                  @"BugSense --> Warning: %@"
#define kProcessingMsgString            @"BugSense --> Processing crash report..."
#define kCrashMsgString                 @"BugSense --> Crashed on %@, with signal %@ (code %@, address=0x%" PRIx64 ")"
#define kCrashReporterErrorString       @"BugSense --> Error: Could not enable crash reporting due to: %@"
#define kNewVersionAlertMsgString       @"BugSense --> New version alert shown."

#define kStandardUpdateTitle            NSLocalizedString(@"Update available", nil)
#define kStandardUpdateAlertFormat      NSLocalizedString(@"There is an update for %@, that fixes the crash you've just\
experienced. Do you want to get it from the App Store?", nil)
#define kAppTitleString                 [[NSBundle mainBundle].infoDictionary objectForKey:@"CFBundleDisplayName"]
#define kCancelText                     NSLocalizedString(@"Cancel", nil)
#define kOKText                         NSLocalizedString(@"Update", nil)

#define kDataKey                        @"data"
#define kContentTitleKey                @"contentTitle"
#define kContentTextKey                 @"contentText"
#define kURLKey                         @"url"

#pragma mark - Private interface
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
@interface BugSenseCrashController (Private)

- (PLCrashReporter *) crashReporter;
- (PLCrashReport *) crashReport;
- (NSString *) currentIPAddress;
- (NSString *) device;
- (dispatch_queue_t) operationsQueue;

void post_crash_callback(siginfo_t *info, ucontext_t *uap, void *context);
- (void) performPostCrashOperations;

- (void) initiateReporting;

- (id) initWithAPIKey:(NSString *)bugSenseAPIKey 
       userDictionary:(NSDictionary *)userDictionary 
      sendImmediately:(BOOL)immediately;

- (void) retainSymbolsForReport:(PLCrashReport *)report;
- (void) processCrashReport:(PLCrashReport *)report;

@end


#pragma mark - Implementation
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
@implementation BugSenseCrashController {
    dispatch_queue_t    _operationsQueue; 
    
    BOOL                _operationCompleted;
    
    PLCrashReporter     *_crashReporter;
    PLCrashReport       *_crashReport;
    
    NSURL               *_storeLinkURL;
}

static BugSenseCrashController *_sharedCrashController = nil;
static NSDictionary            *_userDictionary;
static NSString                *_APIKey;
static BOOL                    _immediately;

#pragma mark - Ivar accessors
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
- (dispatch_queue_t) operationsQueue {
    if (!_operationsQueue) {
        _operationsQueue = dispatch_queue_create("com.bugsense.operations", NULL);
    }
    
    return _operationsQueue;
}


#pragma mark - Crash callback function
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
void post_crash_callback(siginfo_t *info, ucontext_t *uap, void *context) {
    [_sharedCrashController performSelectorOnMainThread:@selector(retainSymbolsForReport:) 
                                             withObject:[_sharedCrashController crashReport] 
                                          waitUntilDone:YES];
    [_sharedCrashController performSelectorOnMainThread:@selector(performPostCrashOperations) 
                                             withObject:nil 
                                          waitUntilDone:YES];
}


#pragma mark - Crash callback method
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (void) performPostCrashOperations {    
    if (_immediately) {
        if ([[self crashReporter] hasPendingCrashReport]) {
            [self processCrashReport:[self crashReport]];
        }
        
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
}


#pragma mark - Logging method
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
+ (BOOL) logException:(NSException *)exception withTag:(NSString *)tag {
    NSData *jsonData = [BugSenseJSONGenerator JSONDataFromException:exception userDictionary:_userDictionary 
                                                                tag:tag];
    if (!jsonData) {
        NSLog(kJSONErrorString);
        return NO;
    }
    
    // Send the JSON string to the BugSense servers
    [BugSenseDataDispatcher postJSONData:jsonData withAPIKey:_APIKey delegate:nil showFeedback:NO];
    
    return YES;
}


#pragma mark - Reporting method
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (void) initiateReporting {
    NSError *error = nil;
    
    PLCrashReporterCallbacks cb = {
        .version = 0,
        .context = (void *) 0xABABABAB,
        .handleSignal = post_crash_callback
    };
    [[self crashReporter] setCrashCallbacks:&cb];
    
    if ([[self crashReporter] hasPendingCrashReport]) {
        dispatch_async(dispatch_get_current_queue(), ^{
            [self processCrashReport:[self crashReport]];
        });
    }
    
    if (![[self crashReporter] enableCrashReporterAndReturnError:&error]) {
        NSLog(kCrashReporterErrorString, error);
    } else {
        if (error != nil) {
            NSLog(kWarningString, error);
        }
    }
}


#pragma mark - Singleton lifecycle
#ifndef __clang_analyzer__
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
+ (BugSenseCrashController *) sharedInstanceWithBugSenseAPIKey:(NSString *)bugSenseAPIKey 
                                                userDictionary:(NSDictionary *)userDictionary
                                               sendImmediately:(BOOL)immediately {
    static dispatch_once_t oncePredicate;
    dispatch_once(&oncePredicate, ^{
        if (!_sharedCrashController) {
            [[self alloc] initWithAPIKey:bugSenseAPIKey userDictionary:userDictionary sendImmediately:immediately];
            [_sharedCrashController initiateReporting];
        }
    });
    
    return _sharedCrashController;
}
#endif


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
            return _sharedCrashController;
        }
    }
    return nil;
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
    dispatch_release(_operationsQueue);
    
    [_APIKey release];
    [_userDictionary release];
    [_crashReporter release];
    [_crashReport release];
    
    [super dealloc];
}


#pragma mark - Process methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (void) retainSymbolsForReport:(PLCrashReport *)report {
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
    
    if (report.hasExceptionInfo) {
        PLCrashReportExceptionInfo *exceptionInfo = report.exceptionInfo;
        [BugSenseSymbolicator retainSymbolsForStackFrames:exceptionInfo.stackFrames inReport:report];
    } else {
        [BugSenseSymbolicator retainSymbolsForStackFrames:crashedThreadInfo.stackFrames inReport:report];
    }
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (void) processCrashReport:(PLCrashReport *)report  {
    NSLog(kProcessingMsgString);
    
    NSLog(kCrashMsgString, report.systemInfo.timestamp, report.signalInfo.name, report.signalInfo.code, 
          report.signalInfo.address);
    
    // Preparing the JSON string
    NSData *jsonData = [BugSenseJSONGenerator JSONDataFromCrashReport:report userDictionary:_userDictionary];
    if (!jsonData) {
        NSLog(kJSONErrorString);
        return;
    }
    
    // Send the JSON string to the BugSense servers
    [BugSenseDataDispatcher postJSONData:jsonData withAPIKey:_APIKey delegate:self showFeedback:YES];
}

@end


@implementation BugSenseCrashController (Delegation)

- (void) showNewVersionAlertViewWithData:(NSData *)data {
    if (data) {
        id dataObject = [[[JSONDecoder decoder] objectWithData:data] objectForKey:kDataKey];
        
        // Keeping this for testing
        /*
         NSString *text = [NSString stringWithFormat:kStandardUpdateAlertFormat, kAppTitleString];
         dataObject = [NSDictionary dictionaryWithObjectsAndKeys:kStandardUpdateTitle, kContentTitleKey, text, 
         kContentTextKey, @"http://www.bugsense.com", kURLKey, nil];
         */
        
        if ([dataObject isKindOfClass:[NSDictionary class]]) {
            _storeLinkURL = [[NSURL URLWithString:(NSString *)[(NSDictionary *)dataObject objectForKey:kURLKey]] retain];
            NSString *contentText = [(NSDictionary *)dataObject objectForKey:kContentTextKey];
            NSString *contentTitle = [(NSDictionary *)dataObject objectForKey:kContentTitleKey];
            
            if (_storeLinkURL && contentText && contentTitle) {
                UIAlertView *newVersionAlertView = [[[UIAlertView alloc] initWithTitle:contentTitle 
                                                                               message:contentText 
                                                                              delegate:self 
                                                                     cancelButtonTitle:kCancelText 
                                                                     otherButtonTitles:kOKText, nil] autorelease];
                [newVersionAlertView show];
                NSLog(kNewVersionAlertMsgString);
            } else {
                _operationCompleted = YES;
            }
        } else {
            _operationCompleted = YES;
        }
    } else {
        _operationCompleted = YES;
    }
}

- (void) alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    switch (buttonIndex) {
        case 0:
            [alertView dismissWithClickedButtonIndex:0 animated:YES];
            break;
        case 1:
            if (_storeLinkURL) {
                [[UIApplication sharedApplication] openURL:_storeLinkURL];
            }
            [alertView dismissWithClickedButtonIndex:1 animated:YES];
            break;
        default:
            break;
    }
    
    _operationCompleted = YES;
}

#pragma mark - Delegate method (in category)
- (void) operationCompleted:(BOOL)statusCodeAcceptable withData:(NSData *)data {
    if (statusCodeAcceptable) {
        [[self crashReporter] purgePendingCrashReport];
        [BugSenseSymbolicator clearSymbols];
        
        if (data) {
            [self showNewVersionAlertViewWithData:data];
        } else {
            _operationCompleted = YES;
        }
    } else {
        _operationCompleted = YES;
    }
}

@end
