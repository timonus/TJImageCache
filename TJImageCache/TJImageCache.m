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
    NSParameterAssert(rootPath);
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
    const char *str = [string UTF8String];
    unsigned char result[CC_MD5_DIGEST_LENGTH];
    CC_MD5(str, (CC_LONG)strlen(str), result);
    
    NSMutableString *ret = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_MD5_DIGEST_LENGTH; i++) {
        [ret appendFormat:@"%02x", result[i]];
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
    
    __block IMAGE_CLASS *inMemoryImage = [[self _cache] objectForKey:urlString];
    
    // Attempt load from map table.
    
    NSString *hash = nil;
    if (!inMemoryImage) {
        hash = [self hash:urlString];
        [self _mapTableWithBlock:^(NSMapTable *mapTable) {
            inMemoryImage = [mapTable objectForKey:hash];
        }];
        if (inMemoryImage) {
            // Propagate back into our cache.
            [[self _cache] setObject:inMemoryImage forKey:urlString];
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
    if ([[self _cache] objectForKey:url]) {
        return TJImageCacheDepthMemory;
    }
    
    NSString *const hash = [self hash:url];
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
    [[self _cache] removeObjectForKey:url];
    NSString *const hash = [self hash:url];
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

/// Keys are image URL strings, NOT hashes
+ (NSCache<NSString *, IMAGE_CLASS *> *)_cache
{
    static NSCache *cache = nil;
    static dispatch_once_t token;
    
    dispatch_once(&token, ^{
        cache = [[NSCache alloc] init];
    });
    
    return cache;
}

/// Keys are image URL string hashes (made using +hash:)
+ (void)_mapTableWithBlock:(void (^)(NSMapTable<NSString *, IMAGE_CLASS *> *mapTable))block
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

/// Keys are image URL string hashes (made using +hash:)
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
        image = [[IMAGE_CLASS alloc] initWithContentsOfFile:path];
        if (forceDecompress) {
            image = [self _predrawnImageFromImage:image];
        }
    }
    if (image) {
        [[self _cache] setObject:image forKey:url];
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

// Taken from https://github.com/Flipboard/FLAnimatedImage/blob/master/FLAnimatedImageDemo/FLAnimatedImage/FLAnimatedImage.m#L641
+ (IMAGE_CLASS *)_predrawnImageFromImage:(IMAGE_CLASS *)imageToPredraw
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

@end
