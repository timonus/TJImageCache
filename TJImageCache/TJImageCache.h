// TJImageCache
// By Tim Johnsen

// NOTE: To use in OS X, you should import AppKit and change IMAGE_CLASS to NSImage
#import <UIKit/UIKit.h>
#define IMAGE_CLASS UIImage

typedef NS_CLOSED_ENUM(NSUInteger, TJImageCacheDepth) {
    TJImageCacheDepthMemory,
    TJImageCacheDepthDisk,
    TJImageCacheDepthNetwork
};

NS_ASSUME_NONNULL_BEGIN

@protocol TJImageCacheDelegate <NSObject>

- (void)didGetImage:(IMAGE_CLASS *)image atURL:(NSString *)url;

@optional

- (void)didFailToGetImageAtURL:(NSString *)url;

@end

extern NSString *TJImageCacheHash(NSString *string);

@interface TJImageCache : NSObject

+ (void)configureWithDefaultRootPath;
+ (void)configureWithRootPath:(NSString *const)rootPath;

+ (NSString *)hash:(NSString *)string __attribute__((deprecated("Use TJImageCacheHash instead", "TJImageCacheHash")));
+ (NSString *)pathForURLString:(NSString *const)urlString;

+ (nullable IMAGE_CLASS *)imageAtURL:(NSString *const)url depth:(const TJImageCacheDepth)depth delegate:(nullable const id<TJImageCacheDelegate>)delegate forceDecompress:(const BOOL)forceDecompress;
+ (nullable IMAGE_CLASS *)imageAtURL:(NSString *const)url depth:(const TJImageCacheDepth)depth delegate:(nullable const id<TJImageCacheDelegate>)delegate;
+ (nullable IMAGE_CLASS *)imageAtURL:(NSString *const)url delegate:(nullable const id<TJImageCacheDelegate>)delegate;
+ (nullable IMAGE_CLASS *)imageAtURL:(NSString *const)url depth:(const TJImageCacheDepth)depth;
+ (nullable IMAGE_CLASS *)imageAtURL:(NSString *const)url;

+ (void)cancelImageLoadForURL:(NSString *const)url delegate:(const id<TJImageCacheDelegate>)delegate;

+ (TJImageCacheDepth)depthForImageAtURL:(NSString *const)url;

+ (void)removeImageAtURL:(NSString *const)url;
+ (void)dumpDiskCache;
+ (void)dumpMemoryCache;
+ (void)getDiskCacheSize:(void (^const)(long long diskCacheSize))completion;

+ (void)auditCacheWithBlock:(BOOL (^const)(NSString *hashedURL, NSDate *lastAccess, NSDate *createdDate, long long fileSize))block completionBlock:(nullable dispatch_block_t)completionBlock; // return YES to preserve the image, return NO to delete it
+ (void)auditCacheWithBlock:(BOOL (^const)(NSString *hashedURL, NSDate *lastAccess, NSDate *createdDate, long long fileSize))block;
+ (void)auditCacheRemovingFilesOlderThanDate:(NSDate *const)date;
+ (void)auditCacheRemovingFilesLastAccessedBeforeDate:(NSDate *const)date;

+ (void)computeDiskCacheSizeIfNeeded;
/// Will be @c nil until @c +computeDiskCacheSizeIfNeeded, @c +getDiskCacheSize:, or one of the cache auditing methods is called once, then it will update automatically as the cache changes.
/// Observe using KVO.
@property (nonatomic, readonly, class) NSNumber *approximateDiskCacheSize;

@end

NS_ASSUME_NONNULL_END
