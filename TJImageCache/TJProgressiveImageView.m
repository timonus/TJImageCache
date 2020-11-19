//
//  TJProgressiveImageView.m
//  OpenerCore
//
//  Created by Tim Johnsen on 1/30/20.
//  Copyright © 2020 tijo. All rights reserved.
//

#import "TJProgressiveImageView.h"

@interface TJProgressiveImageView () <TJImageCacheDelegate> {
    NSInteger _currentImageURLStringIndex;
}

@end

@implementation TJProgressiveImageView

- (instancetype)initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame]) {
        _currentImageURLStringIndex = NSNotFound;
    }
    return self;
}

- (void)setImageURLStrings:(NSOrderedSet<NSString *> *)imageURLStrings
{
    [self setImageURLStrings:imageURLStrings secondaryImageDepth:TJImageCacheDepthDisk];
}

- (void)setImageURLStrings:(NSOrderedSet<NSString *> * _Nullable)imageURLStrings secondaryImageDepth:(const TJImageCacheDepth)secondaryImageDepth
{
    if (imageURLStrings != _imageURLStrings && ![imageURLStrings isEqual:_imageURLStrings]) {
        for (NSString *str in _imageURLStrings) {
            if (![imageURLStrings containsObject:str]) {
                [TJImageCache cancelImageProcessingForURL:str delegate:self];
            }
        }
        NSString *const priorImageURLString = _currentImageURLStringIndex != NSNotFound ? [_imageURLStrings objectAtIndex:_currentImageURLStringIndex] : nil;
        _imageURLStrings = imageURLStrings;
        _currentImageURLStringIndex = _imageURLStrings == nil ? NSNotFound : [_imageURLStrings indexOfObject:priorImageURLString];
        
        if (_currentImageURLStringIndex != 0) {
            [_imageURLStrings enumerateObjectsUsingBlock:^(NSString * _Nonnull urlString, NSUInteger idx, BOOL * _Nonnull stop) {
                if (idx >= _currentImageURLStringIndex) {
                    // Don't attempt to load images beyond the best one we already have.
                    *stop = YES;
                } else {
                    // Load image 0 from network, all others loaded at secondaryImageDepth.
                    const TJImageCacheDepth depth = idx == 0 ? TJImageCacheDepthNetwork : secondaryImageDepth;
                    UIImage *const image = [TJImageCache imageAtURL:urlString depth:depth delegate:self forceDecompress:YES];
                    if (image) {
                        _currentImageURLStringIndex = idx;
                        self.image = image;
                        *stop = YES;
                    }
                }
            }];
            
            if (_currentImageURLStringIndex == NSNotFound) {
                self.image = nil;
            }
        }
    }
}

#pragma mark - TJImageCacheDelegate

- (void)didGetImage:(UIImage *)image atURL:(NSString *)url
{
    NSOrderedSet<NSString *> *const imageURLStrings = self.imageURLStrings;
    const NSInteger index = imageURLStrings ? [imageURLStrings indexOfObject:url] : NSNotFound;
    if (index != NSNotFound && index < _currentImageURLStringIndex) {
        _currentImageURLStringIndex = index;
        self.image = image;
    }
}

@end
