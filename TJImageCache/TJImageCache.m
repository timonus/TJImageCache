// TJImageCache
// By Tim Johnsen

#import "TJImageCache.h"
#import <CommonCrypto/CommonDigest.h>
#import <sys/xattr.h>

#pragma mark - TJTree

@interface TJTreeNode : NSObject {
    NSMutableDictionary *childrenForCharacters;
    BOOL isEnd;
}

- (void)addString:(const char *)hash;
- (BOOL)containsString:(const char *)string;

- (void)reset;

@end

@implementation TJTreeNode

- (void)addString:(const char *)string {
    if (strlen(string) == 0) {
        isEnd = YES;
    } else {
        // Lazily generate our child mapping
        if (!childrenForCharacters) {
            childrenForCharacters = [[NSMutableDictionary alloc] init];
        }
        
        // Lazily add the child node if needed
        NSNumber *key = @(string[0]);
        if (!childrenForCharacters[key]) {
            childrenForCharacters[key] = [[TJTreeNode alloc] init];
        }
        
        // Add string to child starting with next character
        [childrenForCharacters[key] addString:string + 1];
    }
}

- (BOOL)containsString:(const char *)string {
    BOOL containsString = NO;
    if (strlen(string) == 0) {
        containsString = isEnd;
    } else {
        NSNumber *key = @(string[0]);
        containsString = [(TJTreeNode *)childrenForCharacters[key] containsString:string + 1];
    }
    return containsString;
}

- (void)reset {
    childrenForCharacters = nil;
    isEnd = NO;
}

@end

#pragma mark - TJImageCache

@interface TJImageCache ()

+ (void)_createDirectory;
+ (NSString *)_pathForURL:(NSString *)url;

+ (NSMutableDictionary *)_requestDelegates;
+ (NSCache *)_cache;
+ (id)_mapTable;

+ (NSOperationQueue *)_networkQueue;
+ (NSOperationQueue *)_readQueue;
+ (NSOperationQueue *)_writeQueue;

+ (TJTreeNode *)_auditHashTree;

@end

@implementation TJImageCache

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
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [self _createDirectory];
    });
    
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
                // predraw image
                image = [self _predrawnImageFromImage:image];
                
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
                            
                            [[[NSURLSession sharedSession] dataTaskWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:url]] completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                                // process image
                                IMAGE_CLASS *image = [[IMAGE_CLASS alloc] initWithData:data];
                                
                                if (image) {
                                    
                                    // predraw image
                                    image = [self _predrawnImageFromImage:image];
                                    
                                    // Cache in Memory
                                    [[TJImageCache _cache] setObject:image forKey:hash];
                                    [[TJImageCache _mapTable] setObject:image forKey:hash];
                                    
                                    // Cache to Disk
                                    [[TJImageCache _writeQueue] addOperationWithBlock:^{
                                        [data writeToFile:path atomically:YES];
                                    }];
                                    
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

+ (void)dumpMemoryCache {
    [[TJImageCache _cache] removeAllObjects];
    [[TJImageCache _mapTable] removeAllObjects];
}

#pragma mark Cache Auditing

CGFloat const kTJImageCacheAuditThreadPriority = 0.1;

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
    [auditOperation setThreadPriority:kTJImageCacheAuditThreadPriority];
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

const NSUInteger kTJImageCacheAuditHashPrefixLength = 5;

+ (void)addAuditImageURLToPreserve:(NSString *)url {
    NSBlockOperation *addURLOperation = [NSBlockOperation blockOperationWithBlock:^{
        NSString *hash = [[self hash:url] substringToIndex:kTJImageCacheAuditHashPrefixLength];
        const char *string = [hash cStringUsingEncoding:NSUTF8StringEncoding];
        [[self _auditHashTree] addString:string];
    }];
    [addURLOperation setThreadPriority:kTJImageCacheAuditThreadPriority];
    [[TJImageCache _auditQueue] addOperation:addURLOperation];
}

+ (void)commitAuditCache {
    [self auditCacheWithBlock:^BOOL(NSString *hashedURL, NSDate *lastAccess, NSDate *createdDate) {
        hashedURL = [hashedURL substringToIndex:kTJImageCacheAuditHashPrefixLength];
        const char *string = [hashedURL cStringUsingEncoding:NSUTF8StringEncoding];
        return [[self _auditHashTree] containsString:string];
    } completionBlock:^{
        [[self _auditHashTree] reset];
    }];
}

#pragma mark Private

+ (void)_createDirectory {
    BOOL isDir = NO;
    NSString *path = [TJImageCache _pathForURL:nil];
    if (!([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir] && isDir)) {
        [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
        
        // Don't back up
        // https://developer.apple.com/library/ios/qa/qa1719/_index.html
        [[NSURL fileURLWithPath:path] setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
    }
}

+ (NSString *)_pathForURL:(NSString *)url {
    static NSString *path = nil;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        path = [[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingPathComponent:@"TJImageCache"];
    });
    
    if (url) {
        return [path stringByAppendingPathComponent:[TJImageCache hash:url]];
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

+ (NSOperationQueue *)_writeQueue {
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

+ (TJTreeNode *)_auditHashTree {
    static TJTreeNode *rootNode = nil;
    static dispatch_once_t token;
    
    dispatch_once(&token, ^{
        rootNode = [[TJTreeNode alloc] init];
    });
    
    return rootNode;
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

// Taken from https://github.com/Flipboard/FLAnimatedImage/blob/master/FLAnimatedImageDemo/FLAnimatedImage/FLAnimatedImage.m#L641
+ (UIImage *)_predrawnImageFromImage:(UIImage *)imageToPredraw
{
    // Always use a device RGB color space for simplicity and predictability what will be going on.
    CGColorSpaceRef colorSpaceDeviceRGBRef = CGColorSpaceCreateDeviceRGB();
    // Early return on failure!
    if (!colorSpaceDeviceRGBRef) {
        NSLog(@"Failed to `CGColorSpaceCreateDeviceRGB` for image %@", imageToPredraw);
        return imageToPredraw;
    }
    
    // Even when the image doesn't have transparency, we have to add the extra channel because Quartz doesn't support other pixel formats than 32 bpp/8 bpc for RGB:
    // kCGImageAlphaNoneSkipFirst, kCGImageAlphaNoneSkipLast, kCGImageAlphaPremultipliedFirst, kCGImageAlphaPremultipliedLast
    // (source: docs "Quartz 2D Programming Guide > Graphics Contexts > Table 2-1 Pixel formats supported for bitmap graphics contexts")
    size_t numberOfComponents = CGColorSpaceGetNumberOfComponents(colorSpaceDeviceRGBRef) + 1; // 4: RGB + A
    
    // "In iOS 4.0 and later, and OS X v10.6 and later, you can pass NULL if you want Quartz to allocate memory for the bitmap." (source: docs)
    void *data = NULL;
    size_t width = imageToPredraw.size.width;
    size_t height = imageToPredraw.size.height;
    size_t bitsPerComponent = CHAR_BIT;
    
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
    CGColorSpaceRelease(colorSpaceDeviceRGBRef);
    // Early return on failure!
    if (!bitmapContextRef) {
        NSLog(@"Failed to `CGBitmapContextCreate` with color space %@ and parameters (width: %zu height: %zu bitsPerComponent: %zu bytesPerRow: %zu) for image %@", colorSpaceDeviceRGBRef, width, height, bitsPerComponent, bytesPerRow, imageToPredraw);
        return imageToPredraw;
    }
    
    // Draw image in bitmap context and create image by preserving receiver's properties.
    CGContextDrawImage(bitmapContextRef, CGRectMake(0.0, 0.0, imageToPredraw.size.width, imageToPredraw.size.height), imageToPredraw.CGImage);
    CGImageRef predrawnImageRef = CGBitmapContextCreateImage(bitmapContextRef);
    UIImage *predrawnImage = [UIImage imageWithCGImage:predrawnImageRef scale:imageToPredraw.scale orientation:imageToPredraw.imageOrientation];
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