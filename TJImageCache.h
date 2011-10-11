// TJImageCache
// TJImageCache
// By Tim Johnsen

typedef enum {
	TJImageCacheDepthMemory,
	TJImageCacheDepthDisk,
	TJImageCacheDepthInternet
} TJImageCacheDepth;

@protocol TJImageCacheDelegate <NSObject>

@optional

- (void)didGetImage:(UIImage *)image atURL:(NSString *)url;
- (void)didFailToGetImageAtURL:(NSString *)url;

@end

@interface TJImageCache : NSObject

+ (UIImage *)imageAtURL:(NSString *)url depth:(TJImageCacheDepth)depth delegate:(id<TJImageCacheDelegate>)delegate;

+ (UIImage *)imageAtURL:(NSString *)url delegate:(id<TJImageCacheDelegate>)delegate;
+ (UIImage *)imageAtURL:(NSString *)url depth:(TJImageCacheDepth)depth;
+ (UIImage *)imageAtURL:(NSString *)url;

+ (TJImageCacheDepth)depthForImageAtURL:(NSString *)url;

+ (void)removeImageAtURL:(NSString *)url;
+ (void)dumpDiskCache;
+ (void)dumpMemoryCache;


@end
