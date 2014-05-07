//
//  TODocumentsDirectoryWatcher.h
//
//  Copyright 2014 Timothy Oliver. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to
//  deal in the Software without restriction, including without limitation the
//  rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
//  sell copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
//  OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
//  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR
//  IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

#import <Foundation/Foundation.h>

//-------------------------------------------------------------------
//NSNotification Events

/* Notification fired when new files being copied in has been detected. */
extern NSString *const TODocumentsDirectoryWatcherDidStartLoadingFiles;
/* Notification fired when new files have completed being copied in. */
extern NSString *const TODocumentsDirectoryWatcherDidEndLoadingFiles;

/* Notification for when new files have completed being copied in. NSNotification.userInfo[@"files"] contains NSArray of new file names. */
extern NSString *const TODocumentsDirectoryWatcherDidAddFiles;
/* Notification for when renamed files have been detected. NSNotification.userInfo[@"files"] is an NSDictionary in the format of {oldName: newName}. */
extern NSString *const TODocumentsDirectoryWatcherDidRenameFiles;
/* Notification for when deleted files have been detected. NSNotification.userInfo[@"files"] contains NSArray with list of deleted filenames. */
extern NSString *const TODocumentsDirectoryWatcherDidDeleteFiles;

//-------------------------------------------------------------------

/*
* TODocumentsDirectoryWatcher Class Interface
*/
@interface TODocumentsDirectoryWatcher : NSObject

/* Singleton instance of the class */
+ (TODocumentsDirectoryWatcher *)sharedWatcher;

/* Flag for when file copying is active. */
@property (nonatomic, readonly) BOOL isLoading;

/* Begin monitoring the Documents folder for changes. */
- (void)start;

/* Temporarily pause directory monitoring. (Call 'start' again to restart.) */
- (void)pause;

/* Completely stop directory watching and free all resources. */
- (void)stop;

/* Remove the cached data stored to the 'Caches' directory. */
+ (void)clearCachedData;

@end
