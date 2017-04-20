//
//  TJFastImage.h
//  Mastodon
//
//  Created by Tim Johnsen on 4/19/17.
//  Copyright © 2017 Tim Johnsen. All rights reserved.
//

#import <UIKit/UIKit.h>

#ifndef TJFastImage_h
#define TJFastImage_h

#define TJ_FAST_IMAGE_INTERFACE \
@property (nonatomic, copy) NSString *imageURLString;\
@property (nonatomic, assign) CGFloat imageCornerRadius;

#define TJ_FAST_IMAGE_PRIVATE_INTERFACE \
@property (nonatomic, strong) UIImage *loadedImage;\
@property (nonatomic, assign) BOOL needsUpdateImage;

#define TJ_FAST_IMAGE_DEFINITION(TJ_FAST_IMAGE_PROPERTY) \
- (instancetype)initWithFrame:(CGRect)frame\
{\
if (self = [super initWithFrame:frame]) {\
[super setBackgroundColor:[UIColor clearColor]];\
}\
\
return self;\
}\
\
- (void)setBackgroundColor:(UIColor *)backgroundColor\
{\
/* Intentionally left as a no-op so table view cells don't change our background color. */\
}\
\
- (void)setImageURLString:(NSString *)imageURLString\
{\
if (imageURLString != _imageURLString) {\
_imageURLString = [imageURLString copy];\
self.loadedImage = [TJImageCache imageAtURL:self.imageURLString delegate:self];\
}\
}\
\
- (void)setImageCornerRadius:(CGFloat)imageCornerRadius\
{\
if (imageCornerRadius != _imageCornerRadius) {\
_imageCornerRadius = imageCornerRadius;\
[self setNeedsUpdateImage];\
}\
}\
\
- (void)setFrame:(CGRect)frame\
{\
const BOOL shouldUpdateImage = !CGSizeEqualToSize(frame.size, self.frame.size);\
[super setFrame:frame];\
if (shouldUpdateImage) {\
[self setNeedsUpdateImage];\
}\
}\
\
- (void)setLoadedImage:(UIImage *)loadedImage\
{\
if (loadedImage != _loadedImage && ![loadedImage isEqual:_loadedImage]) {\
_loadedImage = loadedImage;\
[self setNeedsUpdateImage];\
}\
}\
\
- (void)didGetImage:(UIImage *)image atURL:(NSString *)url\
{\
if ([url isEqualToString:self.imageURLString] && !self.loadedImage) {\
self.loadedImage = image;\
}\
}\
\
- (void)setNeedsUpdateImage\
{\
self.needsUpdateImage = YES;\
[self setNeedsLayout];\
}\
\
- (void)layoutSubviews\
{\
[super layoutSubviews];\
if (self.needsUpdateImage) {\
[self updateImage];\
}\
}\
\
/* Not to be called, similar to never calling -layoutSubviews. Call -setNeedsUpdateImage instead. */\
- (void)updateImage\
{\
self.TJ_FAST_IMAGE_PROPERTY = placeholderImageWithCornerRadius(self.imageCornerRadius);\
\
UIImage *const image = self.loadedImage;\
if (image) {\
NSString *const imageURLString = self.imageURLString;\
const CGSize size = self.bounds.size;\
const CGFloat cornerRadius = self.imageCornerRadius;\
\
dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{\
UIImage *const drawnImage = imageForImageSizeCornerRadius(image, size, cornerRadius);\
dispatch_async(dispatch_get_main_queue(), ^{\
/* These can mutate while scrolling quickly. We only want to accept the asynchronously drawn image if it matches our expectations. */\
if ([imageURLString isEqualToString:self.imageURLString] && CGSizeEqualToSize(size, self.bounds.size) && cornerRadius == self.imageCornerRadius) {\
self.TJ_FAST_IMAGE_PROPERTY = drawnImage;\
}\
});\
});\
}\
self.needsUpdateImage = NO;\
}\

// Must be thread safe
UIImage *imageForImageSizeCornerRadius(UIImage *const image, const CGSize size, const CGFloat cornerRadius);
UIImage *placeholderImageWithCornerRadius(const CGFloat cornerRadius);

#endif /* TJFastImage_h */
