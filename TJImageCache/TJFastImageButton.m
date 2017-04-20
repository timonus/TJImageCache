//
//  TJFastImageButton.m
//  Mastodon
//
//  Created by Tim Johnsen on 4/19/17.
//  Copyright © 2017 Tim Johnsen. All rights reserved.
//

#import "TJFastImageButton.h"
#import "TJImageCache.h"

@interface TJFastImageButton () <TJImageCacheDelegate>

TJ_FAST_IMAGE_PRIVATE_INTERFACE

@property (nonatomic, strong) UIImage *imageViewImage;

@end

@implementation TJFastImageButton

TJ_FAST_IMAGE_DEFINITION(imageViewImage)

- (void)setImageViewImage:(UIImage *)image
{
    [self setImage:image forState:UIControlStateNormal];
}

- (UIImage *)imageViewImage
{
    return [self imageForState:UIControlStateNormal];
}


@end
