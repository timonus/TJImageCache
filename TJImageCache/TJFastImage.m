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
    UIImage *image = nil;
    if (@available(iOS 10.0, *)) {
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
        
        image = drawImageWithBlockSizeOpaque(drawBlock, size, cornerRadius == 0.0);
        image = [image resizableImageWithCapInsets:(UIEdgeInsets){cornerRadius, cornerRadius, cornerRadius, cornerRadius}];
        [imagesForCornerRadii setObject:image forKey:@(cornerRadius)];
    }
    
    return image;
}
