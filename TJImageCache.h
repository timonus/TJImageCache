// TJImageCache
// By Tim Johnsen

typedef enum {
	TJImageCacheDepthMemory,
	TJImageCacheDepthDisk,
	TJImageCacheDepthFull
} TJImageCacheDepth;

@protocol TJImageCacheDelegate

- (void)didGetImage:(UIImage *)image atURL:(NSString *)url;
- (void)didFailToGetImage:(UIImage *)image atURL:(NSString *)url;

@end

@interface TJImageCache : NSObject

+ (UIImage *)imageAtURL:(NSString *)url depth:(TJImageCacheDepth)depth delegate:(id<TJImageCacheDelegate>)delegate;

+ (UIImage *)imageAtURL:(NSString *)url delegate:(id<TJImageCacheDelegate>)delegate;
+ (UIImage *)imageAtURL:(NSString *)url depth:(TJImageCacheDepth)depth;
+ (UIImage *)imageAtURL:(NSString *)url;

@end
