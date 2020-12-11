//
//  TJFastImageView.h
//  Opener
//
//  Created by Tim Johnsen on 4/13/17.
//  Copyright © 2017 tijo. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "TJFastImage.h"

@interface TJFastImageView : UIImageView

@property (nonatomic, copy) NSString *imageURLString;
@property (nonatomic, assign) CGFloat imageCornerRadius;
@property (nonatomic, strong) UIColor *imageOpaqueBackgroundColor;

@end
