//
//  UIImageView+TJImageCache.h
//  OpenerCore
//
//  Created by Tim Johnsen on 2/10/18.
//  Copyright © 2018 tijo. All rights reserved.
//

#import <UIKit/UIKit.h>

#import "TJImageCache.h"

NS_ASSUME_NONNULL_BEGIN

@interface UIImageView (TJImageCache)

@property (nonatomic, copy) NSString *tj_imageURLString;

- (void)tj_setImageURLString:(nullable NSString *const)imageURLString forceDecompress:(const BOOL)forceDecompress;
- (void)tj_setImageURLString:(nullable NSString *const)imageURLString depth:(const TJImageCacheDepth)depth forceDecompress:(const BOOL)forceDecompress;

@end

NS_ASSUME_NONNULL_END
