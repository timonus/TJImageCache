//
//  TJFastImage.m
//  Mastodon
//
//  Created by Tim Johnsen on 4/19/17.
//  Copyright © 2017 Tim Johnsen. All rights reserved.
//

#import "TJFastImage.h"

// Must be thread safe
UIImage *drawImageWithBlockSizeOpaque(void (^drawBlock)(CGContextRef context, UIBezierPath *clippingPath), const CGSize size, const CGFloat cornerRadius, UIColor *const strokeColor, UIColor *const opaqueBackgroundColor);
UIImage *drawImageWithBlockSizeOpaque(void (^drawBlock)(CGContextRef context, UIBezierPath *clippingPath), const CGSize size, const CGFloat cornerRadius, UIColor *const strokeColor, UIColor *const opaqueBackgroundColor)
{
    UIImage *image = nil;
    const BOOL opaque = opaqueBackgroundColor != nil;
    if (opaque) {
        drawBlock = ^(CGContextRef context, UIBezierPath *clippingPath) {
            [opaqueBackgroundColor setFill];
            CGContextFillRect(context, (CGRect){CGPointZero, size});
            drawBlock(context, clippingPath);
        };
    }
#if defined(__IPHONE_10_0) && __IPHONE_OS_VERSION_MIN_REQUIRED < __IPHONE_10_0
    if (@available(iOS 10.0, *)) {
#endif
        static CGFloat scale;
        static UIGraphicsImageRendererFormat *transparentFormat = nil;
        static UIGraphicsImageRendererFormat *opaqueFormat = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            scale = [[UIScreen mainScreen] scale];
            transparentFormat = [UIGraphicsImageRendererFormat new];
#if defined(__IPHONE_12_0) && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_12_0
            // We assume the images we receive don't contain extended range colors.
            // Those colors are explicitly filtered out when drawing as an optimization.
            if (@available(iOS 12.0, *)) {
                transparentFormat.preferredRange = UIGraphicsImageRendererFormatRangeStandard;
            } else {
#endif
                transparentFormat.prefersExtendedRange = NO;
#if defined(__IPHONE_12_0) && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_12_0
            }
#endif
        });
        UIGraphicsImageRendererFormat *format = nil;
        if (opaque) {
            static dispatch_once_t onceToken;
            dispatch_once(&onceToken, ^{
                opaqueFormat = [transparentFormat copy];
                opaqueFormat.opaque = YES;
            });
            format = opaqueFormat;
        } else {
            format = transparentFormat;
        }
        UIGraphicsImageRenderer *const renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
        const CGRect rect = (CGRect){CGPointZero, size};
        UIBezierPath *const clippingPath = [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:cornerRadius];
        image = [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull rendererContext) {
            const CGContextRef context = rendererContext.CGContext;
            drawBlock(context, clippingPath);
            [strokeColor setStroke];
            CGContextSetLineWidth(context, MIN(1.0 / scale, 0.5));
            [clippingPath stroke];
        }];
#if defined(__IPHONE_10_0) && __IPHONE_OS_VERSION_MIN_REQUIRED < __IPHONE_10_0
    } else {
        UIGraphicsBeginImageContextWithOptions(size, opaque, [UIScreen mainScreen].scale);
        drawBlock(UIGraphicsGetCurrentContext());
        image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    }
#endif
    return image;
}


UIImage *imageForImageSizeCornerRadius(UIImage *const image, const CGSize size, const CGFloat cornerRadius, UIColor *const strokeColor, UIColor *const opaqueBackgroundColor)
{
    UIImage *drawnImage = nil;
    if (size.width > 0.0 && size.height > 0.0) {
        const CGRect rect = (CGRect){CGPointZero, size};
        drawnImage = drawImageWithBlockSizeOpaque(^(CGContextRef context, UIBezierPath *clippingPath) {
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
        }, size, cornerRadius, strokeColor, opaqueBackgroundColor);
    }
    return drawnImage;
}

UIImage *placeholderImageWithCornerRadius(const CGFloat cornerRadius, UIColor *const strokeColor, UIColor *const placeholderBackgroundColor, UIColor *const opaqueBackgroundColor)
{
    static NSCache<NSNumber *, UIImage *> *cachedImages = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cachedImages = [NSCache new];
    });
    
    NSNumber *const key = @((NSUInteger)cornerRadius ^ [strokeColor hash] ^ [placeholderBackgroundColor hash] ^ [opaqueBackgroundColor hash]);
    UIImage *image = [cachedImages objectForKey:key];
    if (!image) {
        const CGFloat sideLength = cornerRadius * 2.0 + 1.0;
        const CGSize size = (CGSize){sideLength, sideLength};
        
        image = drawImageWithBlockSizeOpaque(^(CGContextRef context, UIBezierPath *clippingPath) {
            [placeholderBackgroundColor setFill];
            [clippingPath fill];
        }, size, cornerRadius, strokeColor, opaqueBackgroundColor);
        image = [image resizableImageWithCapInsets:(UIEdgeInsets){cornerRadius, cornerRadius, cornerRadius, cornerRadius}];
        [cachedImages setObject:image forKey:key];
    }
    
    return image;
}
