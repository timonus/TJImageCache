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

// Must be thread safe
UIImage *imageForImageSizeCornerRadius(UIImage *const image, const CGSize size, const CGFloat cornerRadius, UIColor *const strokeColor, UIColor *const opaqueBackgroundColor);
UIImage *placeholderImageWithCornerRadius(const CGFloat cornerRadius, UIColor *const strokeColor, UIColor *const placeholderBackgroundColor, UIColor *const opaqueBackgroundColor);

#endif /* TJFastImage_h */
