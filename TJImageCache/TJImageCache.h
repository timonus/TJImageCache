// TJImageCache
// By Tim Johnsen

// NOTE: To use in OS X, you should import AppKit and chanve IMAGE_CLASS to NSImageView
#import <UIKit/UIKit.h>
#define IMAGE_CLASS UIImage

typedef enum {
    TJImageCacheDepthMemory,
    TJImageCacheDepthDisk,
    TJImageCacheDepthInternet
} TJImageCacheDepth;

@protocol TJImageCacheDelegate <NSObject>

@optional

- (void)didGetImage:(IMAGE_CLASS *)image atURL:(NSString *)url;
- (void)didFailToGetImageAtURL:(NSString *)url;

@end

@interface TJImageCache : NSObject

+ (NSString *)hash:(NSString *)string;

+ (IMAGE_CLASS *)imageAtURL:(NSString *)url depth:(TJImageCacheDepth)depth delegate:(id<TJImageCacheDelegate>)delegate;
+ (IMAGE_CLASS *)imageAtURL:(NSString *)url delegate:(id<TJImageCacheDelegate>)delegate;
+ (IMAGE_CLASS *)imageAtURL:(NSString *)url depth:(TJImageCacheDepth)depth;
+ (IMAGE_CLASS *)imageAtURL:(NSString *)url;

+ (TJImageCacheDepth)depthForImageAtURL:(NSString *)url;

+ (void)removeImageAtURL:(NSString *)url;
+ (void)dumpDiskCache;
+ (void)dumpMemoryCache;

+ (void)auditCacheWithBlock:(BOOL (^)(NSString *hashedURL, NSDate *lastAccess, NSDate *createdDate))block completionBlock:(void (^)(void))completionBlock; // return YES to preserve the image, return NO to delete it
+ (void)auditCacheWithBlock:(BOOL (^)(NSString *hashedURL, NSDate *lastAccess, NSDate *createdDate))block;
+ (void)auditCacheRemovingFilesOlderThanDate:(NSDate *)date;
+ (void)auditCacheRemovingFilesLastAccessedBeforeDate:(NSDate *)date;

+ (void)addAuditImageURLToPreserve:(NSString *)url;
+ (void)commitAuditCache;

@end
