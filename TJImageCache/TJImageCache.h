// TJImageCache
// By Tim Johnsen

// NOTE: To use in OS X, you should import AppKit and change IMAGE_CLASS to NSImageView
#import <UIKit/UIKit.h>
#define IMAGE_CLASS UIImage

typedef NS_ENUM(NSUInteger, TJImageCacheDepth) {
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

@interface TJImageCache : NSObject

+ (void)configureWithDefaultRootPath;
+ (void)configureWithRootPath:(NSString *const)rootPath;

+ (NSString *)hash:(NSString *)string;

+ (nullable IMAGE_CLASS *)imageAtURL:(NSString *const)url depth:(const TJImageCacheDepth)depth delegate:(nullable const id<TJImageCacheDelegate>)delegate forceDecompress:(const BOOL)forceDecompress;
+ (nullable IMAGE_CLASS *)imageAtURL:(NSString *const)url depth:(const TJImageCacheDepth)depth delegate:(nullable const id<TJImageCacheDelegate>)delegate;
+ (nullable IMAGE_CLASS *)imageAtURL:(NSString *const)url delegate:(nullable const id<TJImageCacheDelegate>)delegate;
+ (nullable IMAGE_CLASS *)imageAtURL:(NSString *const)url depth:(const TJImageCacheDepth)depth;
+ (nullable IMAGE_CLASS *)imageAtURL:(NSString *const)url;

+ (TJImageCacheDepth)depthForImageAtURL:(NSString *const)url;

+ (void)removeImageAtURL:(NSString *const)url;
+ (void)dumpDiskCache;
+ (void)dumpMemoryCache;
+ (void)getDiskCacheSize:(void (^const)(NSUInteger diskCacheSize))completion;

+ (void)auditCacheWithBlock:(BOOL (^const)(NSString *hashedURL, NSDate *lastAccess, NSDate *createdDate))block completionBlock:(void (^_Nullable)(void))completionBlock; // return YES to preserve the image, return NO to delete it
+ (void)auditCacheWithBlock:(BOOL (^const)(NSString *hashedURL, NSDate *lastAccess, NSDate *createdDate))block;
+ (void)auditCacheRemovingFilesOlderThanDate:(NSDate *const)date;
+ (void)auditCacheRemovingFilesLastAccessedBeforeDate:(NSDate *const)date;

@end

NS_ASSUME_NONNULL_END
