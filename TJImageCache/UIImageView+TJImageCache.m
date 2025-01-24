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

__attribute__((objc_direct_members))
@interface UIImageView (TJImageCachePrivate) <TJImageCacheDelegate>

@end

@implementation UIImageView (TJImageCachePrivate)

#pragma mark - TJImageCacheDelegate

- (void)didGetImage:(UIImage *)image atURL:(NSString *)url
{
    if ([url isEqualToString:self.tj_imageURLString]) {
        self.image = image;
    }
}

@end

@implementation UIImageView (TJImageCache)

#pragma mark - Getters and Setters

- (void)tj_setImageURLString:(NSString *)imageURLString
{
    [self tj_setImageURLString:imageURLString depth:TJImageCacheDepthNetwork backgroundDecode:YES];
}

- (void)tj_setImageURLString:(NSString *const)imageURLString backgroundDecode:(const BOOL)backgroundDecode
{
    [self tj_setImageURLString:imageURLString depth:TJImageCacheDepthNetwork backgroundDecode:backgroundDecode];
}

- (void)tj_setImageURLString:(nullable NSString *const)imageURLString depth:(const TJImageCacheDepth)depth backgroundDecode:(const BOOL)backgroundDecode
{
    NSString *const currentImageURLString = self.tj_imageURLString;
    if (imageURLString != currentImageURLString && ![imageURLString isEqualToString:currentImageURLString]) {
        self.image = [TJImageCache imageAtURL:imageURLString depth:TJImageCacheDepthNetwork delegate:self backgroundDecode:backgroundDecode];
        objc_setAssociatedObject(self, kTJImageCacheUIImageViewImageURLStringKey, imageURLString, OBJC_ASSOCIATION_COPY_NONATOMIC);
        if (currentImageURLString) {
            [TJImageCache cancelImageLoadForURL:currentImageURLString delegate:self policy:TJImageCacheCancellationPolicyImageProcessing];
        }
    }
}

- (NSString *)tj_imageURLString
{
    return objc_getAssociatedObject(self, kTJImageCacheUIImageViewImageURLStringKey);
}

- (void)tj_cancelImageLoadWithPolicy:(const TJImageCacheCancellationPolicy)policy
{
    if (!self.image) {
        NSString *urlString = [self tj_imageURLString];
        if (urlString) {
            [TJImageCache cancelImageLoadForURL:urlString delegate:self policy:policy];
        }
    }
}

@end
