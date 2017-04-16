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
    }
    
    return self;
}

- (void)setBackgroundColor:(UIColor *)backgroundColor
{
    // Intentionally left as a no-op so table view cells don't change our background color.
}

- (void)setImageURLString:(NSString *)imageURLString
{
    if (imageURLString != _imageURLString) {
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

// Not to be called, similar to never calling -layoutSubviews. Call -setNeedsUpdateImage instead.
- (void)updateImage
{
    self.image = [[self class] placeholderImageWithCornerRadius:self.imageCornerRadius];
    
    UIImage *const image = self.loadedImage;
    if (image) {
        NSString *const imageURLString = self.imageURLString;
        const CGSize size = self.bounds.size;
        const CGFloat cornerRadius = self.imageCornerRadius;
        
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            UIImage *const drawnImage = [[self class] imageForImage:image size:size cornerRadius:cornerRadius];
            dispatch_async(dispatch_get_main_queue(), ^{
                // These can mutate while scrolling quickly. We only want to accept the asynchronously drawn image if it matches our expectations.
                if ([imageURLString isEqualToString:self.imageURLString] && CGSizeEqualToSize(size, self.bounds.size) && cornerRadius == self.imageCornerRadius) {
                    self.image = drawnImage;
                }
            });
        });
    }
    self.needsUpdateImage = NO;
}

// Must be thread safe
+ (UIImage *)imageForImage:(nonnull UIImage *)image size:(CGSize)size cornerRadius:(CGFloat)cornerRadius
{
    UIImage *drawnImage = nil;
    if (size.width > 0.0 && size.height > 0.0) {
        const CGRect rect = (CGRect){CGPointZero, size};
        const CGFloat scale = [UIScreen mainScreen].scale;
        
        const void (^drawBlock)(CGContextRef context) = ^(CGContextRef context) {
            UIBezierPath *const clippingPath = [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:cornerRadius];
            [clippingPath addClip]; // http://stackoverflow.com/a/13870097
            CGRect drawRect;
            if (rect.size.width / rect.size.height > image.size.width / image.size.height) {
                // Scale width
                CGFloat scaledHeight = floor(rect.size.width * (image.size.height / image.size.width));
                drawRect = CGRectMake(0.0, floor((rect.size.height - scaledHeight) / 2.0), rect.size.width, scaledHeight);
            } else {
                // Scale height
                CGFloat scaledWidth = floor(rect.size.height * (image.size.width / image.size.height));
                drawRect = CGRectMake(floor((rect.size.width - scaledWidth) / 2.0), 0.0, scaledWidth, rect.size.height);
            }
            [image drawInRect:drawRect];
            [[UIColor lightGrayColor] setStroke];
            CGContextSetLineWidth(context, MIN(1.0 / scale, 0.5));
            [clippingPath stroke];
        };
        
        if ([UIGraphicsImageRenderer class]) {
            UIGraphicsImageRenderer *const renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size];
            drawnImage = [renderer imageWithActions:^(UIGraphicsImageRendererContext *rendererContext) {
                drawBlock(rendererContext.CGContext);
            }];
        } else {
            UIGraphicsBeginImageContextWithOptions(size, NO, scale);
            drawBlock(UIGraphicsGetCurrentContext());
            drawnImage = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();
        }
    }
    return drawnImage;
}

+ (UIImage *)placeholderImageWithCornerRadius:(CGFloat)cornerRadius
{
    static NSCache *imagesForCornerRadii = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        imagesForCornerRadii = [NSCache new];
    });
    
    UIImage *image = [imagesForCornerRadii objectForKey:@(cornerRadius)];
    if (!image) {
        const CGFloat sideLength = cornerRadius * 2.0 + 1.0;
        const CGSize size = (CGSize){sideLength, sideLength};
        
        const void (^drawBlock)(CGContextRef context) = ^(CGContextRef context) {
            const CGRect rect = (CGRect){CGPointZero, size};
            UIBezierPath *const clippingPath = [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:cornerRadius];
            [[UIColor lightGrayColor] setFill];
            [clippingPath fill];
        };
        
        if ([UIGraphicsImageRenderer class]) {
            UIGraphicsImageRenderer *const renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size];
            image = [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull rendererContext) {
                drawBlock(rendererContext.CGContext);
            }];
        } else {
            UIGraphicsBeginImageContextWithOptions(size, NO, [UIScreen mainScreen].scale);
            drawBlock(UIGraphicsGetCurrentContext());
            image = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();
        }
        image = [image resizableImageWithCapInsets:(UIEdgeInsets){cornerRadius, cornerRadius, cornerRadius, cornerRadius}];
        [imagesForCornerRadii setObject:image forKey:@(cornerRadius)];
    }
    
    return image;
}

@end
