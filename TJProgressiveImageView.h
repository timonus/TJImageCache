//
//  TJProgressiveImageView.h
//  OpenerCore
//
//  Created by Tim Johnsen on 1/30/20.
//  Copyright © 2020 tijo. All rights reserved.
//

#import "TJImageCache.h"
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface TJProgressiveImageView : UIImageView

@property (nonatomic, nullable) NSOrderedSet<NSString *> *imageURLStrings;

- (void)setImageURLStrings:(NSOrderedSet<NSString *> * _Nullable)imageURLStrings secondaryImageDepth:(const TJImageCacheDepth)secondaryImageDepth;

@end

NS_ASSUME_NONNULL_END
