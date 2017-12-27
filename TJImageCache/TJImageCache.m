// TJImageCache
// By Tim Johnsen

#import "TJImageCache.h"
#import <CommonCrypto/CommonDigest.h>

static NSString *_tj_imageCacheRootPath;

@implementation TJImageCache

#pragma mark - Configuration

+ (void)configureWithDefaultRootPath
{
    [self configureWithRootPath:[[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingPathComponent:@"TJImageCache"]];
}

+ (void)configureWithRootPath:(NSString *const)rootPath
{
    NSAssert(_tj_imageCacheRootPath == nil, @"You should not configure %@'s root path more than once.", NSStringFromClass([self class]));
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _tj_imageCacheRootPath = [rootPath copy];
        
        BOOL isDir = NO;
        if (!([[NSFileManager defaultManager] fileExistsAtPath:_tj_imageCacheRootPath isDirectory:&isDir] && isDir)) {
            [[NSFileManager defaultManager] createDirectoryAtPath:_tj_imageCacheRootPath withIntermediateDirectories:YES attributes:nil error:nil];
            
            // Don't back up
            // https://developer.apple.com/library/ios/qa/qa1719/_index.html
            [[NSURL fileURLWithPath:_tj_imageCacheRootPath] setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
        }
    });
}

#pragma mark - Hashing

+ (NSString *)hash:(NSString *)string
{
    const char* str = [string UTF8String];
    unsigned char result[CC_MD5_DIGEST_LENGTH];
    CC_MD5(str, (CC_LONG)strlen(str), result);
    
    NSMutableString *ret = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH*2];
    for(int i = 0; i<CC_MD5_DIGEST_LENGTH; i++) {
        [ret appendFormat:@"%02x",result[i]];
    }
    return ret;
}

#pragma mark - Image Fetching

+ (IMAGE_CLASS *)imageAtURL:(NSString *const)url
{
    return [self imageAtURL:url depth:TJImageCacheDepthInternet delegate:nil];
}

+ (IMAGE_CLASS *)imageAtURL:(NSString *const)url depth:(const TJImageCacheDepth)depth
{
    return [self imageAtURL:url depth:depth delegate:nil];
}

+ (IMAGE_CLASS *)imageAtURL:(NSString *const)url delegate:(const id<TJImageCacheDelegate>)delegate
{
    return [self imageAtURL:url depth:TJImageCacheDepthInternet delegate:delegate];
}

+ (IMAGE_CLASS *)imageAtURL:(NSString *const)url depth:(const TJImageCacheDepth)depth delegate:(nullable const id<TJImageCacheDelegate>)delegate
{
    return [self imageAtURL:url depth:depth delegate:delegate forceDecompress:NO];
}

+ (IMAGE_CLASS *)imageAtURL:(NSString *const)urlString depth:(const TJImageCacheDepth)depth delegate:(nullable const id<TJImageCacheDelegate>)delegate forceDecompress:(const BOOL)forceDecompress
{
    NSURL *const url = [NSURL URLWithString:urlString];
    if (!url) {
        return nil;
    }
    
    // Attempt load from cache.
    
    NSString *const hash = [self hash:urlString];
    __block IMAGE_CLASS *inMemoryImage = [[self _cache] objectForKey:hash];
    
    // Attempt load from map table.
    
    if (!inMemoryImage) {
        [self _mapTableWithBlock:^(NSMapTable *mapTable) {
            inMemoryImage = [mapTable objectForKey:hash];
        }];
        if (inMemoryImage) {
            // Propagate back into our cache.
            [[self _cache] setObject:inMemoryImage forKey:hash];
        }
    }
    
    // Check if there's an existing disk/network request running for this image.
    __block BOOL loadAsynchronously = NO;
    if (!inMemoryImage && depth != TJImageCacheDepthMemory) {
        [self _requestDelegatesWithBlock:^(NSMutableDictionary<NSString *,NSHashTable *> *requestDelegates) {
            NSHashTable *delegatesForRequest = [requestDelegates objectForKey:hash];
            if (!delegatesForRequest) {
                delegatesForRequest = [NSHashTable weakObjectsHashTable];
                [requestDelegates setObject:delegatesForRequest forKey:hash];
                loadAsynchronously = YES;
            }
            if (delegate) {
                [delegatesForRequest addObject:delegate];
            }
        }];
    }
    
    // Attempt load from disk and network.
    if (loadAsynchronously) {
        static dispatch_queue_t readQueue = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            readQueue = dispatch_queue_create("TJImageCache disk read queue", DISPATCH_QUEUE_SERIAL);
        });
        dispatch_async(readQueue, ^{
            NSString *const path = [self _pathForHash:hash];
            if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
                // Inform delegates about success
                [self _tryUpdateMemoryCacheAndCallDelegatesForImageAtPath:path url:urlString hash:hash forceDecompress:forceDecompress];

                // Update last access date
                [[NSFileManager defaultManager] setAttributes:[NSDictionary dictionaryWithObject:[NSDate date] forKey:NSFileModificationDate] ofItemAtPath:path error:nil];
            } else if (depth == TJImageCacheDepthInternet) {
                static NSURLSession *session = nil;
                static dispatch_once_t onceToken;
                dispatch_once(&onceToken, ^{
                    // We use an ephemeral session since TJImageCache does memory and disk caching.
                    // Using NSURLCache would be redundant.
                    session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration]];
                });
                
                [[session downloadTaskWithURL:url completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
                    if (location) {
                        [[NSFileManager defaultManager] moveItemAtURL:location toURL:[NSURL fileURLWithPath:path] error:nil];
                    }
                    // Inform delegates about success or failure
                    [self _tryUpdateMemoryCacheAndCallDelegatesForImageAtPath:path url:urlString hash:hash forceDecompress:forceDecompress];
                }] resume];
            } else {
                // Inform delegates about failure
                [self _tryUpdateMemoryCacheAndCallDelegatesForImageAtPath:nil url:urlString hash:hash forceDecompress:forceDecompress];
            }
        });
    }
    
    return inMemoryImage;
}

#pragma mark - Cache Checking

+ (TJImageCacheDepth)depthForImageAtURL:(NSString *const)url
{
    NSString *const hash = [self hash:url];
    
    if ([[self _cache] objectForKey:hash]) {
        return TJImageCacheDepthMemory;
    }
    
    __block BOOL isImageInMapTable = NO;
    [self _mapTableWithBlock:^(NSMapTable *mapTable) {
        isImageInMapTable = [mapTable objectForKey:hash] != nil;
    }];
    
    if (isImageInMapTable) {
        return TJImageCacheDepthMemory;
    }
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:[self _pathForHash:hash]]) {
        return TJImageCacheDepthDisk;
    }
    
    return TJImageCacheDepthInternet;
}

+ (void)getDiskCacheSize:(void (^const)(NSUInteger diskCacheSize))completion
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSUInteger fileSize = 0;
        NSDirectoryEnumerator *const enumerator = [[NSFileManager defaultManager] enumeratorAtPath:[self _rootPath]];
        for (NSString *filename in enumerator) {
#pragma unused(filename)
            fileSize += [[[enumerator fileAttributes] objectForKey:NSFileSize] unsignedIntegerValue];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(fileSize);
        });
    });
}

#pragma mark - Cache Manipulation

+ (void)removeImageAtURL:(NSString *const)url
{
    NSString *const hash = [self hash:url];
    [[self _cache] removeObjectForKey:hash];
    [self _mapTableWithBlock:^(NSMapTable *mapTable) {
        [mapTable removeObjectForKey:hash];
    }];
    [[NSFileManager defaultManager] removeItemAtPath:[self _pathForHash:hash] error:nil];
}

+ (void)dumpMemoryCache
{
    [[self _cache] removeAllObjects];
    [self _mapTableWithBlock:^(NSMapTable *mapTable) {
        [mapTable removeAllObjects];
    }];
}

+ (void)dumpDiskCache
{
    [self auditCacheWithBlock:^BOOL(NSString *hashedURL, NSDate *lastAccess, NSDate *createdDate) {
        return NO;
    }];
}

#pragma mark - Cache Auditing

+ (void)auditCacheWithBlock:(BOOL (^const)(NSString *hashedURL, NSDate *lastAccess, NSDate *createdDate))block completionBlock:(void (^)(void))completionBlock
{
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0), ^{
        NSDirectoryEnumerator *const enumerator = [[NSFileManager defaultManager] enumeratorAtPath:[self _rootPath]];
        for (NSString *file in enumerator) {
            @autoreleasepool {
                NSDictionary *attributes = [enumerator fileAttributes];
                NSDate *createdDate = [attributes objectForKey:NSFileCreationDate];
                NSDate *lastAccess = [attributes objectForKey:NSFileModificationDate];
                __block BOOL isInUse = NO;
                [self _mapTableWithBlock:^(NSMapTable *mapTable) {
                    isInUse = [mapTable objectForKey:file] != nil;
                }];
                if (!isInUse && !block(file, lastAccess, createdDate)) {
                    NSString *path = [[self _rootPath] stringByAppendingPathComponent:file];
                    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
                }
            }
        }
        if (completionBlock) {
            completionBlock();
        }
    });
}

+ (void)auditCacheWithBlock:(BOOL (^const)(NSString *hashedURL, NSDate *lastAccess, NSDate *createdDate))block
{
    [self auditCacheWithBlock:block completionBlock:nil];
}

+ (void)auditCacheRemovingFilesOlderThanDate:(NSDate *const)date
{
    [self auditCacheWithBlock:^BOOL(NSString *hashedURL, NSDate *lastAccess, NSDate *createdDate) {
        return ([createdDate compare:date] != NSOrderedAscending);
    }];
}

+ (void)auditCacheRemovingFilesLastAccessedBeforeDate:(NSDate *const)date
{
    [self auditCacheWithBlock:^BOOL(NSString *hashedURL, NSDate *lastAccess, NSDate *createdDate) {
        return ([lastAccess compare:date] != NSOrderedAscending);
    }];
}

#pragma mark - Private

+ (NSString *)_rootPath
{
    NSAssert(_tj_imageCacheRootPath != nil, @"You should configure %@'s root path before attempting to use it.", NSStringFromClass([self class]));
    return _tj_imageCacheRootPath;
}

+ (NSString *)_pathForHash:(NSString *const)hash
{
    NSString *path = [self _rootPath];
    if (hash) {
        path = [path stringByAppendingPathComponent:hash];
    }
    return path;
}

+ (NSCache *)_cache
{
    static NSCache *cache = nil;
    static dispatch_once_t token;
    
    dispatch_once(&token, ^{
        cache = [[NSCache alloc] init];
    });
    
    return cache;
}

+ (void)_mapTableWithBlock:(void (^)(NSMapTable *mapTable))block
{
    static NSMapTable *mapTable = nil;
    static dispatch_once_t token;
    static dispatch_queue_t queue = nil;
    
    dispatch_once(&token, ^{
        mapTable = [NSMapTable strongToWeakObjectsMapTable];
        queue = dispatch_queue_create("TJImageCache map table queue", DISPATCH_QUEUE_SERIAL);
    });
    
    dispatch_sync(queue, ^{
        block(mapTable);
    });
}

+ (void)_requestDelegatesWithBlock:(void (^)(NSMutableDictionary<NSString *, NSHashTable *> *requestDelegates))block
{
    static NSMutableDictionary<NSString *, NSHashTable *> *requests = nil;
    static dispatch_once_t token;
    static dispatch_queue_t queue = nil;
    
    dispatch_once(&token, ^{
        requests = [[NSMutableDictionary alloc] init];
        queue = dispatch_queue_create("TJImageCache delegate queue", DISPATCH_QUEUE_SERIAL);
    });
    
    dispatch_sync(queue, ^{
        block(requests);
    });
}

+ (void)_tryUpdateMemoryCacheAndCallDelegatesForImageAtPath:(NSString *const)path url:(NSString *const)url hash:(NSString *const)hash forceDecompress:(const BOOL)forceDecompress
{
    IMAGE_CLASS *image = nil;
    if (path) {
        if (forceDecompress) {
            // Forces decompress to happen here instead of wherever the image is first painted in the UI (on the main thread)
            // Based off of https://www.cocoanetics.com/2011/10/avoiding-image-decompression-sickness/, but uses kCGImageSourceShouldCacheImmediately introduced in iOS 7.
            // Also see https://www.objc.io/issues/5-ios7/iOS7-hidden-gems-and-workarounds/#image-decompression.
            CGImageSourceRef imageSource = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], (__bridge CFDictionaryRef)@{(__bridge NSString *)kCGImageSourceShouldCacheImmediately: (__bridge id)kCFBooleanTrue});
            if (imageSource) {
                CGImageRef decompressedImage = CGImageSourceCreateImageAtIndex(imageSource, 0, (__bridge CFDictionaryRef)@{(__bridge NSString *)kCGImageSourceShouldCacheImmediately: (__bridge id)kCFBooleanTrue});
                if (decompressedImage) {
                    image = [IMAGE_CLASS imageWithCGImage:decompressedImage];
                    CGImageRelease(decompressedImage);
                }
                CFRelease(imageSource);
            }
        }
        if (!image) {
            // Fall back to primitive image loading.
            image = [[IMAGE_CLASS alloc] initWithContentsOfFile:path];
        }
    }
    if (image) {
        [[self _cache] setObject:image forKey:hash];
        [self _mapTableWithBlock:^(NSMapTable *mapTable) {
            [mapTable setObject:image forKey:hash];
        }];
    }
    [self _requestDelegatesWithBlock:^(NSMutableDictionary<NSString *,NSHashTable *> *requestDelegates) {
        NSHashTable *delegatesForRequest = [requestDelegates objectForKey:hash];
        dispatch_async(dispatch_get_main_queue(), ^{
            for (id<TJImageCacheDelegate> delegate in delegatesForRequest) {
                if (image) {
                    [delegate didGetImage:image atURL:url];
                } else if ([delegate respondsToSelector:@selector(didFailToGetImageAtURL:)]) {
                    [delegate didFailToGetImageAtURL:url];
                }
            }
        });
        [requestDelegates removeObjectForKey:hash];
    }];
}

@end
