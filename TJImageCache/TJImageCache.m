// TJImageCache
// By Tim Johnsen

#import "TJImageCache.h"
#import <CommonCrypto/CommonDigest.h>

static NSString *_tj_imageCacheRootPath;

@implementation TJImageCache

#pragma mark Configuration

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

#pragma mark Hashing

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

#pragma mark Image Fetching

+ (IMAGE_CLASS *)imageAtURL:(NSString *const)url
{
    return [self imageAtURL:url depth:TJImageCacheDepthInternet delegate:nil];
}

+ (IMAGE_CLASS *)imageAtURL:(NSString *const)url depth:(const TJImageCacheDepth)depth
{
    return [self imageAtURL:url depth:depth delegate:nil];
}

+ (IMAGE_CLASS *)imageAtURL:(NSString *const)url delegate:(const id<TJImageCacheDelegate>)delegate;
{
    return [self imageAtURL:url depth:TJImageCacheDepthInternet delegate:delegate];
}

+ (IMAGE_CLASS *)imageAtURL:(NSString *const)url depth:(const TJImageCacheDepth)depth delegate:(const id<TJImageCacheDelegate>)delegate
{
    if (!url) {
        return nil;
    }
    
    // Load from memory
    
    NSString *const hash = [TJImageCache hash:url];
    __block IMAGE_CLASS *inMemoryImage = [[TJImageCache _cache] objectForKey:hash];
    
    // Load from other object potentially hanging on to reference
    
    if (!inMemoryImage) {
        [self _mapTableWithBlock:^(NSMapTable *mapTable) {
            inMemoryImage = [mapTable objectForKey:hash];
        }];
        if (inMemoryImage) {
            [[TJImageCache _cache] setObject:inMemoryImage forKey:hash];
        }
    }
    
    // Load from disk or network
    
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
    
    if (loadAsynchronously) {
        [[self _readQueue] addOperationWithBlock:^{
            NSString *const path = [TJImageCache _pathForURL:url];
            __block UIImage *image = [[IMAGE_CLASS alloc] initWithContentsOfFile:path];

            if (image) {
                // tell delegate about success
                [self _tryCacheInMemoryAndCallDelegatesForImage:image url:url hash:hash];

                // update last access date
                [[NSFileManager defaultManager] setAttributes:[NSDictionary dictionaryWithObject:[NSDate date] forKey:NSFileModificationDate] ofItemAtPath:path error:nil];
            } else if (depth == TJImageCacheDepthInternet) {
                static NSURLSession *session = nil;
                static dispatch_once_t onceToken;
                dispatch_once(&onceToken, ^{
                    // We use an ephemeral session since TJImageCache does memory and disk caching.
                    // Using NSURLCache would be redundant.
                    session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration]];
                });
                
                [[session downloadTaskWithURL:[NSURL URLWithString:url] completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
                    if (location) {
                        [[NSFileManager defaultManager] moveItemAtURL:location toURL:[NSURL fileURLWithPath:path] error:nil];
                        image = [[IMAGE_CLASS alloc] initWithContentsOfFile:path];
                    }
                    [self _tryCacheInMemoryAndCallDelegatesForImage:image url:url hash:hash];
                }] resume];
            } else {
                [self _tryCacheInMemoryAndCallDelegatesForImage:nil url:url hash:hash];
            }
        }];
    }
    
    return inMemoryImage;
}

+ (void)_tryCacheInMemoryAndCallDelegatesForImage:(UIImage *const)image url:(NSString *const)url hash:(NSString *)hash
{
    if (image) {
        [[TJImageCache _cache] setObject:image forKey:hash];
        [TJImageCache _mapTableWithBlock:^(NSMapTable *mapTable) {
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

//+ (IMAGE_CLASS *)imageAtURL:(NSString *const)url depth:(const TJImageCacheDepth)depth delegate:(const id<TJImageCacheDelegate>)delegate
//{
//    if (!url) {
//        return nil;
//    }
//
//    // Load from memory
//
//    NSString *const hash = [TJImageCache hash:url];
//    IMAGE_CLASS *inMemoryImage = [[TJImageCache _cache] objectForKey:hash];
//
//    // Load from other object potentially hanging on to reference
//
//    if (!inMemoryImage) {
//        @synchronized ([self _mapTable]) {
//            inMemoryImage = [[TJImageCache _mapTable] objectForKey:hash];
//        }
//        if (inMemoryImage) {
//            [[TJImageCache _cache] setObject:inMemoryImage forKey:hash];
//        }
//    }
//
//    // Load from disk
//
//    if (!inMemoryImage && depth != TJImageCacheDepthMemory) {
//        __block IMAGE_CLASS *image = nil;
//        [[TJImageCache _readQueue] addOperationWithBlock:^{
//            NSString *const path = [TJImageCache _pathForURL:url];
//            image = [[IMAGE_CLASS alloc] initWithContentsOfFile:path];
//
//            if (image) {
//                // add to in-memory cache
//                [self _setInMemoryImage:image forKey:hash];
//
//                // tell delegate about success
//                if ([delegate respondsToSelector:@selector(didGetImage:atURL:)]) {
//                    dispatch_async(dispatch_get_main_queue(), ^{
//                        [delegate didGetImage:image atURL:url];
//                    });
//                }
//
//                // update last access date
//                [[NSFileManager defaultManager] setAttributes:[NSDictionary dictionaryWithObject:[NSDate date] forKey:NSFileModificationDate] ofItemAtPath:path error:nil];
//            } else {
//                if (depth == TJImageCacheDepthInternet) {
//
//
//                    if (loadFromNetwork) {
//                        static NSURLSession *session = nil;
//                        static dispatch_once_t onceToken;
//                        dispatch_once(&onceToken, ^{
//                            // We use an ephemeral session since TJImageCache does memory and disk caching.
//                            // Using NSURLCache would be redundant.
//                            session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration]];
//                        });
//
//                        [[session downloadTaskWithURL:[NSURL URLWithString:url] completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
//                            if (location) {
//                                [[NSFileManager defaultManager] moveItemAtURL:location toURL:[NSURL fileURLWithPath:path] error:nil];
//                                image = [[IMAGE_CLASS alloc] initWithContentsOfFile:path];
//                            }
//
//                            if (image) {
//                                // Cache in Memory
//                                [self _setInMemoryImage:image forKey:hash];
//
//                                dispatch_async(dispatch_get_main_queue(), ^{
//                                    // Inform Delegates
//                                    for (id delegate in [[self _requestDelegates] objectForKey:hash]) {
//                                        if ([delegate respondsToSelector:@selector(didGetImage:atURL:)]) {
//                                            [delegate didGetImage:image atURL:url];
//                                        }
//                                    }
//
//                                    // Remove the connection
//                                    [[TJImageCache _requestDelegates] removeObjectForKey:hash];
//                                });
//                            } else {
//                                dispatch_async(dispatch_get_main_queue(), ^{
//                                    // Inform Delegates
//                                    for (id delegate in [[self _requestDelegates] objectForKey:hash]) {
//                                        if ([delegate respondsToSelector:@selector(didFailToGetImageAtURL:)]) {
//                                            [delegate didFailToGetImageAtURL:url];
//                                        }
//                                    }
//
//                                    // Remove the connection
//                                    [[TJImageCache _requestDelegates] removeObjectForKey:hash];
//                                });
//                            }
//                        }] resume];
//                    }
//                } else {
//                    // tell delegate about failure
//                    if ([delegate respondsToSelector:@selector(didFailToGetImageAtURL:)]) {
//                        dispatch_async(dispatch_get_main_queue(), ^{
//                            [delegate didFailToGetImageAtURL:url];
//                        });
//                    }
//                }
//            }
//        }];
//    }
//
//    return inMemoryImage;
//}

#pragma mark Cache Checking

+ (TJImageCacheDepth)depthForImageAtURL:(NSString *const)url
{
    
    if ([[TJImageCache _cache] objectForKey:[TJImageCache hash:url]]) {
        return TJImageCacheDepthMemory;
    }
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:[TJImageCache _pathForURL:url]]) {
        return TJImageCacheDepthDisk;
    }
    
    return TJImageCacheDepthInternet;
}

#pragma mark Cache Manipulation

+ (void)removeImageAtURL:(NSString *const)url
{
    NSString *const hash = [TJImageCache hash:url];
    [[TJImageCache _cache] removeObjectForKey:hash];
    [TJImageCache _mapTableWithBlock:^(NSMapTable *mapTable) {
        [mapTable removeObjectForKey:hash];
    }];
    [[NSFileManager defaultManager] removeItemAtPath:[TJImageCache _pathForURL:url] error:nil];
}

+ (void)dumpDiskCache
{
    [self auditCacheWithBlock:^BOOL(NSString *hashedURL, NSDate *lastAccess, NSDate *createdDate) {
        return NO;
    }];
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

+ (void)dumpMemoryCache
{
    [[TJImageCache _cache] removeAllObjects];
    [TJImageCache _mapTableWithBlock:^(NSMapTable *mapTable) {
        [mapTable removeAllObjects];
    }];
}

#pragma mark Cache Auditing

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
    [TJImageCache auditCacheWithBlock:^BOOL(NSString *hashedURL, NSDate *lastAccess, NSDate *createdDate) {
        return ([createdDate compare:date] != NSOrderedAscending);
    }];
}

+ (void)auditCacheRemovingFilesLastAccessedBeforeDate:(NSDate *const)date
{
    [TJImageCache auditCacheWithBlock:^BOOL(NSString *hashedURL, NSDate *lastAccess, NSDate *createdDate) {
        return ([lastAccess compare:date] != NSOrderedAscending);
    }];
}

#pragma mark Private

+ (NSString *)_rootPath
{
    NSAssert(_tj_imageCacheRootPath != nil, @"You should configure %@'s root path before attempting to use it.", NSStringFromClass([self class]));
    return _tj_imageCacheRootPath;
}

+ (NSString *)_pathForURL:(NSString *const)url
{
    NSString *path = [self _rootPath];
    if (url) {
        path = [path stringByAppendingPathComponent:[TJImageCache hash:url]];
    }
    return path;
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
    static id mapTable = nil;
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

+ (NSOperationQueue *)_readQueue
{
    static NSOperationQueue *queue = nil;
    static dispatch_once_t token;
    
    dispatch_once(&token, ^{
        queue = [[NSOperationQueue alloc] init];
        [queue setMaxConcurrentOperationCount:1];
    });
    
    return queue;
}

@end
