//
//  TJProgressiveImageView.h
//  OpenerCore
//
//  Created by Tim Johnsen on 1/30/20.
//  Copyright © 2020 tijo. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface TJProgressiveImageView : UIImageView

@property (nonatomic, strong, nullable) NSOrderedSet<NSString *> *imageURLStrings;

@end

NS_ASSUME_NONNULL_END
