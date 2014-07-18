//
//  TODocumentsDirectoryWatcher.m
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

#import "TODocumentsDirectoryWatcher.h"

/* Permanent file name of cache file that holds the current state of the Documents directory */
static NSString * const kTODocumentsDirectoryWatcherCacheFileName = @"com.timoliver.documentsDirectoryCache.json";

/* NSNotification Message Names */
NSString *const TODocumentsDirectoryWatcherDidStartLoadingFiles = @"TODocumentsDirectoryWatcherDidStartLoadingFiles";
NSString *const TODocumentsDirectoryWatcherDidEndLoadingFiles   = @"TODocumentsDirectoryWatcherDidEndLoadingFiles";
NSString *const TODocumentsDirectoryWatcherDidAddFiles          = @"TODocumentsDirectoryWatcherDidAddFiles";
NSString *const TODocumentsDirectoryWatcherDidRenameFiles       = @"TODocumentsDirectoryWatcherDidRenameFiles";
NSString *const TODocumentsDirectoryWatcherDidDeleteFiles       = @"TODocumentsDirectoryWatcherDidDeleteFiles";

/* Names of keys for each file in the cache */
static NSString * const kCacheKeyFileName           = @"FileName";
static NSString * const kCacheKeyFileIDNumber       = @"FileIDNumber";
static NSString * const kCacheKeyFileSize           = @"FileSize";

/* Private interface */
@interface TODocumentsDirectoryWatcher ()

/* File import polling is currently in progress */
@property (nonatomic, assign, readwrite) BOOL isLoading;

/* Serial queue to handle all tasks in this controller */
@property (nonatomic, strong) dispatch_queue_t watcherQueue;

/* The main GCD Source in charge of monitoring the documents directory */
@property (nonatomic, strong) dispatch_source_t dispatchSource;

/* A snapshot of the Documents folder, with all files confirmed to have been completely imported. */
@property (nonatomic, strong) NSMutableDictionary *documentsFolderCache;

/* A set of potentially new files, that may not have finished copying yet */
@property (nonatomic, strong) NSMutableDictionary *pendingFiles;

/* A set of files contained inside new directories that may not have finished copying. */
@property (nonatomic, strong) NSMutableDictionary *pendingSubdirectoryFiles;

/* If scanning for file changes is temporarily paused */
@property (nonatomic, assign) BOOL isPaused;

/* A timer for polling when to check for importing files */
@property (nonatomic, strong) NSTimer *fileImportTimer;

/* System directory constants */
+ (NSString *)applicationCachePath;
+ (NSString *)applicationDocumentsPath;
+ (NSString *)cachedDataFilePath;

/* Creates a new GCD Source object. */
- (dispatch_source_t)createDispatchSourceForDirectoryAtPath:(NSString *)directory;

/* Called whenever an update event is fired. */
- (void)handleDocumentsDirectoryUpdateEvent;

/* Called by the timer to check the state of the new files */
- (void)importTimerFired;

/* Given a directory in the Documents folder, check its contents for any files that may have changed. */
- (BOOL)contentsHaveChangedInSubdirectory:(NSString *)subdirectoryPath;

@end

@implementation TODocumentsDirectoryWatcher

#pragma mark - Object Creation -
+ (TODocumentsDirectoryWatcher *)sharedWatcher
{
    static TODocumentsDirectoryWatcher *sharedWatcher;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedWatcher = [TODocumentsDirectoryWatcher new];
    });
    return sharedWatcher;
}

- (void)dealloc
{
    [self stop];
}

#pragma mark - Starting/Stopping Watch State -
- (dispatch_source_t)createDispatchSourceForDirectoryAtPath:(NSString *)directory
{
    int dirFD = open([directory fileSystemRepresentation], O_EVTONLY);
    if (dirFD < 0)
        return nil;
    
    // Get the main thread's serial dispatch queue (since we'll be updating the UI)
    dispatch_queue_t queue = dispatch_get_main_queue();
    if (!queue) {
        close(dirFD);
        return nil;
    }
    
    // Create a dispatch source to monitor the directory for writes
    dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, // Watch for certain events on the VNODE spec'd by the second (handle) argument
                                                      dirFD,                      // The handle to watch (the directory FD)
                                                      DISPATCH_VNODE_WRITE,       // The events to watch for on the VNODE spec'd by handle (writes)
                                                      queue);                     // The queue to which the handler block will ultimately be dispatched
    
    if (!source) {
        close(dirFD);
        return nil;
    }
    
    // Set the block to be submitted in response to source cancellation
    dispatch_source_set_cancel_handler(source, ^{close(dirFD);});
    
    return source;
}

//http://www.mlsite.net/blog/?p=2655
- (void)start
{
    if (self.isPaused)
        self.isPaused = NO;
    
    if (self.dispatchSource != NULL)
        return;
    
    // Fetch pathname of the directory to monitor
	NSString *documentsPath = [TODocumentsDirectoryWatcher applicationDocumentsPath];
    
	// Open an event-only file descriptor associated with the directory
    self.dispatchSource = [self createDispatchSourceForDirectoryAtPath:documentsPath];
    if (self.dispatchSource == nil)
        return;
    
	// Set the block to be submitted in response to an event
	dispatch_source_set_event_handler(self.dispatchSource, ^{[self handleDocumentsDirectoryUpdateEvent];});
    
	// Unsuspend the source s.t. it will begin submitting blocks
	dispatch_resume(self.dispatchSource);
    
    //kickstart the first event
    [self handleDocumentsDirectoryUpdateEvent];
}

- (void)pause
{
    self.isPaused = YES;
}

- (void)stop
{
    if (self.dispatchSource) {
		// Stop the source from submitting further blocks (and close the underlying FD)
		dispatch_source_cancel(self.dispatchSource);
        
		// Release the source
		self.dispatchSource = NULL;
	
        //remove all data stores
        self.documentsFolderCache = nil;
        self.pendingFiles = nil;
        
        //cancel the timer
        [self.fileImportTimer invalidate];
        self.fileImportTimer = nil;
    }
}

#pragma mark - Update Event Handling -
- (void)handleDocumentsDirectoryUpdateEvent
{
    if (self.isPaused)
        return;
    
    //create the watcher queue
    if (self.watcherQueue == NULL) {
        self.watcherQueue = dispatch_queue_create("com.timoliver.documentsDirectoryWatcherQueue", DISPATCH_QUEUE_SERIAL);
    }
    
    //offload to the serial queue to minimize UI locking
    dispatch_async(self.watcherQueue, ^{
        //Keep track if we make a change that needs to be persisted to disk
        BOOL diskWriteNecessary = NO;
        
        NSString *documentsPath = [TODocumentsDirectoryWatcher applicationDocumentsPath];
        
        //create the store to hold pending files in the Documents directory
        if (self.pendingFiles == nil)
            self.pendingFiles = [NSMutableDictionary dictionary];
        
        //create the store to hold all first-level subdirectory files
        if (self.pendingSubdirectoryFiles == nil)
            self.pendingSubdirectoryFiles = [NSMutableDictionary dictionary];
        
        //import the last snapshot cache if we haven't already got it
        if (self.documentsFolderCache == nil) {
            NSData *data = [NSData dataWithContentsOfFile:[TODocumentsDirectoryWatcher cachedDataFilePath]];
            if (data)
                self.documentsFolderCache = [[NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:nil] mutableCopy];
            
            if (data == nil || self.documentsFolderCache == nil)
                self.documentsFolderCache = [NSMutableDictionary new];
        }
        
        //get a list of the current files in the Documents folder
        NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:documentsPath error:nil];
        
        //loop though all of these files to see if any aren't already in the cached snapshot
        NSMutableSet *possibleNewFiles = [NSMutableSet set];
        for (NSString *file in files) {
            if (self.documentsFolderCache[file] == nil)
                [possibleNewFiles addObject:file];
        }
        
        //add each of the new files to the pending list
        for (NSString *newFile in possibleNewFiles) {
            if (self.pendingFiles[newFile] == nil) {
                NSString *filePath = [documentsPath stringByAppendingPathComponent:newFile];
                NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:nil];
                if (attributes == nil)
                    continue;
                
                NSMutableDictionary *newFileAttributes = [NSMutableDictionary dictionary];
                newFileAttributes[kCacheKeyFileName]         = newFile;
                newFileAttributes[kCacheKeyFileIDNumber]     = @(attributes.fileSystemFileNumber);
                newFileAttributes[kCacheKeyFileSize]         = @(attributes.fileSize);
                
                self.pendingFiles[newFile] = newFileAttributes;
            }
        }
        
        //loop through the new files and compare file system IDs to see if any of the new files are simply
        //renamed old files
        NSMutableDictionary *renamedFiles = [NSMutableDictionary dictionary];
        for (NSString *cacheKey in self.documentsFolderCache.allKeys) {
            NSDictionary *snapshotFile = self.documentsFolderCache[cacheKey];
            
            for (NSString *newFileKey in self.pendingFiles.allKeys) {
                if ([snapshotFile[kCacheKeyFileIDNumber] integerValue] == [self.pendingFiles[newFileKey][kCacheKeyFileIDNumber] integerValue])
                    renamedFiles[snapshotFile[kCacheKeyFileName]] = newFileKey;
            }
        }
        
        //for any renamed file, pull it out of the snapshot cache, rename it, and re-insert it
        if (renamedFiles.count > 0) {
            for (NSString *renameKey in renamedFiles.allKeys) {
                NSMutableDictionary *snapshotFile = [self.documentsFolderCache[renameKey] mutableCopy];
                [self.documentsFolderCache removeObjectForKey:renameKey];
                snapshotFile[kCacheKeyFileName] = renamedFiles[renameKey];
                self.documentsFolderCache[renamedFiles[renameKey]] = snapshotFile;
                
                [self.pendingFiles removeObjectForKey:renamedFiles[renameKey]];
                
                diskWriteNecessary = YES;
            }
            
            //post a notification about the file renaming
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:TODocumentsDirectoryWatcherDidRenameFiles object:nil userInfo:@{@"files":renamedFiles}];
            });
        }
        
        //check for any files that were deleted
        NSMutableArray *deletedFiles = [NSMutableArray array];
        for (NSString *snapshotFileName in self.documentsFolderCache.allKeys) {
            NSString *filePath = [documentsPath stringByAppendingPathComponent:snapshotFileName];
            if ([[NSFileManager defaultManager] fileExistsAtPath:filePath] == NO) {
                [deletedFiles addObject:snapshotFileName];
            }
        }
        
        //remove any deleted files from the snapshot
        if (deletedFiles.count > 0) {
            for (NSString *deletedFile in deletedFiles)
                [self.documentsFolderCache removeObjectForKey:deletedFile];
            
            diskWriteNecessary = YES;
            
            //post a notification about the file renaming
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:TODocumentsDirectoryWatcherDidDeleteFiles object:nil userInfo:@{@"files":deletedFiles}];
            });
        }
        
        //if a disk write was necessary, do it now
        if (diskWriteNecessary) {
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:self.documentsFolderCache options:kNilOptions error:nil];
            [jsonData writeToFile:[TODocumentsDirectoryWatcher cachedDataFilePath] atomically:YES];
        }
        
        //if there are pending files left, kickstart a polling timer
        if (self.pendingFiles.count > 0 && self.fileImportTimer == nil) {
            dispatch_async(dispatch_get_main_queue(), ^{
                //kickstart a polling timer
                self.fileImportTimer = [NSTimer scheduledTimerWithTimeInterval:5.0f target:self selector:@selector(importTimerFired) userInfo:nil repeats:YES];
            
                self.isLoading = YES;
                
                //post a notification to say we've started loading files
                [[NSNotificationCenter defaultCenter] postNotificationName:TODocumentsDirectoryWatcherDidStartLoadingFiles object:nil];
            });
        } else if (self.pendingFiles.count == 0) {
            self.pendingFiles = nil;
            self.documentsFolderCache = nil;
        }
    });
}

- (void)importTimerFired
{
    dispatch_async(self.watcherQueue, ^{
        NSString *documentsPath = [TODocumentsDirectoryWatcher applicationDocumentsPath];
        
        //compare each pending file to see if their size has changed at all
        BOOL fileSizeChanged = NO;
        for (NSString *pendingFileName in self.pendingFiles) {
            //grab the attributes of the file and see if the size has changed at all since last poll
            NSString *filePath = [documentsPath stringByAppendingPathComponent:pendingFileName];
            NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:nil];
            if (attributes.fileSize > [self.pendingFiles[pendingFileName][kCacheKeyFileSize] integerValue])
                fileSizeChanged = YES;
            
            //in any case, update the cached version with the current file size
            self.pendingFiles[pendingFileName][kCacheKeyFileSize] = @(attributes.fileSize);
            
            //====================================================
            
            //if the file is a directory, take a snapshot of its contents and see if they've changed
            if ([attributes.fileType isEqualToString:NSFileTypeDirectory])
                fileSizeChanged = (fileSizeChanged || [self contentsHaveChangedInSubdirectory:filePath]);
        }
        
        //If NONE of the files have changed, then they must have finished importing
        if (fileSizeChanged == NO) {
            //save a copy of the file names
            NSArray *fileNames = [self.pendingFiles.allKeys copy];
            fileNames = [fileNames sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
                return [(NSString *)obj1 compare:(NSString *)obj2 options:NSNumericSearch];
            }];
            
            //add the pending files to the main snapshot
            [self.documentsFolderCache addEntriesFromDictionary:self.pendingFiles];
            self.pendingFiles = nil;
            
            //save the state to disk
            if (self.documentsFolderCache) {
                NSData *data = [NSJSONSerialization dataWithJSONObject:self.documentsFolderCache options:kNilOptions error:nil];
                [data writeToFile:[TODocumentsDirectoryWatcher cachedDataFilePath] atomically:YES];
            }
            else {
                [[NSFileManager defaultManager] removeItemAtPath:[TODocumentsDirectoryWatcher cachedDataFilePath] error:nil];
            }
            
            //clean the data
            self.pendingFiles = nil;
            self.pendingSubdirectoryFiles = nil;
            self.documentsFolderCache = nil;
            
            //cancel the timer
            [self.fileImportTimer invalidate];
            self.fileImportTimer = nil;
            
            //post the notification
            dispatch_async(dispatch_get_main_queue(), ^{
                if (fileNames)
                    [[NSNotificationCenter defaultCenter] postNotificationName:TODocumentsDirectoryWatcherDidAddFiles object:nil userInfo:@{@"files":fileNames}];

                self.isLoading = NO;
                
                //post a notification to say the files have finished loading
                [[NSNotificationCenter defaultCenter] postNotificationName:TODocumentsDirectoryWatcherDidEndLoadingFiles object:nil];
            });
        }
    });
}

- (BOOL)contentsHaveChangedInSubdirectory:(NSString *)subdirectoryPath
{
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:subdirectoryPath error:nil];
    if (files.count == 0)
        return NO;
    
    //If not done already, build a snapshot of the current directory contents
    NSString *folderName = [subdirectoryPath lastPathComponent];
    if (self.pendingSubdirectoryFiles[folderName] == nil)
        self.pendingSubdirectoryFiles[folderName] = [NSMutableDictionary dictionary];
    
    NSMutableDictionary *folderContentsSnapshot = (NSMutableDictionary *)self.pendingSubdirectoryFiles[folderName];
    
    //loop through each file, and check its size
    for (NSString *file in files) {
        NSString *filePath = [subdirectoryPath stringByAppendingPathComponent:file];
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:nil];
        if (attributes == nil)
            continue;
        
        //create the file size for the first time (and skip the check as it's pointless for now)
        NSNumber *fileID = @(attributes.fileSystemFileNumber);
        if (folderContentsSnapshot[fileID] == nil) {
            folderContentsSnapshot[fileID] = @(attributes.fileSize);
            continue;
        }
        
        //check to see if since the last poll, the size of this file has changed
        if ([(NSNumber *)folderContentsSnapshot[fileID] unsignedLongLongValue] == attributes.fileSize) {
            return NO;
        }

        //update the snapshot with the new filesize
        folderContentsSnapshot[fileID] = @(attributes.fileSize);
    }
    
    return YES;
}

#pragma mark - Static Methods - 
+ (NSString *)cachedDataFilePath
{
    return [[TODocumentsDirectoryWatcher applicationCachePath] stringByAppendingPathComponent:kTODocumentsDirectoryWatcherCacheFileName];
}

+ (NSString *)applicationCachePath
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *basePath = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
    return basePath;
}

+ (NSString *)applicationDocumentsPath
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *basePath = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
    return basePath;
}

+ (void)clearCachedData
{
    if ([[NSFileManager defaultManager] fileExistsAtPath:[TODocumentsDirectoryWatcher cachedDataFilePath]])
        [[NSFileManager defaultManager] removeItemAtPath:[TODocumentsDirectoryWatcher cachedDataFilePath] error:nil];
}

@end
