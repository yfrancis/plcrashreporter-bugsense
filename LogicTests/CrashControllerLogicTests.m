/*
 
 CrashControllerLogicTests.m
 BugSense-iOS
 
 Copyright (c) 2011 BugSense Inc.
 
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

#import "CrashControllerLogicTests.h"

#import "BugSenseCrashController.h"
#import "BugSenseCrashController+Private.h"

@implementation CrashControllerLogicTests

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (void) testSingleton {
    STAssertNotNil([BugSenseCrashController sharedInstanceWithBugSenseAPIKey:@"0000000"], 
        @"+sharedInstance returned nil");
    
    STAssertEqualObjects([BugSenseCrashController sharedInstanceWithBugSenseAPIKey:@"0000000"],
        [BugSenseCrashController sharedInstanceWithBugSenseAPIKey:@"1111111"],
            @"+sharedInstance doesn't return a singleton object");
    
    BugSenseCrashController *crashController = [BugSenseCrashController sharedInstanceWithBugSenseAPIKey:@"0000000"];
    [crashController release];
    STAssertNotNil(crashController, @"The singleton can be released");
}

@end
