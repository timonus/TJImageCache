//
//  UIImageView+TJImageCache.m
//  OpenerCore
//
//  Created by Tim Johnsen on 2/10/18.
//  Copyright © 2018 tijo. All rights reserved.
//

#import "UIImageView+TJImageCache.h"

#import <objc/runtime.h>

static char *const kTJImageCacheUIImageViewImageURLStringKey = "tj_imageURLString";

@interface UIImageView (TJImageCachePrivate) <TJImageCacheDelegate>

@end

@implementation UIImageView (TJImageCachePrivate)

#pragma mark - TJImageCacheDelegate

- (void)didGetImage:(UIImage *)image atURL:(NSString *)url
{
    NSString *const currentURLString = self.tj_imageURLString;
    if (currentURLString && [url isEqualToString:currentURLString]) {
        self.image = image;
    }
}

@end

@implementation UIImageView (TJImageCache)

#pragma mark - Getters and Setters

- (void)setTj_imageURLString:(NSString *)imageURLString
{
    [self tj_setImageURLString:imageURLString depth:TJImageCacheDepthNetwork forceDecompress:NO];
}

- (void)tj_setImageURLString:(NSString *const)imageURLString forceDecompress:(const BOOL)forceDecompress
{
    [self tj_setImageURLString:imageURLString depth:TJImageCacheDepthNetwork forceDecompress:forceDecompress];
}

- (void)tj_setImageURLString:(nullable NSString *const)imageURLString depth:(const TJImageCacheDepth)depth forceDecompress:(const BOOL)forceDecompress
{
    NSString *const currentImageURLString = self.tj_imageURLString;
    if (imageURLString != currentImageURLString && ![imageURLString isEqualToString:currentImageURLString]) {
        objc_setAssociatedObject(self, kTJImageCacheUIImageViewImageURLStringKey, imageURLString, OBJC_ASSOCIATION_COPY_NONATOMIC);
        self.image = [TJImageCache imageAtURL:imageURLString depth:TJImageCacheDepthNetwork delegate:self forceDecompress:forceDecompress];
    }
}

- (NSString *)tj_imageURLString
{
    return objc_getAssociatedObject(self, kTJImageCacheUIImageViewImageURLStringKey);
}

- (void)tj_cancelImageLoad
{
    if (!self.image) {
        NSString *urlString = [self tj_imageURLString];
        if (urlString) {
            [TJImageCache cancelImageLoadForURL:urlString delegate:self];
        }
    }
}

@end
