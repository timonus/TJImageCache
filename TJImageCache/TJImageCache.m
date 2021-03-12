// TJImageCache
// By Tim Johnsen

#import "TJImageCache.h"
#import <CommonCrypto/CommonDigest.h>

static NSString *_tj_imageCacheRootPath;

static NSNumber *_tj_imageCacheBaseSize;
static long long _tj_imageCacheDeltaSize;
static NSNumber *_tj_imageCacheApproximateCacheSize;

#if defined(__has_attribute) && __has_attribute(objc_direct_members)
__attribute__((objc_direct_members))
#endif
@interface TJImageCacheNoOpDelegate : NSObject <TJImageCacheDelegate>

@end

@implementation TJImageCacheNoOpDelegate

- (void)didGetImage:(IMAGE_CLASS *)image atURL:(NSString *)url
{
    // intentional no-op
}

@end

#if defined(__has_attribute) && __has_attribute(objc_direct_members)
__attribute__((objc_direct_members))
#endif
@implementation TJImageCache

#pragma mark - Configuration

+ (void)configureWithDefaultRootPath
{
    [self configureWithRootPath:[[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject] stringByAppendingPathComponent:@"TJImageCache"]];
}

+ (void)configureWithRootPath:(NSString *const)rootPath
{
    NSParameterAssert(rootPath);
    NSAssert(_tj_imageCacheRootPath == nil, @"You should not configure %@'s root path more than once.", NSStringFromClass([self class]));
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _tj_imageCacheRootPath = [rootPath copy];
    });
}

#pragma mark - Hashing

+ (NSString *)hash:(NSString *)string
{
    return TJImageCacheHash(string);
}

NSString *TJImageCacheHash(NSString *string)
{
    unsigned char result[CC_MD5_DIGEST_LENGTH];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    // MD5 deprecated in iOS 13 for security use, but still fine for us.
    CC_MD5([string UTF8String], (CC_LONG)string.length, result);
#pragma clang diagnostic pop
    
    return [NSString stringWithFormat:@"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
            result[0],
            result[1],
            result[2],
            result[3],
            result[4],
            result[5],
            result[6],
            result[7],
            result[8],
            result[9],
            result[10],
            result[11],
            result[12],
            result[13],
            result[14],
            result[15]];
}

+ (NSString *)pathForURLString:(NSString *const)urlString
{
    return _pathForHash(TJImageCacheHash(urlString));
}

#pragma mark - Image Fetching

+ (IMAGE_CLASS *)imageAtURL:(NSString *const)urlString
{
    return [self imageAtURL:urlString depth:TJImageCacheDepthNetwork delegate:nil forceDecompress:NO];
}

+ (IMAGE_CLASS *)imageAtURL:(NSString *const)urlString depth:(const TJImageCacheDepth)depth
{
    return [self imageAtURL:urlString depth:depth delegate:nil forceDecompress:NO];
}

+ (IMAGE_CLASS *)imageAtURL:(NSString *const)urlString delegate:(const id<TJImageCacheDelegate>)delegate
{
    return [self imageAtURL:urlString depth:TJImageCacheDepthNetwork delegate:delegate forceDecompress:NO];
}

+ (IMAGE_CLASS *)imageAtURL:(NSString *const)urlString depth:(const TJImageCacheDepth)depth delegate:(nullable const id<TJImageCacheDelegate>)delegate
{
    return [self imageAtURL:urlString depth:depth delegate:delegate forceDecompress:NO];
}

+ (IMAGE_CLASS *)imageAtURL:(NSString *const)urlString depth:(const TJImageCacheDepth)depth delegate:(nullable const id<TJImageCacheDelegate>)delegate forceDecompress:(const BOOL)forceDecompress
{
    if (urlString.length == 0) {
        return nil;
    }
    
    // Attempt load from cache.
    
    __block IMAGE_CLASS *inMemoryImage = [_cache() objectForKey:urlString];
    
    // Attempt load from map table.
    
    if (!inMemoryImage) {
        _mapTableWithBlock(^(NSMapTable<NSString *, IMAGE_CLASS *> *const mapTable) {
            inMemoryImage = [mapTable objectForKey:urlString];
        }, NO);
        if (inMemoryImage) {
            // Propagate back into our cache.
            [_cache() setObject:inMemoryImage forKey:urlString];
        }
    }
    
    // Check if there's an existing disk/network request running for this image.
    __block BOOL loadAsynchronously = NO;
    if (!inMemoryImage && depth != TJImageCacheDepthMemory) {
        _requestDelegatesWithBlock(^(NSMutableDictionary<NSString *, NSHashTable<id<TJImageCacheDelegate>> *> *const requestDelegates) {
            NSHashTable *delegatesForRequest = [requestDelegates objectForKey:urlString];
            if (!delegatesForRequest) {
                delegatesForRequest = [NSHashTable weakObjectsHashTable];
                [requestDelegates setObject:delegatesForRequest forKey:urlString];
                loadAsynchronously = YES;
            }
            if (delegate) {
                [delegatesForRequest addObject:delegate];
            } else {
                // Since this request was started without a delegate, we add a no-op delegate to ensure that future calls to -cancelImageLoadForURL:delegate: won't inadvertently cancel it.
                static TJImageCacheNoOpDelegate *noOpDelegate;
                static dispatch_once_t onceToken;
                dispatch_once(&onceToken, ^{
                    noOpDelegate = [TJImageCacheNoOpDelegate new];
                });
                [delegatesForRequest addObject:noOpDelegate];
            }
        });
    }
    
    // Attempt load from disk and network.
    if (loadAsynchronously) {
        static dispatch_queue_t readQueue;
        static NSFileManager *fileManager;
        static dispatch_once_t readOnceToken;
        dispatch_once(&readOnceToken, ^{
            // NOTE: There could be a perf improvement to be had here using dispatch barriers (https://bit.ly/2FvNNff).
            // The readQueue could be made concurrent, and and writes would have to be added to a dispatch_barrier_sync call like so https://db.tt/1qRAxNvejH (changes marked with *'s)
            // My fear in doing that is that a bunch of threads will be spawned and blocked on I/O.
            readQueue = dispatch_queue_create("TJImageCache disk read queue", DISPATCH_QUEUE_SERIAL_WITH_AUTORELEASE_POOL);
            
            fileManager = [NSFileManager defaultManager];
        });
        dispatch_async(readQueue, ^{
            NSString *const hash = TJImageCacheHash(urlString);
            NSURL *const url = [NSURL URLWithString:urlString];
            const BOOL isFileURL = url.isFileURL;
            NSString *const path = isFileURL ? url.path : _pathForHash(hash);
            if ([fileManager fileExistsAtPath:path]) {
                _tryUpdateMemoryCacheAndCallDelegates(path, urlString, hash, forceDecompress, 0);

                // Update last access date
                NSURL *const fileURL = isFileURL ? url : [NSURL fileURLWithPath:path isDirectory:NO];
                [fileURL setResourceValue:[NSDate date] forKey:NSURLContentModificationDateKey error:nil];
            } else if (depth == TJImageCacheDepthNetwork && !isFileURL && path) {
                static NSURLSession *session;
                static dispatch_once_t sessionOnceToken;
                dispatch_once(&sessionOnceToken, ^{
                    // We use an ephemeral session since TJImageCache does memory and disk caching.
                    // Using NSURLCache would be redundant.
                    session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration]];
                });
                
                NSMutableURLRequest *const request = [NSMutableURLRequest requestWithURL:url];
                [request setValue:@"image/*" forHTTPHeaderField:@"Accept"];
                NSURLSessionDownloadTask *const task = [session downloadTaskWithRequest:request completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
                    BOOL validToProcess = location != nil && [response isKindOfClass:[NSHTTPURLResponse class]];
                    if (validToProcess) {
                        NSString *contentType;
                        static NSString *const kContentTypeResponseHeaderKey = @"Content-Type";
#if !defined(__IPHONE_13_0) || __IPHONE_OS_VERSION_MIN_REQUIRED < __IPHONE_13_0
                        if (@available(iOS 13.0, *)) {
#endif
                            // -valueForHTTPHeaderField: is more "correct" since it's case-insensitive, however it's only available in iOS 13+.
                            contentType = [(NSHTTPURLResponse *)response valueForHTTPHeaderField:kContentTypeResponseHeaderKey];
#if !defined(__IPHONE_13_0) || __IPHONE_OS_VERSION_MIN_REQUIRED < __IPHONE_13_0
                        } else {
                            contentType = [[(NSHTTPURLResponse *)response allHeaderFields] objectForKey:kContentTypeResponseHeaderKey];
                        }
#endif
                        validToProcess = [contentType hasPrefix:@"image/"];
                    }
                    
                    BOOL success;
                    if (validToProcess) {
                        // Lazily generate the directory the first time it's written to if needed.
                        static dispatch_once_t rootDirectoryOnceToken;
                        dispatch_once(&rootDirectoryOnceToken, ^{
                            if (![fileManager fileExistsAtPath:_tj_imageCacheRootPath isDirectory:nil]) {
                                [fileManager createDirectoryAtPath:_tj_imageCacheRootPath withIntermediateDirectories:YES attributes:nil error:nil];
                                
                                // Don't back up
                                // https://developer.apple.com/library/ios/qa/qa1719/_index.html
                                NSURL *const rootURL = _tj_imageCacheRootPath != nil ? [NSURL fileURLWithPath:_tj_imageCacheRootPath isDirectory:YES] : nil;
                                [rootURL setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
                            }
                        });
                        
                        // Move resulting image into place.
                        success = [fileManager moveItemAtPath:location.path toPath:path error:nil];
                    } else {
                        success = NO;
                    }
                    
                    if (success) {
                        // Inform delegates about success
                        _tryUpdateMemoryCacheAndCallDelegates(path, urlString, hash, forceDecompress, response.expectedContentLength);
                    } else {
                        // Inform delegates about failure
                        _tryUpdateMemoryCacheAndCallDelegates(nil, urlString, hash, forceDecompress, 0);
                    }
                    
                    _tasksForImageURLStringsWithBlock(^(NSMutableDictionary<NSString *,NSURLSessionDownloadTask *> *const tasks) {
                        [tasks removeObjectForKey:urlString];
                    });
                }];
                
                task.countOfBytesClientExpectsToSend = 0;
                
                _tasksForImageURLStringsWithBlock(^(NSMutableDictionary<NSString *,NSURLSessionDownloadTask *> *const tasks) {
                    [tasks setObject:task forKey:urlString];
                });
                
                [task resume];
            } else {
                // Inform delegates about failure
                _tryUpdateMemoryCacheAndCallDelegates(nil, urlString, hash, forceDecompress, 0);
            }
        });
    }
    
    return inMemoryImage;
}

+ (void)cancelImageLoadForURL:(NSString *const)urlString delegate:(const id<TJImageCacheDelegate>)delegate policy:(const TJImageCacheCancellationPolicy)policy
{
    if (_cancelImageProcessing(urlString, delegate)) {
        // NOTE: Could potentially use -getTasksWithCompletionHandler: instead, however that's async.
        _tasksForImageURLStringsWithBlock(^(NSMutableDictionary<NSString *,NSURLSessionDataTask *> *const tasks) {
            NSURLSessionTask *const task = tasks[urlString];
            if (task) {
                switch (policy) {
                    case TJImageCacheCancellationPolicyBeforeResponse:
                        if (task.response) {
                            break;
                        }
                    case TJImageCacheCancellationPolicyBeforeBody:
                        if (task.countOfBytesReceived > 0) {
                            break;
                        }
                    case TJImageCacheCancellationPolicyUnconditional:
                        [task cancel];
                    case TJImageCacheCancellationPolicyImageProcessing:
                        break;
                }
            }
        });
    }
}

static BOOL _cancelImageProcessing(NSString *const urlString, const id<TJImageCacheDelegate>delegate)
{
    __block BOOL cancelTask = NO;
    _requestDelegatesWithBlock(^(NSMutableDictionary<NSString *,NSHashTable<id<TJImageCacheDelegate>> *> *const requestDelegates) {
        NSHashTable *const delegates = [requestDelegates objectForKey:urlString];
        if (delegates) {
            [delegates removeObject:delegate];
            if (delegates.count == 0) {
                [requestDelegates removeObjectForKey:urlString];
                cancelTask = YES;
            }
        }
    });
    return cancelTask;
}

#pragma mark - Cache Checking

+ (TJImageCacheDepth)depthForImageAtURL:(NSString *const)urlString
{
    if ([_cache() objectForKey:urlString]) {
        return TJImageCacheDepthMemory;
    }
    
    __block BOOL isImageInMapTable = NO;
    _mapTableWithBlock(^(NSMapTable<NSString *, IMAGE_CLASS *> *const mapTable) {
        isImageInMapTable = [mapTable objectForKey:urlString] != nil;
    }, NO);
    
    if (isImageInMapTable) {
        return TJImageCacheDepthMemory;
    }
    
    NSString *const hash = TJImageCacheHash(urlString);
    if ([[NSFileManager defaultManager] fileExistsAtPath:_pathForHash(hash)]) {
        return TJImageCacheDepthDisk;
    }
    
    return TJImageCacheDepthNetwork;
}

+ (void)getDiskCacheSize:(void (^const)(long long diskCacheSize))completion
{
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        long long fileSize = 0;
        NSDirectoryEnumerator *const enumerator = [[NSFileManager defaultManager] enumeratorAtPath:_rootPath()];
        for (NSString *filename in enumerator) {
#pragma unused(filename)
            fileSize += enumerator.fileAttributes.fileSize;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(fileSize);
            _setBaseCacheSize(fileSize);
        });
    });
}

#pragma mark - Cache Manipulation

+ (void)removeImageAtURL:(NSString *const)urlString
{
    [_cache() removeObjectForKey:urlString];
    NSString *const path = _pathForHash(TJImageCacheHash(urlString));
    NSNumber *fileSizeNumber;
    [[NSURL fileURLWithPath:path] getResourceValue:&fileSizeNumber forKey:NSURLTotalFileSizeKey error:nil];
    if ([[NSFileManager defaultManager] removeItemAtPath:path error:nil]) {
        _modifyDeltaSize(-fileSizeNumber.longLongValue);
    }
}

+ (void)dumpMemoryCache
{
    [_cache() removeAllObjects];
}

+ (void)dumpDiskCache
{
    [self auditCacheWithBlock:^BOOL(NSString *hashedURL, NSDate *lastAccess, NSDate *createdDate, long long fileSize) {
        return NO;
    }];
}

#pragma mark - Cache Auditing

+ (void)auditCacheWithBlock:(BOOL (^const)(NSString *hashedURL, NSDate *lastAccess, NSDate *createdDate, long long fileSize))block completionBlock:(dispatch_block_t)completionBlock
{
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0), ^{
        NSFileManager *const fileManager = [NSFileManager defaultManager];
        NSDirectoryEnumerator *const enumerator = [fileManager enumeratorAtPath:_rootPath()];
        long long totalFileSize = 0;
        for (NSString *file in enumerator) {
            @autoreleasepool {
                NSDictionary *attributes = [enumerator fileAttributes];
                NSDate *createdDate = [attributes objectForKey:NSFileCreationDate];
                NSDate *lastAccess = [attributes objectForKey:NSFileModificationDate];
                long long fileSize = [[attributes objectForKey:NSFileSize] longLongValue];
                __block BOOL isInUse = NO;
                NSString *const key = [file substringToIndex:9];
                _mapTableWithBlock(^(NSMapTable<NSString *, IMAGE_CLASS *> *const mapTable) {
                    isInUse = [mapTable objectForKey:key] != nil;
                }, NO);
                BOOL wasRemoved = NO;
                if (!isInUse && !block(file, lastAccess, createdDate, fileSize)) {
                    NSString *const path = _pathForHash(file);
                    if ([fileManager removeItemAtPath:path error:nil]) {
                        wasRemoved = YES;
                    }
                }
                if (!wasRemoved) {
                    totalFileSize += fileSize;
                }
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completionBlock) {
                completionBlock();
            }
            _setBaseCacheSize(totalFileSize);
        });
    });
}

+ (void)auditCacheWithBlock:(BOOL (^const)(NSString *hashedURL, NSDate *lastAccess, NSDate *createdDate, long long fileSize))block
{
    [self auditCacheWithBlock:block completionBlock:nil];
}

+ (void)auditCacheRemovingFilesOlderThanDate:(NSDate *const)date
{
    [self auditCacheWithBlock:^BOOL(NSString *hashedURL, NSDate *lastAccess, NSDate *createdDate, long long fileSize) {
        return ([createdDate compare:date] != NSOrderedAscending);
    }];
}

+ (void)auditCacheRemovingFilesLastAccessedBeforeDate:(NSDate *const)date
{
    [self auditCacheWithBlock:^BOOL(NSString *hashedURL, NSDate *lastAccess, NSDate *createdDate, long long fileSize) {
        return ([lastAccess compare:date] != NSOrderedAscending);
    }];
}

#pragma mark - Private

static NSString *_rootPath(void)
{
    NSCAssert(_tj_imageCacheRootPath != nil, @"You should configure %@'s root path before attempting to use it.", NSStringFromClass([TJImageCache class]));
    return _tj_imageCacheRootPath;
}

static NSString *_pathForHash(NSString *const hash)
{
    NSString *path = _rootPath();
    if (hash) {
        path = [path stringByAppendingPathComponent:hash];
    }
    return path;
}

/// Keys are image URL strings, NOT hashes
static NSCache<NSString *, IMAGE_CLASS *> *_cache(void)
{
    static NSCache<NSString *, IMAGE_CLASS *> *cache;
    static dispatch_once_t token;
    
    dispatch_once(&token, ^{
        cache = [NSCache new];
    });
    
    return cache;
}

/// Every image maps to two keys in this map table.
/// { image URL string -> image,
///   image URL string hash truncated to 9 characters -> image }
/// Both keys are used so that we can easily query for membership based on either URL (used for in-memory lookups) or hash (used for on-disk lookups)
/// Hashes are truncated to 9 characters so they'll fit into tagged pointer strings https://www.mikeash.com/pyblog/friday-qa-2015-07-31-tagged-pointer-strings.html.
static void _mapTableWithBlock(void (^block)(NSMapTable<NSString *, IMAGE_CLASS *> *const mapTable), const BOOL blockIsWriteOnly)
{
    static NSMapTable<NSString *, IMAGE_CLASS *> *mapTable;
    static dispatch_once_t token;
    static dispatch_queue_t queue;
    
    dispatch_once(&token, ^{
        mapTable = [NSMapTable strongToWeakObjectsMapTable];
        queue = dispatch_queue_create("TJImageCache map table queue", DISPATCH_QUEUE_CONCURRENT);
    });
    
    if (blockIsWriteOnly) {
        dispatch_barrier_async(queue, ^{
            block(mapTable);
        });
    } else {
        dispatch_sync(queue, ^{
            block(mapTable);
        });
    }
}

/// Keys are image URL strings
static void _requestDelegatesWithBlock(void (^block)(NSMutableDictionary<NSString *, NSHashTable<id<TJImageCacheDelegate>> *> *const requestDelegates))
{
    static NSMutableDictionary<NSString *, NSHashTable<id<TJImageCacheDelegate>> *> *requests;
    static dispatch_once_t token;
    static dispatch_queue_t queue;
    
    dispatch_once(&token, ^{
        requests = [NSMutableDictionary new];
        queue = dispatch_queue_create("TJImageCache._requestDelegatesWithBlock", DISPATCH_QUEUE_SERIAL);
    });
    
    dispatch_sync(queue, ^{
        block(requests);
    });
}

/// Keys are image URL strings
static void _tasksForImageURLStringsWithBlock(void (^block)(NSMutableDictionary<NSString *, NSURLSessionDownloadTask *> *const tasks))
{
    static NSMutableDictionary<NSString *, NSURLSessionDownloadTask *> *tasks;
    static dispatch_once_t token;
    static dispatch_queue_t queue;
    
    dispatch_once(&token, ^{
        tasks = [NSMutableDictionary new];
        queue = dispatch_queue_create("TJImageCache._tasksForImageURLStringsWithBlock", DISPATCH_QUEUE_SERIAL);
    });
    
    dispatch_sync(queue, ^{
        block(tasks);
    });
}

static void _tryUpdateMemoryCacheAndCallDelegates(NSString *const path, NSString *const urlString, NSString *const hash, const BOOL forceDecompress, const long long size)
{
    __block NSHashTable *delegatesForRequest = nil;
    _requestDelegatesWithBlock(^(NSMutableDictionary<NSString *, NSHashTable<id<TJImageCacheDelegate>> *> *const requestDelegates) {
        delegatesForRequest = [requestDelegates objectForKey:urlString];
        [requestDelegates removeObjectForKey:urlString];
    });
    
    const BOOL canProcess = delegatesForRequest.count > 0;
    
    IMAGE_CLASS *image = nil;
    if (canProcess) {
        if (path) {
            if (forceDecompress) {
                image = _predrawnImageFromPath(path);
            }
            if (!image) {
                image = [IMAGE_CLASS imageWithContentsOfFile:path];
            }
        }
        if (image) {
            [_cache() setObject:image forKey:urlString];
            NSString *const key = [hash substringToIndex:9];
            _mapTableWithBlock(^(NSMapTable<NSString *, IMAGE_CLASS *> *const mapTable) {
                [mapTable setObject:image forKey:key];
                [mapTable setObject:image forKey:urlString];
            }, YES);
        }
    }
    // else { Skip drawing / updating cache / calling delegates since the result wouldn't be used }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        for (id<TJImageCacheDelegate> delegate in delegatesForRequest) {
            if (image) {
                [delegate didGetImage:image atURL:urlString];
            } else if ([delegate respondsToSelector:@selector(didFailToGetImageAtURL:)]) {
                [delegate didFailToGetImageAtURL:urlString];
            }
        }
        _modifyDeltaSize(size);
    });
    
    // Per this WWDC talk, dump as much memory as possible when entering the background to avoid jetsam.
    // https://developer.apple.com/videos/play/wwdc2020/10078/?t=333
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        void (^emptyCacheBlock)(NSNotification *) = ^(NSNotification * _Nonnull note) {
            [TJImageCache dumpMemoryCache];
        };
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:nil usingBlock:emptyCacheBlock];
        [[NSNotificationCenter defaultCenter] addObserverForName:NSExtensionHostDidEnterBackgroundNotification object:nil queue:nil usingBlock:emptyCacheBlock];
    });
}

// Modified version of https://github.com/Flipboard/FLAnimatedImage/blob/master/FLAnimatedImageDemo/FLAnimatedImage/FLAnimatedImage.m#L641
static IMAGE_CLASS *_predrawnImageFromPath(NSString *const path)
{
    // Always use a device RGB color space for simplicity and predictability what will be going on.
    static CGColorSpaceRef colorSpaceDeviceRGBRef;
    static size_t numberOfComponents;
    static CFDictionaryRef options;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        colorSpaceDeviceRGBRef = CGColorSpaceCreateDeviceRGB();
        
        if (colorSpaceDeviceRGBRef) {
            // Even when the image doesn't have transparency, we have to add the extra channel because Quartz doesn't support other pixel formats than 32 bpp/8 bpc for RGB:
            // kCGImageAlphaNoneSkipFirst, kCGImageAlphaNoneSkipLast, kCGImageAlphaPremultipliedFirst, kCGImageAlphaPremultipliedLast
            // (source: docs "Quartz 2D Programming Guide > Graphics Contexts > Table 2-1 Pixel formats supported for bitmap graphics contexts")
            numberOfComponents = CGColorSpaceGetNumberOfComponents(colorSpaceDeviceRGBRef) + 1; // 4: RGB + A
        }
        
        options = (__bridge_retained CFDictionaryRef)@{(__bridge NSString *)kCGImageSourceShouldCache: (__bridge id)kCFBooleanFalse};
    });
    
    const CGImageSourceRef imageSource = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], nil);
    if (!imageSource) {
        return nil;
    }
    
    if (CGImageSourceGetCount(imageSource) == 0) {
        CFRelease(imageSource);
        return nil;
    }
    
    const CGImageRef image = CGImageSourceCreateImageAtIndex(imageSource, 0, options);
    
    CFRelease(imageSource);
    
    if (!image) {
        return nil;
    }
    
    // "In iOS 4.0 and later, and OS X v10.6 and later, you can pass NULL if you want Quartz to allocate memory for the bitmap." (source: docs)
    void *data = NULL;
    const size_t width = CGImageGetWidth(image);
    const size_t height = CGImageGetHeight(image);
    static const size_t bitsPerComponent = CHAR_BIT;
    
    const size_t bytesPerRow = (((bitsPerComponent * numberOfComponents) / 8) * width);
    
    CGImageAlphaInfo alphaInfo = CGImageGetAlphaInfo(image);
    // If the alpha info doesn't match to one of the supported formats (see above), pick a reasonable supported one.
    // "For bitmaps created in iOS 3.2 and later, the drawing environment uses the premultiplied ARGB format to store the bitmap data." (source: docs)
    if (alphaInfo == kCGImageAlphaNone || alphaInfo == kCGImageAlphaOnly) {
        alphaInfo = kCGImageAlphaNoneSkipFirst;
    } else if (alphaInfo == kCGImageAlphaFirst) {
        // Hack to strip alpha
        // http://stackoverflow.com/a/21416518/3943258
        //        alphaInfo = kCGImageAlphaPremultipliedFirst;
        alphaInfo = kCGImageAlphaNoneSkipFirst;
    } else if (alphaInfo == kCGImageAlphaLast) {
        // Hack to strip alpha
        // http://stackoverflow.com/a/21416518/3943258
        //        alphaInfo = kCGImageAlphaPremultipliedLast;
        alphaInfo = kCGImageAlphaNoneSkipLast;
    }
    // "The constants for specifying the alpha channel information are declared with the `CGImageAlphaInfo` type but can be passed to this parameter safely." (source: docs)
    const CGBitmapInfo bitmapInfo = kCGBitmapByteOrderDefault | alphaInfo;
    
    // Create our own graphics context to draw to; `UIGraphicsGetCurrentContext`/`UIGraphicsBeginImageContextWithOptions` doesn't create a new context but returns the current one which isn't thread-safe (e.g. main thread could use it at the same time).
    // Note: It's not worth caching the bitmap context for multiple frames ("unique key" would be `width`, `height` and `hasAlpha`), it's ~50% slower. Time spent in libRIP's `CGSBlendBGRA8888toARGB8888` suddenly shoots up -- not sure why.
    
    const CGContextRef bitmapContextRef = CGBitmapContextCreate(data, width, height, bitsPerComponent, bytesPerRow, colorSpaceDeviceRGBRef, bitmapInfo);
    // Early return on failure!
    if (!bitmapContextRef) {
        NSCAssert(NO, @"Failed to `CGBitmapContextCreate` with color space %@ and parameters (width: %zu height: %zu bitsPerComponent: %zu bytesPerRow: %zu) for image %@", colorSpaceDeviceRGBRef, width, height, bitsPerComponent, bytesPerRow, image);
        return nil;
    }
    
    // Draw image in bitmap context and create image by preserving receiver's properties.
    CGContextDrawImage(bitmapContextRef, CGRectMake(0.0, 0.0, width, height), image);
    const CGImageRef predrawnImageRef = CGBitmapContextCreateImage(bitmapContextRef);
    IMAGE_CLASS *predrawnImage = [IMAGE_CLASS imageWithCGImage:predrawnImageRef];
    CGImageRelease(image);
    CGImageRelease(predrawnImageRef);
    CGContextRelease(bitmapContextRef);
    
    return predrawnImage;
}

+ (void)computeDiskCacheSizeIfNeeded
{
    if (_tj_imageCacheBaseSize == nil) {
        [self getDiskCacheSize:^(long long diskCacheSize) {
            // intentional no-op, cache size is set as a side effect of +getDiskCacheSize: running.
        }];
    }
}

+ (NSNumber *)approximateDiskCacheSize
{
    return _tj_imageCacheApproximateCacheSize;
}

static void _setApproximateCacheSize(const long long cacheSize)
{
    static NSString *key;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        key = NSStringFromSelector(@selector(approximateDiskCacheSize));
    });
    if (cacheSize != _tj_imageCacheApproximateCacheSize.longLongValue) {
        [TJImageCache willChangeValueForKey:key];
        _tj_imageCacheApproximateCacheSize = @(cacheSize);
        [TJImageCache didChangeValueForKey:key];
    }
}

static void _setBaseCacheSize(const long long diskCacheSize)
{
    _tj_imageCacheBaseSize = @(diskCacheSize);
    _tj_imageCacheDeltaSize = 0;
    _setApproximateCacheSize(diskCacheSize);
}

static void _modifyDeltaSize(const long long delta)
{
    // We don't track in-memory deltas unless a base size has been computed.
    if (_tj_imageCacheBaseSize != nil) {
        _tj_imageCacheDeltaSize += delta;
        _setApproximateCacheSize(_tj_imageCacheBaseSize.longLongValue + _tj_imageCacheDeltaSize);
    }
}

@end
