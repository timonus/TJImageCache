// TJImageCache
// By Tim Johnsen

#import "TJImageCache.h"
#import <CommonCrypto/CommonDigest.h>
#import <pthread.h>

static NSString *_tj_imageCacheRootPath;

static NSNumber *_tj_imageCacheBaseSize;
static long long _tj_imageCacheDeltaSize;
static NSNumber *_tj_imageCacheApproximateCacheSize;

@implementation TJImageCache

#pragma mark - Configuration

+ (void)configureWithDefaultRootPath
{
    [self configureWithRootPath:[[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingPathComponent:@"TJImageCache"]];
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
    const char *str = [string UTF8String];
    unsigned char result[CC_MD5_DIGEST_LENGTH];
    CC_MD5(str, (CC_LONG)strlen(str), result);
    
    NSMutableString *ret = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_MD5_DIGEST_LENGTH; i++) {
        [ret appendFormat:@"%02x", result[i]];
    }
    return ret;
}

+ (NSString *)pathForURLString:(NSString *const)urlString
{
    return [self _pathForHash:[self hash:urlString]];
}

#pragma mark - Image Fetching

+ (IMAGE_CLASS *)imageAtURL:(NSString *const)urlString
{
    return [self imageAtURL:urlString depth:TJImageCacheDepthNetwork delegate:nil];
}

+ (IMAGE_CLASS *)imageAtURL:(NSString *const)urlString depth:(const TJImageCacheDepth)depth
{
    return [self imageAtURL:urlString depth:depth delegate:nil];
}

+ (IMAGE_CLASS *)imageAtURL:(NSString *const)urlString delegate:(const id<TJImageCacheDelegate>)delegate
{
    return [self imageAtURL:urlString depth:TJImageCacheDepthNetwork delegate:delegate];
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
            }
        });
    }
    
    // Attempt load from disk and network.
    if (loadAsynchronously) {
        static dispatch_queue_t readQueue = nil;
        static dispatch_once_t readQueueOnceToken;
        dispatch_once(&readQueueOnceToken, ^{
            // NOTE: There could be a perf improvement to be had here using dispatch barriers (https://bit.ly/2FvNNff).
            // The readQueue could be made concurrent, and and writes would have to be added to a dispatch_barrier_sync call like so https://db.tt/1qRAxNvejH (changes marked with *'s)
            // My fear in doing that is that a bunch of threads will be spawned and blocked on I/O.
            readQueue = dispatch_queue_create("TJImageCache disk read queue", DISPATCH_QUEUE_SERIAL_WITH_AUTORELEASE_POOL);
        });
        dispatch_async(readQueue, ^{
            NSString *const hash = [self hash:urlString];
            NSURL *const url = [NSURL URLWithString:urlString];
            const BOOL isFileURL = url.isFileURL;
            NSString *const path = isFileURL ? url.path : [self _pathForHash:hash];
            if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
                // Inform delegates about success
                [self _tryUpdateMemoryCacheAndCallDelegatesForImageAtPath:path url:urlString hash:hash forceDecompress:forceDecompress size:0];

                // Update last access date
                [[NSFileManager defaultManager] setAttributes:[NSDictionary dictionaryWithObject:[NSDate date] forKey:NSFileModificationDate] ofItemAtPath:path error:nil];
            } else if (depth == TJImageCacheDepthNetwork && !isFileURL) {
                static NSURLSession *session = nil;
                static dispatch_once_t sessionOnceToken;
                dispatch_once(&sessionOnceToken, ^{
                    // We use an ephemeral session since TJImageCache does memory and disk caching.
                    // Using NSURLCache would be redundant.
                    session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration]];
                });
                
                [[session downloadTaskWithURL:url completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
                    if (location && path) {
                        // Lazily generate the directory the first time it's written to if needed.
                        static dispatch_once_t rootDirectoryOnceToken;
                        dispatch_once(&rootDirectoryOnceToken, ^{
                            BOOL isDir = NO;
                            if (!([[NSFileManager defaultManager] fileExistsAtPath:_tj_imageCacheRootPath isDirectory:&isDir] && isDir)) {
                                [[NSFileManager defaultManager] createDirectoryAtPath:_tj_imageCacheRootPath withIntermediateDirectories:YES attributes:nil error:nil];
                                
                                // Don't back up
                                // https://developer.apple.com/library/ios/qa/qa1719/_index.html
                                NSURL *const rootURL = _tj_imageCacheRootPath != nil ? [[NSURL alloc] initFileURLWithPath:_tj_imageCacheRootPath isDirectory:YES] : nil;
                                [rootURL setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
                            }
                        });
                        
                        // Move resulting image into place.
                        [[NSFileManager defaultManager] moveItemAtURL:location toURL:[[NSURL alloc] initFileURLWithPath:path isDirectory:NO] error:nil];
                    }
                    // Inform delegates about success or failure
                    [self _tryUpdateMemoryCacheAndCallDelegatesForImageAtPath:path url:urlString hash:hash forceDecompress:forceDecompress size:response.expectedContentLength];
                }] resume];
            } else {
                // Inform delegates about failure
                [self _tryUpdateMemoryCacheAndCallDelegatesForImageAtPath:nil url:urlString hash:hash forceDecompress:forceDecompress size:0];
            }
        });
    }
    
    return inMemoryImage;
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
    
    NSString *const hash = [self hash:urlString];
    if ([[NSFileManager defaultManager] fileExistsAtPath:[self _pathForHash:hash]]) {
        return TJImageCacheDepthDisk;
    }
    
    return TJImageCacheDepthNetwork;
}

+ (void)getDiskCacheSize:(void (^const)(long long diskCacheSize))completion
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        long long fileSize = 0;
        NSDirectoryEnumerator *const enumerator = [[NSFileManager defaultManager] enumeratorAtPath:[self _rootPath]];
        for (NSString *filename in enumerator) {
#pragma unused(filename)
            fileSize += [[[enumerator fileAttributes] objectForKey:NSFileSize] longLongValue];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(fileSize);
            [self _setBaseCacheSize:fileSize];
        });
    });
}

#pragma mark - Cache Manipulation

+ (void)removeImageAtURL:(NSString *const)urlString
{
    [_cache() removeObjectForKey:urlString];
    NSString *const hash = [self hash:urlString];
    _mapTableWithBlock(^(NSMapTable<NSString *, IMAGE_CLASS *> *const mapTable) {
        [mapTable removeObjectForKey:hash];
        [mapTable removeObjectForKey:urlString];
    }, YES);
    NSString *const path = [self _pathForHash:hash];
    const long long fileSize = [[[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil] fileSize];
    if ([[NSFileManager defaultManager] removeItemAtPath:path error:nil]) {
        [self _modifyDeltaSize:-fileSize];
    }
}

+ (void)dumpMemoryCache
{
    [_cache() removeAllObjects];
    _mapTableWithBlock(^(NSMapTable<NSString *, IMAGE_CLASS *> *const mapTable) {
        [mapTable removeAllObjects];
    }, YES);
}

+ (void)dumpDiskCache
{
    [self auditCacheWithBlock:^BOOL(NSString *hashedURL, NSDate *lastAccess, NSDate *createdDate, long long fileSize) {
        return NO;
    }];
}

#pragma mark - Cache Auditing

+ (void)auditCacheWithBlock:(BOOL (^const)(NSString *hashedURL, NSDate *lastAccess, NSDate *createdDate, long long fileSize))block completionBlock:(void (^)(void))completionBlock
{
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0), ^{
        NSDirectoryEnumerator *const enumerator = [[NSFileManager defaultManager] enumeratorAtPath:[self _rootPath]];
        long long totalFileSize = 0;
        for (NSString *file in enumerator) {
            @autoreleasepool {
                NSDictionary *attributes = [enumerator fileAttributes];
                NSDate *createdDate = [attributes objectForKey:NSFileCreationDate];
                NSDate *lastAccess = [attributes objectForKey:NSFileModificationDate];
                long long fileSize = [[attributes objectForKey:NSFileSize] longLongValue];
                __block BOOL isInUse = NO;
                _mapTableWithBlock(^(NSMapTable<NSString *, IMAGE_CLASS *> *const mapTable) {
                    isInUse = [mapTable objectForKey:file] != nil;
                }, NO);
                BOOL wasRemoved = NO;
                if (!isInUse && !block(file, lastAccess, createdDate, fileSize)) {
                    NSString *path = [[self _rootPath] stringByAppendingPathComponent:file];
                    if ([[NSFileManager defaultManager] removeItemAtPath:path error:nil]) {
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
            [self _setBaseCacheSize:totalFileSize];
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

/// Keys are image URL strings, NOT hashes
static NSCache<NSString *, IMAGE_CLASS *> *_cache(void)
{
    static NSCache<NSString *, IMAGE_CLASS *> *cache = nil;
    static dispatch_once_t token;
    
    dispatch_once(&token, ^{
        cache = [[NSCache alloc] init];
    });
    
    return cache;
}

/// Every image maps to two keys in this map table.
/// { image URL string -> image,
///   image URL string hash -> image }
/// Both keys are used so that we can easily query for membership based on either URL (used for in-memory lookups) or hash (used for on disk lookups)
static void _mapTableWithBlock(void (^block)(NSMapTable<NSString *, IMAGE_CLASS *> *const mapTable), const BOOL blockIsWriteOnly)
{
    static NSMapTable<NSString *, IMAGE_CLASS *> *mapTable = nil;
    static dispatch_once_t token;
    static dispatch_queue_t queue = nil;
    
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
    static NSMutableDictionary<NSString *, NSHashTable<id<TJImageCacheDelegate>> *> *requests = nil;
    static dispatch_once_t token;
    static pthread_mutex_t lock;
    
    dispatch_once(&token, ^{
        requests = [[NSMutableDictionary alloc] init];
        pthread_mutex_init(&lock, nil);
    });
    
    pthread_mutex_lock(&lock);
    block(requests);
    pthread_mutex_unlock(&lock);
}

+ (void)_tryUpdateMemoryCacheAndCallDelegatesForImageAtPath:(NSString *const)path url:(NSString *const)urlString hash:(NSString *const)hash forceDecompress:(const BOOL)forceDecompress size:(const long long)size
{
    IMAGE_CLASS *image = nil;
    if (path) {
        image = [[IMAGE_CLASS alloc] initWithContentsOfFile:path];
        if (forceDecompress) {
            image = _predrawnImageFromImage(image);
        }
    }
    if (image) {
        [_cache() setObject:image forKey:urlString];
        _mapTableWithBlock(^(NSMapTable<NSString *, IMAGE_CLASS *> *const mapTable) {
            [mapTable setObject:image forKey:hash];
            [mapTable setObject:image forKey:urlString];
        }, YES);
    }
    __block NSHashTable *delegatesForRequest = nil;
    _requestDelegatesWithBlock(^(NSMutableDictionary<NSString *, NSHashTable<id<TJImageCacheDelegate>> *> *const requestDelegates) {
        delegatesForRequest = [requestDelegates objectForKey:urlString];
        [requestDelegates removeObjectForKey:urlString];
    });
    dispatch_async(dispatch_get_main_queue(), ^{
        for (id<TJImageCacheDelegate> delegate in delegatesForRequest) {
            if (image) {
                [delegate didGetImage:image atURL:urlString];
            } else if ([delegate respondsToSelector:@selector(didFailToGetImageAtURL:)]) {
                [delegate didFailToGetImageAtURL:urlString];
            }
        }
        [self _modifyDeltaSize:size];
    });
}

// Taken from https://github.com/Flipboard/FLAnimatedImage/blob/master/FLAnimatedImageDemo/FLAnimatedImage/FLAnimatedImage.m#L641
static IMAGE_CLASS *_predrawnImageFromImage(IMAGE_CLASS *const imageToPredraw)
{
    // Always use a device RGB color space for simplicity and predictability what will be going on.
    static CGColorSpaceRef colorSpaceDeviceRGBRef = nil;
    static size_t numberOfComponents;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        colorSpaceDeviceRGBRef = CGColorSpaceCreateDeviceRGB();
        
        if (colorSpaceDeviceRGBRef) {
            // Even when the image doesn't have transparency, we have to add the extra channel because Quartz doesn't support other pixel formats than 32 bpp/8 bpc for RGB:
            // kCGImageAlphaNoneSkipFirst, kCGImageAlphaNoneSkipLast, kCGImageAlphaPremultipliedFirst, kCGImageAlphaPremultipliedLast
            // (source: docs "Quartz 2D Programming Guide > Graphics Contexts > Table 2-1 Pixel formats supported for bitmap graphics contexts")
            numberOfComponents = CGColorSpaceGetNumberOfComponents(colorSpaceDeviceRGBRef) + 1; // 4: RGB + A
        }
    });
    // Early return on failure!
    if (!colorSpaceDeviceRGBRef) {
        NSLog(@"Failed to `CGColorSpaceCreateDeviceRGB` for image %@", imageToPredraw);
        return imageToPredraw;
    }
    
    // "In iOS 4.0 and later, and OS X v10.6 and later, you can pass NULL if you want Quartz to allocate memory for the bitmap." (source: docs)
    void *data = NULL;
    size_t width = imageToPredraw.size.width;
    size_t height = imageToPredraw.size.height;
    static const size_t bitsPerComponent = CHAR_BIT;
    
    size_t bitsPerPixel = (bitsPerComponent * numberOfComponents);
    size_t bytesPerPixel = (bitsPerPixel / 8);
    size_t bytesPerRow = (bytesPerPixel * width);
    
    CGBitmapInfo bitmapInfo = kCGBitmapByteOrderDefault;
    
    CGImageAlphaInfo alphaInfo = CGImageGetAlphaInfo(imageToPredraw.CGImage);
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
    bitmapInfo |= alphaInfo;
    
    // Create our own graphics context to draw to; `UIGraphicsGetCurrentContext`/`UIGraphicsBeginImageContextWithOptions` doesn't create a new context but returns the current one which isn't thread-safe (e.g. main thread could use it at the same time).
    // Note: It's not worth caching the bitmap context for multiple frames ("unique key" would be `width`, `height` and `hasAlpha`), it's ~50% slower. Time spent in libRIP's `CGSBlendBGRA8888toARGB8888` suddenly shoots up -- not sure why.
    CGContextRef bitmapContextRef = CGBitmapContextCreate(data, width, height, bitsPerComponent, bytesPerRow, colorSpaceDeviceRGBRef, bitmapInfo);
    // Early return on failure!
    if (!bitmapContextRef) {
        NSLog(@"Failed to `CGBitmapContextCreate` with color space %@ and parameters (width: %zu height: %zu bitsPerComponent: %zu bytesPerRow: %zu) for image %@", colorSpaceDeviceRGBRef, width, height, bitsPerComponent, bytesPerRow, imageToPredraw);
        return imageToPredraw;
    }
    
    // Draw image in bitmap context and create image by preserving receiver's properties.
    CGContextDrawImage(bitmapContextRef, CGRectMake(0.0, 0.0, imageToPredraw.size.width, imageToPredraw.size.height), imageToPredraw.CGImage);
    CGImageRef predrawnImageRef = CGBitmapContextCreateImage(bitmapContextRef);
    IMAGE_CLASS *predrawnImage = [IMAGE_CLASS imageWithCGImage:predrawnImageRef scale:imageToPredraw.scale orientation:imageToPredraw.imageOrientation];
    CGImageRelease(predrawnImageRef);
    CGContextRelease(bitmapContextRef);
    
    // Early return on failure!
    if (!predrawnImage) {
        NSLog(@"Failed to `imageWithCGImage:scale:orientation:` with image ref %@ created with color space %@ and bitmap context %@ and properties and properties (scale: %f orientation: %ld) for image %@", predrawnImageRef, colorSpaceDeviceRGBRef, bitmapContextRef, imageToPredraw.scale, (long)imageToPredraw.imageOrientation, imageToPredraw);
        return imageToPredraw;
    }
    
    return predrawnImage;
}

+ (void)computeDiskCacheSizeIfNeeded
{
    if (!_tj_imageCacheBaseSize) {
        [self getDiskCacheSize:^(long long diskCacheSize) {
            // intentional no-op, cache size is set as a side effect of +getDiskCacheSize: running.
        }];
    }
}

+ (NSNumber *)approximateDiskCacheSize
{
    return _tj_imageCacheApproximateCacheSize;
}

+ (void)_setApproximateCacheSize:(const long long)cacheSize
{
    static NSString *key = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        key = NSStringFromSelector(@selector(approximateDiskCacheSize));
    });
    if (cacheSize != _tj_imageCacheApproximateCacheSize.longLongValue) {
        [self willChangeValueForKey:key];
        _tj_imageCacheApproximateCacheSize = @(cacheSize);
        [self didChangeValueForKey:key];
    }
}

+ (void)_setBaseCacheSize:(const long long)diskCacheSize
{
    _tj_imageCacheBaseSize = @(diskCacheSize);
    _tj_imageCacheDeltaSize = 0;
    [self _setApproximateCacheSize:diskCacheSize];
}

+ (void)_modifyDeltaSize:(const long long)delta
{
    // We don't track in-memory deltas unless a base size has been computed.
    if (_tj_imageCacheBaseSize != nil) {
        _tj_imageCacheDeltaSize += delta;
        [self _setApproximateCacheSize:_tj_imageCacheBaseSize.longLongValue + _tj_imageCacheDeltaSize];
    }
}

@end
