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

@property (nonatomic, strong) UIImage *loadedImage;
@property (nonatomic, assign) BOOL needsUpdateImage;

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

- (void)setBackgroundColor:(UIColor *)backgroundColor
{
    /* Intentionally left as a no-op so table view cells don't change our background color. */
}

- (void)setImageURLString:(NSString *)imageURLString
{
    if (imageURLString != _imageURLString && ![imageURLString isEqual:_imageURLString]) {
        _imageURLString = [imageURLString copy];
        self.loadedImage = [TJImageCache imageAtURL:self.imageURLString delegate:self];
    }
}

- (void)setImageCornerRadius:(CGFloat)imageCornerRadius
{
    if (imageCornerRadius != _imageCornerRadius) {
        _imageCornerRadius = imageCornerRadius;
        [self setNeedsUpdateImage];
    }
}

- (void)setImageOpaqueBackgroundColor:(UIColor *const)color
{
    if (color != _imageOpaqueBackgroundColor && ![color isEqual:_imageOpaqueBackgroundColor]) {
        _imageOpaqueBackgroundColor = color;
        [self setNeedsUpdateImage];
    }
}

- (void)setFrame:(CGRect)frame
{
    const BOOL shouldUpdateImage = !CGSizeEqualToSize(frame.size, self.frame.size);
    [super setFrame:frame];
    if (shouldUpdateImage) {
        [self setNeedsUpdateImage];
    }
}

- (void)setLoadedImage:(UIImage *)loadedImage
{
    if (loadedImage != _loadedImage && ![loadedImage isEqual:_loadedImage]) {
        _loadedImage = loadedImage;
        [self setNeedsUpdateImage];
    }
}

- (void)didGetImage:(UIImage *)image atURL:(NSString *)url
{
    if ([url isEqualToString:self.imageURLString] && !self.loadedImage) {
        self.loadedImage = image;
    }
}

- (void)setNeedsUpdateImage
{
    self.needsUpdateImage = YES;
    [self setNeedsLayout];
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    if (self.needsUpdateImage) {
        [self updateImage];
    }
}

/* Not to be called, similar to never calling -layoutSubviews. Call -setNeedsUpdateImage instead. */
- (void)updateImage
{
    UIColor *opaqueBackgroundColor = nil;
    if (@available(iOS 11.0, *)) {
        opaqueBackgroundColor = self.accessibilityIgnoresInvertColors && UIAccessibilityIsInvertColorsEnabled() ? nil : self.imageOpaqueBackgroundColor;
    } else {
        opaqueBackgroundColor = self.imageOpaqueBackgroundColor;
    }
    self.image = placeholderImageWithCornerRadius(self.imageCornerRadius, opaqueBackgroundColor);
    
    UIImage *const image = self.loadedImage;
    if (image) {
        NSString *const imageURLString = self.imageURLString;
        const CGSize size = self.bounds.size;
        const CGFloat cornerRadius = self.imageCornerRadius;
        
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            UIImage *const drawnImage = imageForImageSizeCornerRadius(image, size, cornerRadius, opaqueBackgroundColor);
            dispatch_async(dispatch_get_main_queue(), ^{
                /* These can mutate while scrolling quickly. We only want to accept the asynchronously drawn image if it matches our expectations. */
                if ([imageURLString isEqualToString:self.imageURLString] && CGSizeEqualToSize(size, self.bounds.size) && cornerRadius == self.imageCornerRadius) {
                    self.image = drawnImage;
                }
            });
        });
    }
    self.needsUpdateImage = NO;
}


@end
