//
//  AppDelegate.m
//  SampleProject
//
//  Created by Tim Johnsen on 9/19/15.
//  Copyright © 2015 tijo. All rights reserved.
//

#import "AppDelegate.h"
#import "TJImageCache.h"
#import "ViewController.h"

@interface AppDelegate ()

@end

@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    [TJImageCache configureWithDefaultRootPath];
    
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.backgroundColor = [UIColor whiteColor];
    self.window.rootViewController = [[ViewController alloc] init];
    [self.window makeKeyAndVisible];
    return YES;
}

@end
