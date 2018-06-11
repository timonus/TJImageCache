//
//  TJFastImage.m
//  Mastodon
//
//  Created by Tim Johnsen on 4/19/17.
//  Copyright © 2017 Tim Johnsen. All rights reserved.
//

#import "TJFastImage.h"

// Must be thread safe
UIImage *drawImageWithBlockSizeOpaque(const void (^drawBlock)(CGContextRef context), const CGSize size, const BOOL opaque);
UIImage *drawImageWithBlockSizeOpaque(const void (^drawBlock)(CGContextRef context), const CGSize size, const BOOL opaque)
{
    static UIGraphicsImageRendererFormat *format = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        format = [[UIGraphicsImageRendererFormat alloc] init];
#if defined(__IPHONE_12_0) && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_12_0
        // We assume the images we receive don't contain extended range colors.
        // Those colors are explicitly filtered out when drawing as an optimization.
        if (@available(iOS 12.0, *)) {
            format.preferredRange = UIGraphicsImageRendererFormatRangeStandard;
        } else {
#endif
            format.prefersExtendedRange = NO;
#if defined(__IPHONE_12_0) && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_12_0
        }
#endif
    });
    UIGraphicsImageRenderer *const renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
    UIImage *const image = [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull rendererContext) {
        drawBlock(rendererContext.CGContext);
    }];
    return image;
}


UIImage *imageForImageSizeCornerRadius(UIImage *const image, const CGSize size, const CGFloat cornerRadius)
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
        
        drawnImage = drawImageWithBlockSizeOpaque(drawBlock, size, cornerRadius == 0.0);
    }
    return drawnImage;
}

UIImage *placeholderImageWithCornerRadius(const CGFloat cornerRadius)
{
    static NSCache *imagesForCornerRadii = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        imagesForCornerRadii = [NSCache new];
    });
    
    NSNumber *const key = @(cornerRadius);
    UIImage *image = [imagesForCornerRadii objectForKey:key];
    if (!image) {
        const CGFloat sideLength = cornerRadius * 2.0 + 1.0;
        const CGSize size = (CGSize){sideLength, sideLength};
        
        const void (^drawBlock)(CGContextRef context) = ^(CGContextRef context) {
            const CGRect rect = (CGRect){CGPointZero, size};
            UIBezierPath *const clippingPath = [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:cornerRadius];
            [[UIColor lightGrayColor] setFill];
            [clippingPath fill];
        };
        
        image = drawImageWithBlockSizeOpaque(drawBlock, size, cornerRadius == 0.0);
        image = [image resizableImageWithCapInsets:(UIEdgeInsets){cornerRadius, cornerRadius, cornerRadius, cornerRadius}];
        [imagesForCornerRadii setObject:image forKey:key];
    }
    
    return image;
}
