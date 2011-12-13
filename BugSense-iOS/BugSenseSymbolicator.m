/*
 
 BugSenseSymbolicator.m
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

#import "BugSenseSymbolicator.h"
#include <dlfcn.h>

#define kSymbolsProcessStartedMsg   @"BugSense --> Symbols are being retained..."
#define kSymbolsProcessCompletedMsg @"BugSense --> Symbols have been retained."
#define kSymbolsErrorMsg            @"BugSense --> Error while retaining symbols!"
#define kSymbolsDataErrorMsg        @"BugSense --> Symbols data error: %@!"

static NSString *BUGSENSE_CACHE_DIR = @"com.bugsense.crashcontroller.symbols";
static NSString *BUGSENSE_LIVE_SYMBOLS = @"live_report_symbols.plist";

@implementation BugSenseSymbolicator

static NSMutableDictionary *symbolDictionary = nil;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
+ (NSString *) symbolsDirectory {
    NSBundle *mainBundle = [NSBundle mainBundle];
    NSString *mainBundleIdentifier = [mainBundle bundleIdentifier];
    
    NSString *appPath = [mainBundleIdentifier stringByReplacingOccurrencesOfString:@"/" withString:@"_"];

    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *cacheDir = [paths objectAtIndex: 0];
    
    return [[cacheDir stringByAppendingPathComponent:BUGSENSE_CACHE_DIR] stringByAppendingPathComponent:appPath];
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
+ (BOOL) populateSymbolsDirectoryAndReturnError:(NSError **)error {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSDictionary *attributes = [NSDictionary dictionaryWithObject:[NSNumber numberWithUnsignedLong:0755] 
                                                           forKey:NSFilePosixPermissions];
    
    if (![fileManager fileExistsAtPath:[self symbolsDirectory]] &&
        ![fileManager createDirectoryAtPath:[self symbolsDirectory] withIntermediateDirectories:YES 
                                 attributes:attributes error:error]) {
        return NO;
    }
    
    return YES;
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
+ (BOOL) retainSymbolsForStackFrames:(NSArray *)stackFrames inReport:(PLCrashReport *)report {
    NSLog(kSymbolsProcessStartedMsg);
    
    if ([self populateSymbolsDirectoryAndReturnError:NULL]) {
        if (symbolDictionary) {
            [symbolDictionary removeAllObjects];
            [symbolDictionary release];
        }
        symbolDictionary = [[NSMutableDictionary alloc] init];
        
        for (PLCrashReportStackFrameInfo *frameInfo in stackFrames) {
            Dl_info theInfo;
            if ((dladdr((void *)(uintptr_t)frameInfo.instructionPointer, &theInfo) != 0) && theInfo.dli_sname != NULL) {
                NSString *symbol = [NSString stringWithCString:theInfo.dli_sname encoding:NSUTF8StringEncoding];
                NSNumber *pcOffset = 
                    [NSNumber numberWithUnsignedInt:(frameInfo.instructionPointer - (uint64_t)theInfo.dli_saddr)];
                [symbolDictionary setObject:[NSArray arrayWithObjects:symbol, pcOffset, nil]
                                     forKey:[NSString stringWithFormat:@"%i",(uintptr_t)frameInfo.instructionPointer]];
            }
        }
        
        NSError *error = nil;
        NSString *plistPath = [[self symbolsDirectory] stringByAppendingPathComponent:BUGSENSE_LIVE_SYMBOLS];
        NSData *plistData = [NSPropertyListSerialization dataWithPropertyList:symbolDictionary 
                                                                       format:NSPropertyListXMLFormat_v1_0
                                                                      options:0
                                                                        error:&error];
        if (plistData) {
            if ([plistData writeToFile:plistPath atomically:YES]) {
                NSLog(kSymbolsProcessCompletedMsg);
                return YES;
            } else {
                NSLog(kSymbolsErrorMsg);
                return NO;
            }
        } else {
            NSLog(kSymbolsDataErrorMsg, error);
            [error release];
            return NO;
        }
    } else {
        return NO;
    }
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
+ (void) clearSymbols {
    [[NSFileManager defaultManager] removeItemAtPath:[self symbolsDirectory] error:NULL];
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
+ (NSArray *) symbolAndOffsetForInstructionPointer:(uint64_t)instructionPointer {
    if (!symbolDictionary) {
        NSError *error = nil;
        NSString *plistPath = [[self symbolsDirectory] stringByAppendingPathComponent:BUGSENSE_LIVE_SYMBOLS];
        
        if (![[NSFileManager defaultManager] fileExistsAtPath:plistPath]) {
            return nil;
        }
                    
        NSData *plistXML = [[NSFileManager defaultManager] contentsAtPath:plistPath];
        symbolDictionary = [(NSDictionary *)[NSPropertyListSerialization propertyListWithData:plistXML 
            options:NSPropertyListMutableContainersAndLeaves format:NULL error:&error] mutableCopy];
        if (!symbolDictionary) {
            NSLog(@"Error reading plist: %@", error);
        }
    }
    
    if (symbolDictionary) {
        return [symbolDictionary objectForKey:[NSString stringWithFormat:@"%i", instructionPointer]];
    } else {
        return nil;
    }
}

@end
