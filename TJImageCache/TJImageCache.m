// TJImageCache
// By Tim Johnsen

#import "TJImageCache.h"
#import <CommonCrypto/CommonDigest.h>

static NSString *tj_imageCacheRootPath;

@implementation TJImageCache

#pragma mark Configuration

+ (void)configureWithDefaultRootPath
{
    [self configureWithRootPath:[[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingPathComponent:@"TJImageCache"]];
}

+ (void)configureWithRootPath:(NSString *const)rootPath
{
    NSAssert(tj_imageCacheRootPath == nil, @"You should not configure %@'s root path more than once.", NSStringFromClass([self class]));
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        tj_imageCacheRootPath = [rootPath copy];
        
        BOOL isDir = NO;
        if (!([[NSFileManager defaultManager] fileExistsAtPath:tj_imageCacheRootPath isDirectory:&isDir] && isDir)) {
            [[NSFileManager defaultManager] createDirectoryAtPath:tj_imageCacheRootPath withIntermediateDirectories:YES attributes:nil error:nil];
            
            // Don't back up
            // https://developer.apple.com/library/ios/qa/qa1719/_index.html
            [[NSURL fileURLWithPath:tj_imageCacheRootPath] setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
        }
    });
}

#pragma mark Hashing

+ (NSString *)hash:(NSString *)string {
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

+ (IMAGE_CLASS *)imageAtURL:(NSString *)url delegate:(id<TJImageCacheDelegate>)delegate {
    return [self imageAtURL:url depth:TJImageCacheDepthInternet delegate:delegate];
}

+ (IMAGE_CLASS *)imageAtURL:(NSString *)url depth:(TJImageCacheDepth)depth {
    return [self imageAtURL:url depth:depth delegate:nil];
}

+ (IMAGE_CLASS *)imageAtURL:(NSString *)url {
    return [self imageAtURL:url depth:TJImageCacheDepthInternet delegate:nil];
}

+ (IMAGE_CLASS *)imageAtURL:(NSString *)url depth:(TJImageCacheDepth)depth delegate:(id<TJImageCacheDelegate>)delegate {
    
    if (!url) {
        return nil;
    }
    
    // Load from memory
    
    NSString *hash = [TJImageCache hash:url];
    __block IMAGE_CLASS *image = [[TJImageCache _cache] objectForKey:hash];
    
    // Load from other object potentially hanging on to reference
    
    if (!image) {
        image = [[TJImageCache _mapTable] objectForKey:hash];
        if (image) {
            [[TJImageCache _cache] setObject:image forKey:hash];
        }
    }
    
    // Load from disk
    
    if (!image && depth != TJImageCacheDepthMemory) {
        
        [[TJImageCache _readQueue] addOperationWithBlock:^{
            NSString *path = [TJImageCache _pathForURL:url];
            image = [[IMAGE_CLASS alloc] initWithContentsOfFile:path];
            
            if (image) {
                // update last access date
                [[NSFileManager defaultManager] setAttributes:[NSDictionary dictionaryWithObject:[NSDate date] forKey:NSFileModificationDate] ofItemAtPath:path error:nil];
                
                // add to in-memory cache
                [[TJImageCache _cache] setObject:image forKey:hash];
                [[TJImageCache _mapTable] setObject:image forKey:hash];
                
                // tell delegate about success
                if ([delegate respondsToSelector:@selector(didGetImage:atURL:)]) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [delegate didGetImage:image atURL:url];
                    });
                }
            } else {
                if (depth == TJImageCacheDepthInternet) {
                    
                    // setup or add to delegate ball wrapped in locks...
                    
                    dispatch_async(dispatch_get_main_queue(), ^{
                        
                        // Load from the interwebs
                        
                        if ([[TJImageCache _requestDelegates] objectForKey:hash]) {
                            if (delegate) {
                                id delegatesForConnection = [[TJImageCache _requestDelegates] objectForKey:hash];
                                [delegatesForConnection addObject:delegate];
                            }
                        } else {
                            id delegatesForConnection = nil;
                            if ([self _isHashTableAvailable]) {
                                delegatesForConnection = [NSHashTable weakObjectsHashTable];
                            } else {
                                delegatesForConnection = [[NSMutableSet alloc] init];
                            }
                            if (delegate) {
                                [delegatesForConnection addObject:delegate];
                            }
                            
                            [[self _requestDelegates] setObject:delegatesForConnection forKey:hash];
                            
                            static NSURLSession *session = nil;
                            static dispatch_once_t onceToken;
                            dispatch_once(&onceToken, ^{
                                // We use an ephemeral session since TJImageCache does memory and disk caching.
                                // Using NSURLCache would be redundant.
                                session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration]];
                            });
                            
                            [[session downloadTaskWithURL:[NSURL URLWithString:url] completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
                                IMAGE_CLASS *image = nil;
                                if (location) {
                                    [[NSFileManager defaultManager] moveItemAtURL:location toURL:[NSURL fileURLWithPath:path] error:nil];
                                    image = [[IMAGE_CLASS alloc] initWithContentsOfFile:path];
                                }

                                if (image) {
                                    // Cache in Memory
                                    [[TJImageCache _cache] setObject:image forKey:hash];
                                    [[TJImageCache _mapTable] setObject:image forKey:hash];
                                    
                                    dispatch_async(dispatch_get_main_queue(), ^{
                                        // Inform Delegates
                                        for (id delegate in [[self _requestDelegates] objectForKey:hash]) {
                                            if ([delegate respondsToSelector:@selector(didGetImage:atURL:)]) {
                                                [delegate didGetImage:image atURL:url];
                                            }
                                        }
                                        
                                        // Remove the connection
                                        [[TJImageCache _requestDelegates] removeObjectForKey:hash];
                                    });
                                } else {
                                    dispatch_async(dispatch_get_main_queue(), ^{
                                        // Inform Delegates
                                        for (id delegate in [[self _requestDelegates] objectForKey:hash]) {
                                            if ([delegate respondsToSelector:@selector(didFailToGetImageAtURL:)]) {
                                                [delegate didFailToGetImageAtURL:url];
                                            }
                                        }
                                        
                                        // Remove the connection
                                        [[TJImageCache _requestDelegates] removeObjectForKey:hash];
                                    });
                                }
                            }] resume];
                        }
                    });
                } else {
                    // tell delegate about failure
                    if ([delegate respondsToSelector:@selector(didFailToGetImageAtURL:)]) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [delegate didFailToGetImageAtURL:url];
                        });
                    }
                }
            }
        }];
    }
    
    return image;
}

#pragma mark Cache Checking

+ (TJImageCacheDepth)depthForImageAtURL:(NSString *)url {
    
    if ([[TJImageCache _cache] objectForKey:[TJImageCache hash:url]]) {
        return TJImageCacheDepthMemory;
    }
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:[TJImageCache _pathForURL:url]]) {
        return TJImageCacheDepthDisk;
    }
    
    return TJImageCacheDepthInternet;
}

#pragma mark Cache Manipulation

+ (void)removeImageAtURL:(NSString *)url {
    [[TJImageCache _cache] removeObjectForKey:[TJImageCache hash:url]];
    
    [[NSFileManager defaultManager] removeItemAtPath:[TJImageCache _pathForURL:url] error:nil];
}

+ (void)dumpDiskCache {
    [self auditCacheWithBlock:^BOOL(NSString *hashedURL, NSDate *lastAccess, NSDate *createdDate) {
        return NO;
    }];
}

+ (void)getDiskCacheSize:(void (^)(NSUInteger diskCacheSize))completion
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        NSUInteger fileSize = 0;
        NSDirectoryEnumerator *const enumerator = [[NSFileManager defaultManager] enumeratorAtPath:[self _pathForURL:nil]];
        for (NSURL *fileURL in enumerator) {
#pragma unused(fileURL)
            fileSize += [[[enumerator fileAttributes] objectForKey:NSFileSize] unsignedIntegerValue];
        }
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(fileSize);
            });
        }
    });
}

+ (void)dumpMemoryCache {
    [[TJImageCache _cache] removeAllObjects];
    [[TJImageCache _mapTable] removeAllObjects];
}

#pragma mark Cache Auditing

+ (void)auditCacheWithBlock:(BOOL (^)(NSString *hashedURL, NSDate *lastAccess, NSDate *createdDate))block completionBlock:(void (^)(void))completionBlock {
    NSBlockOperation *auditOperation = [NSBlockOperation blockOperationWithBlock:^{
        NSString *basePath = [TJImageCache _pathForURL:nil];
        NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:basePath error:nil];

        for (NSString *file in files) {
            @autoreleasepool {
                NSString *path = [basePath stringByAppendingPathComponent:file];
                NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
                NSDate *createdDate = [attributes objectForKey:NSFileCreationDate];
                NSDate *lastAccess = [attributes objectForKey:NSFileModificationDate];
                if (!block(file, lastAccess, createdDate)) {
                    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
                }
            }
        }
        
        if (completionBlock) {
            completionBlock();
        }
    }];
    [auditOperation setQualityOfService:NSQualityOfServiceBackground];
    [[TJImageCache _auditQueue] addOperation:auditOperation];
}

+ (void)auditCacheWithBlock:(BOOL (^)(NSString *hashedURL, NSDate *lastAccess, NSDate *createdDate))block {
    [self auditCacheWithBlock:block completionBlock:nil];
}

+ (void)auditCacheRemovingFilesOlderThanDate:(NSDate *)date {
    [TJImageCache auditCacheWithBlock:^BOOL(NSString *hashedURL, NSDate *lastAccess, NSDate *createdDate){
        return ([createdDate compare:date] != NSOrderedAscending);
    }];
}

+ (void)auditCacheRemovingFilesLastAccessedBeforeDate:(NSDate *)date {
    [TJImageCache auditCacheWithBlock:^BOOL(NSString *hashedURL, NSDate *lastAccess, NSDate *createdDate){
        return ([lastAccess compare:date] != NSOrderedAscending);
    }];
}

#pragma mark Private

+ (NSString *)_pathForURL:(NSString *)url {
    NSString *path = nil;
    if (url) {
        NSAssert(tj_imageCacheRootPath != nil, @"Attempting to access disk cache before %@ is configured!", NSStringFromClass([self class]));
        path = [tj_imageCacheRootPath stringByAppendingPathComponent:[TJImageCache hash:url]];
    }
    return path;
}

+ (NSMutableDictionary *)_requestDelegates {
    static NSMutableDictionary *requests = nil;
    static dispatch_once_t token;
    
    dispatch_once(&token, ^{
        requests = [[NSMutableDictionary alloc] init];
    });
    
    return requests;
}

+ (NSCache *)_cache {
    static NSCache *cache = nil;
    static dispatch_once_t token;
    
    dispatch_once(&token, ^{
        cache = [[NSCache alloc] init];
    });
    
    return cache;
}

+ (id)_mapTable {
    static id mapTable = nil;
    static dispatch_once_t token;
    
    dispatch_once(&token, ^{
        if ([NSMapTable class] && [[NSMapTable class] respondsToSelector:@selector(strongToWeakObjectsMapTable)]) {
            mapTable = [NSMapTable strongToWeakObjectsMapTable];
        }
    });
    
    return mapTable;
}

+ (NSOperationQueue *)_networkQueue {
    static NSOperationQueue *queue = nil;
    static dispatch_once_t token;

    dispatch_once(&token, ^{
        queue = [[NSOperationQueue alloc] init];
        [queue setMaxConcurrentOperationCount:1];
    });

    return queue;
}


+ (NSOperationQueue *)_readQueue {
    static NSOperationQueue *queue = nil;
    static dispatch_once_t token;
    
    dispatch_once(&token, ^{
        queue = [[NSOperationQueue alloc] init];
        [queue setMaxConcurrentOperationCount:1];
    });
    
    return queue;
}

+ (NSOperationQueue *)_auditQueue {
    static NSOperationQueue *queue = nil;
    static dispatch_once_t token;
    
    dispatch_once(&token, ^{
        queue = [[NSOperationQueue alloc] init];
        [queue setMaxConcurrentOperationCount:1];
    });
    
    return queue;
}

+ (BOOL)_isHashTableAvailable
{
    static BOOL hashTableAvailable = NO;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        hashTableAvailable = [NSHashTable class] && [[NSHashTable class] respondsToSelector:@selector(weakObjectsHashTable)];
    });
    
    return hashTableAvailable;
}

@end
