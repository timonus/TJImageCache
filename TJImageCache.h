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

+ (NSString *)hash:(NSString *)string;

+ (UIImage *)imageAtURL:(NSString *)url depth:(TJImageCacheDepth)depth delegate:(id<TJImageCacheDelegate>)delegate;
+ (UIImage *)imageAtURL:(NSString *)url delegate:(id<TJImageCacheDelegate>)delegate;
+ (UIImage *)imageAtURL:(NSString *)url depth:(TJImageCacheDepth)depth;
+ (UIImage *)imageAtURL:(NSString *)url;

+ (TJImageCacheDepth)depthForImageAtURL:(NSString *)url;

+ (void)removeImageAtURL:(NSString *)url;
+ (void)dumpDiskCache;
+ (void)dumpMemoryCache;

+ (void)auditCacheWithBlock:(BOOL (^)(NSString *hashedURL, NSDate *lastAccess, NSDate *createdDate))block;		// return YES to preserve the image, return NO to delete it
+ (void)auditCacheRemovingFilesOlderThanDate:(NSDate *)date;
+ (void)auditCacheRemovingFilesLastAccessedBeforeDate:(NSDate *)date;

@end
