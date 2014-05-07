//
//  TOAppDelegate.m
//  TODirectoryWatcher
//
//  Created by Tim Oliver on 6/05/2014.
//  Copyright (c) 2014 TimOliver. All rights reserved.
//

#import "TOAppDelegate.h"
#import "TOViewController.h"

@implementation TOAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.rootViewController = [[UINavigationController alloc] initWithRootViewController:[TOViewController new]];
    [self.window makeKeyAndVisible];
    
    return YES;
}

@end
