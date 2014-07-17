//
//  TOViewController.m
//  TODirectoryWatcher
//
//  Created by Tim Oliver on 6/05/2014.
//  Copyright (c) 2014 TimOliver. All rights reserved.
//

#import "TOViewController.h"
#import "TODocumentsDirectoryWatcher.h"

static NSString * const kCacheFileName = @"com.timoliver.DirectoryWatcherExampleCache";

@interface TOViewController ()

@property (nonatomic, strong) NSMutableArray *items;

@property (nonatomic, strong) UIBarButtonItem *helpButtonItem;
@property (nonatomic, strong) UIBarButtonItem *loadingBarButtonItem;
@property (nonatomic, strong) UIBarButtonItem *addDirButton;

- (void)filesStartedLoading;
- (void)filesEndedLoading;

- (void)filesWereAdded:(NSNotification *)notification;
- (void)filesWereRenamed:(NSNotification *)notification;
- (void)filesWereDeleted:(NSNotification *)notification;

- (NSString *)documentsDirectory;
- (NSString *)cachesDirectory;
- (NSMutableArray *)loadItemsFromDisk;
- (void)saveItemsToDisk;

- (void)helpButtonItemTapped;
- (void)addDirectoryButtonItemTapped;

@end

@implementation TOViewController

- (id)init
{
    if (self = [super init]) {
        //start the notification watchers
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(filesWereAdded:) name:TODocumentsDirectoryWatcherDidAddFiles object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(filesWereRenamed:) name:TODocumentsDirectoryWatcherDidRenameFiles object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(filesWereDeleted:) name:TODocumentsDirectoryWatcherDidDeleteFiles object:nil];
    
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(filesStartedLoading) name:TODocumentsDirectoryWatcherDidStartLoadingFiles object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(filesEndedLoading) name:TODocumentsDirectoryWatcherDidEndLoadingFiles object:nil];
    }
    
    return self;
}

- (void)dealloc
{
    //remove the notification watchers
    [[NSNotificationCenter defaultCenter] removeObserver:self name:TODocumentsDirectoryWatcherDidAddFiles object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:TODocumentsDirectoryWatcherDidRenameFiles object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:TODocumentsDirectoryWatcherDidDeleteFiles object:nil];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	
    self.items = [self loadItemsFromDisk];
    if (self.items == nil)
        self.items = [NSMutableArray array];
    
    self.title = @"Director Watcher";
    
    UIActivityIndicatorView *loadingView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    [loadingView startAnimating];
    self.loadingBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:loadingView];
    
    self.helpButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Do what?" style:UIBarButtonItemStylePlain target:self action:@selector(helpButtonItemTapped)];
    self.navigationItem.leftBarButtonItem = self.helpButtonItem;
    
    self.addDirButton = [[UIBarButtonItem alloc] initWithTitle:@"+ Dir" style:UIBarButtonItemStylePlain target:self action:@selector(addDirectoryButtonItemTapped)];
    self.navigationItem.rightBarButtonItem = self.addDirButton;
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

    //start the file watcher
    [[TODocumentsDirectoryWatcher sharedWatcher] start];
}

#pragma mark - Button Feedback -
- (void)helpButtonItemTapped
{
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"http://support.apple.com/kb/ht4094"]];
}

- (void)addDirectoryButtonItemTapped
{
    NSInteger directoryNumber = 0;
    NSString *directoryName = nil;
    
    do {
        directoryName = [NSString stringWithFormat:@"Directory %ld", (long)++directoryNumber];
    } while ([[NSFileManager defaultManager] fileExistsAtPath:[[self documentsDirectory] stringByAppendingPathComponent:directoryName]]);
    
    [[NSFileManager defaultManager] createDirectoryAtPath:[[self documentsDirectory] stringByAppendingPathComponent:directoryName]
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
}

#pragma mark - Load Data from disk - 
- (NSMutableArray *)loadItemsFromDisk
{
    NSData *data = [NSData dataWithContentsOfFile:[[self cachesDirectory] stringByAppendingPathComponent:kCacheFileName]];
    if (data == nil)
        return nil;
    
    return [[NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:nil][@"items"] mutableCopy];
}

- (void)saveItemsToDisk
{
    if (self.items.count == 0) {
        [[NSFileManager defaultManager] removeItemAtPath:[[self cachesDirectory] stringByAppendingPathComponent:kCacheFileName] error:nil];
        return;
    }
    
    NSDictionary *jsonData = @{@"items":self.items};
    NSData *data = [NSJSONSerialization dataWithJSONObject:jsonData options:kNilOptions error:nil];
    [data writeToFile:[[self cachesDirectory] stringByAppendingPathComponent:kCacheFileName] atomically:YES];
}

#pragma mark - Notifications -
- (void)filesStartedLoading
{
    self.navigationItem.rightBarButtonItem = self.loadingBarButtonItem;
}

- (void)filesEndedLoading
{
    self.navigationItem.rightBarButtonItem = self.addDirButton;
}

- (void)filesWereAdded:(NSNotification *)notification
{
    NSLog(@"ADDED: %@", notification.userInfo);
    NSArray *files = notification.userInfo[@"files"];
    
    for (NSString *file in files) {
        NSString *filePath = [[self documentsDirectory] stringByAppendingPathComponent:file];
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:nil];
        
        [self.items addObject:@{@"name":file, @"size":@(attributes.fileSize)}];
        [self.tableView insertRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:self.items.count-1 inSection:0]] withRowAnimation:UITableViewRowAnimationRight];
    }
    
    [self saveItemsToDisk];
}

- (void)filesWereRenamed:(NSNotification *)notification
{
    NSLog(@"RENAMED: %@", notification.userInfo);
    NSDictionary *renamedFiles = notification.userInfo[@"files"];
    
    for (NSString *renamedFile in renamedFiles.allKeys) {
        for (NSInteger i = 0; i < self.items.count; i++) {
            NSDictionary *item = self.items[i];
            
            if ([item[@"name"] isEqualToString:renamedFile]) {
                NSMutableDictionary *newItem = [item mutableCopy];
                newItem[@"name"] = renamedFiles[renamedFile];
                [self.items replaceObjectAtIndex:i withObject:newItem];
                [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:i inSection:0]] withRowAnimation:UITableViewRowAnimationNone];
            }
        }
    }
    
    [self saveItemsToDisk];
}

- (void)filesWereDeleted:(NSNotification *)notification
{
    NSLog(@"DELETED: %@", notification.userInfo);
    
    NSArray *files = notification.userInfo[@"files"];
    
    for (NSString *file in files) {
        NSInteger index = 0;
        for (NSDictionary *item in self.items) {
            if ([item[@"name"] isEqualToString:file]) {
                break;
            }
            
            index++;
        }
        
        if (index < self.items.count) {
            [self.items removeObjectAtIndex:index];
            [self.tableView deleteRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:index inSection:0]] withRowAnimation:UITableViewRowAnimationFade];
        }
    }
    
    [self saveItemsToDisk];
}

#pragma mark - UITableView -
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *cellString = @"TableCell";
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:cellString];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellString];
    }
    
    cell.textLabel.text = self.items[indexPath.row][@"name"];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld bytes", (long)[self.items[indexPath.row][@"size"] integerValue]];
    
    return cell;
}

#pragma mark - System -
- (NSString *)documentsDirectory
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *basePath = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
    return basePath;
}

- (NSString *)cachesDirectory
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *basePath = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
    return basePath;
}

@end
