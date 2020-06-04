//
//  TJImagePriorityLoader.h
//  Wootie
//
//  Created by Tim Johnsen on 6/4/20.
//

#import "TJImageCache.h"

NS_ASSUME_NONNULL_BEGIN

@interface TJImagePriorityLoader : NSObject

- (nullable UIImage *)imageAtURL:(NSString *const)url delegate:(nullable const id<TJImageCacheDelegate>)delegate priority:(NSUInteger)priority;

@end

NS_ASSUME_NONNULL_END
