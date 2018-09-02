//
//  TJFastImageView.m
//  Opener
//
//  Created by Tim Johnsen on 4/13/17.
//  Copyright © 2017 tijo. All rights reserved.
//

#import "TJFastImageView.h"
#import "TJImageCache.h"

@interface TJFastImageView () <TJImageCacheDelegate>

TJ_FAST_IMAGE_PRIVATE_INTERFACE

@end

@implementation TJFastImageView

- (instancetype)initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame]) {
        [super setBackgroundColor:[UIColor clearColor]];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(invertColorsStatusDidChange:)
                                                     name:UIAccessibilityInvertColorsStatusDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (void)invertColorsStatusDidChange:(NSNotification *)notification
{
    [self setNeedsUpdateImage];
}

TJ_FAST_IMAGE_DEFINITION(image)

@end
