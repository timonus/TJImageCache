//
//  TJProgressiveImageView.m
//  OpenerCore
//
//  Created by Tim Johnsen on 1/30/20.
//  Copyright © 2020 tijo. All rights reserved.
//

#import "TJProgressiveImageView.h"

@interface TJProgressiveImageView () <TJImageCacheDelegate>

@property (nonatomic) NSInteger currentImageURLStringIndex;

@end

@implementation TJProgressiveImageView

- (instancetype)initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame]) {
        self.currentImageURLStringIndex = NSNotFound;
    }
    return self;
}

- (void)setImageURLStrings:(NSOrderedSet<NSString *> *)imageURLStrings
{
    [self setImageURLStrings:imageURLStrings secondaryImageDepth:TJImageCacheDepthDisk];
}

- (void)setImageURLStrings:(NSOrderedSet<NSString *> * _Nullable)imageURLStrings secondaryImageDepth:(const TJImageCacheDepth)secondaryImageDepth
{
    if (imageURLStrings != _imageURLStrings) {
        NSString *const priorImageURLString = self.currentImageURLStringIndex != NSNotFound ? [_imageURLStrings objectAtIndex:self.currentImageURLStringIndex] : nil;
        _imageURLStrings = imageURLStrings;
        self.currentImageURLStringIndex = _imageURLStrings == nil ? NSNotFound : [_imageURLStrings indexOfObject:priorImageURLString]; // returns NSNotFound if priorImageURLString == nil?
        
        if (self.currentImageURLStringIndex != 0) {
            [_imageURLStrings enumerateObjectsUsingBlock:^(NSString * _Nonnull urlString, NSUInteger idx, BOOL * _Nonnull stop) {
                if (idx >= self.currentImageURLStringIndex) {
                    // Don't attempt to load images beyond the best one we already have.
                    *stop = YES;
                } else {
                    // Load image 0 from network, all others loaded at secondaryImageDepth.
                    const TJImageCacheDepth depth = idx == 0 ? TJImageCacheDepthNetwork : secondaryImageDepth;
                    UIImage *const image = [TJImageCache imageAtURL:urlString depth:depth delegate:self forceDecompress:YES];
                    if (image) {
                        self.currentImageURLStringIndex = idx;
                        self.image = image;
                        *stop = YES;
                    }
                }
            }];
            
            if (self.currentImageURLStringIndex == NSNotFound) {
                self.image = nil;
            }
        }
    }
}

#pragma mark - TJImageCacheDelegate

- (void)didGetImage:(UIImage *)image atURL:(NSString *)url
{
    const NSInteger index = self.imageURLStrings ? [self.imageURLStrings indexOfObject:url] : NSNotFound;
    if (index != NSNotFound && index < self.currentImageURLStringIndex) {
        self.currentImageURLStringIndex = index;
        self.image = image;
    }
}

@end
