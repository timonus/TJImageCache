//
//  NSItemProvider+TJImageCache.m
//  Wootie
//
//  Created by Tim Johnsen on 5/13/20.
//

#import "NSItemProvider+TJImageCache.h"
#import "TJImageCache.h"

#import <objc/runtime.h>

static const char *kTJImageCacheItemProviderLoadCompletionBlockKey = "kTJImageCacheItemProviderLoadCompletionBlockKey";

@interface NSItemProvider (TJImageCacheDelegate) <TJImageCacheDelegate>

@end

@implementation NSItemProvider (TJImageCache)

+ (instancetype)tj_itemProviderForImageURLString:(NSString *const)imageURLString
{
    NSItemProvider *itemProvider = nil;
    if (imageURLString) {
        itemProvider = [NSItemProvider new];
        __weak NSItemProvider *const weakItemProvider = itemProvider;
        [itemProvider registerObjectOfClass:[UIImage class]
                                 visibility:NSItemProviderRepresentationVisibilityAll
                                loadHandler:^NSProgress * _Nullable(void (^ _Nonnull completionHandler)(id<NSItemProviderWriting> _Nullable, NSError * _Nullable)) {
            UIImage *const image = [TJImageCache imageAtURL:imageURLString delegate:weakItemProvider];
            if (image) {
                completionHandler(image, nil);
            } else {
                objc_setAssociatedObject(weakItemProvider, kTJImageCacheItemProviderLoadCompletionBlockKey, completionHandler, OBJC_ASSOCIATION_COPY);
            }
            return nil;
        }];
    }
    return itemProvider;
}

@end

@implementation NSItemProvider (TJImageCacheDelegate)

static void _tryInvokeCallbackWithImage(NSItemProvider *const itemProvider, UIImage *const image)
{
    void (^completionHandler)(id<NSItemProviderWriting> _Nullable object, NSError * _Nullable error) = objc_getAssociatedObject(itemProvider, kTJImageCacheItemProviderLoadCompletionBlockKey);
    if (completionHandler) {
        completionHandler(nil, nil);
    }
}

- (void)didGetImage:(UIImage *)image atURL:(NSString *)url
{
    _tryInvokeCallbackWithImage(self, image);
}

- (void)didFailToGetImageAtURL:(NSString *)url
{
    _tryInvokeCallbackWithImage(self, nil);
}

@end
