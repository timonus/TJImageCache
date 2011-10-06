// TJImageCache
// By Tim Johnsen

#import "TJImageCache.h"
#import <CommonCrypto/CommonDigest.h>

@interface TJImageCache ()

+ (NSString *)_pathForURL:(NSString *)url;
+ (NSString *)_hash:(NSString *)string;

+ (NSMutableDictionary *)_requests;
+ (NSCache *)_cache;

@end

@implementation TJImageCache

#pragma mark -
#pragma mark Image Fetching

+ (UIImage *)imageAtURL:(NSString *)url delegate:(id<TJImageCacheDelegate>)delegate {
	return [self imageAtURL:url depth:TJImageCacheDepthFull delegate:delegate];
}

+ (UIImage *)imageAtURL:(NSString *)url depth:(TJImageCacheDepth)depth {
	return [self imageAtURL:url depth:depth delegate:nil];
}

+ (UIImage *)imageAtURL:(NSString *)url {
	return [self imageAtURL:url depth:TJImageCacheDepthFull delegate:nil];
}

+ (UIImage *)imageAtURL:(NSString *)url depth:(TJImageCacheDepth)depth delegate:(id<TJImageCacheDelegate>)delegate {
	return nil;
}

#pragma mark -
#pragma mark Cache Checking

- (TJImageCacheDepth)depthForImageAtURL:(NSString *)url {
	
	if ([[TJImageCache _cache] objectForKey:[TJImageCache _hash:url]]) {
		return TJImageCacheDepthMemory;
	}
	
	if ([[NSFileManager defaultManager] fileExistsAtPath:[TJImageCache _pathForURL:url]]) {
		return TJImageCacheDepthDisk;
	}
	
	return TJImageCacheDepthFull;
}

#pragma mark -
#pragma mark Cache Manipulation

- (void)removeImageAtURL:(NSString *)url {
	[[TJImageCache _cache] removeObjectForKey:[TJImageCache _hash:url]];
	
	[[NSFileManager defaultManager] removeItemAtPath:[TJImageCache _pathForURL:url] error:nil];
}

- (void)dumpDiskCache {
	[[NSFileManager defaultManager] removeItemAtPath:[TJImageCache _pathForURL:nil] error:nil];
}

- (void)dumpMemoryCache {
	[[TJImageCache _cache] removeAllObjects];
}

#pragma mark -
#pragma mark NSURLConnectionDelegate

#pragma mark -
#pragma mark Private

+ (NSString *)_pathForURL:(NSString *)url {
	static NSString *path = nil;
	static dispatch_once_t token;
	dispatch_once(&token, ^{
		path = [[NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingPathComponent:@"TJImageCache"];
	});
	
	if (url) {
		return [path stringByAppendingPathComponent:[TJImageCache _hash:url]];
	}
	return path;
}

+ (NSString *)_hash:(NSString *)string {
	const char* str = [string UTF8String];
    unsigned char result[CC_MD5_DIGEST_LENGTH];
    CC_MD5(str, strlen(str), result);
	
    NSMutableString *ret = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH*2];
    for(int i = 0; i<CC_MD5_DIGEST_LENGTH; i++) {
        [ret appendFormat:@"%02x",result[i]];
    }
    return ret;
}

+ (NSMutableDictionary *)_requests {
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

@end