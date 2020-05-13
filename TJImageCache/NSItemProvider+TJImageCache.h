//
//  NSItemProvider+TJImageCache.h
//  Wootie
//
//  Created by Tim Johnsen on 5/13/20.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSItemProvider (TJImageCache)

+ (nullable instancetype)tj_itemProviderForImageURLString:(nullable NSString *const)imageURLString;

@end

NS_ASSUME_NONNULL_END
