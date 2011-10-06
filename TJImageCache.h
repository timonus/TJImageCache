// TJImageCache
// By Tim Johnsen

typedef enum {
	TJImageCacheDepthMemory,
	TJImageCacheDepthDisk,
	TJImageCacheDepthFull
} TJImageCacheDepth;

@protocol TJImageCacheDelegate <NSObject>

- (void)didGetImage:(UIImage *)image atURL:(NSString *)url;
- (void)didFailToGetImageAtURL:(NSString *)url;

@end

@interface TJImageCache : NSObject

+ (UIImage *)imageAtURL:(NSString *)url depth:(TJImageCacheDepth)depth delegate:(id<TJImageCacheDelegate>)delegate;

+ (UIImage *)imageAtURL:(NSString *)url delegate:(id<TJImageCacheDelegate>)delegate;
+ (UIImage *)imageAtURL:(NSString *)url depth:(TJImageCacheDepth)depth;
+ (UIImage *)imageAtURL:(NSString *)url;

@end
