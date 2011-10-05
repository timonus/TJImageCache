// TJImageCache
// By Tim Johnsen

#import "TJImageCache.h"

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
	
}

- (void)dumpMemoryCache {
	
}

#pragma mark -
#pragma mark NSURLConnectionDelegate

#pragma mark -
#pragma mark Private

+ (NSString *)_pathForURL:(NSString *)url {
	return [NSHomeDirectory() stringByAppendingFormat:@"/Library/Caches/%@", [TJImageCache _hash:url]];
}

+ (NSString *)_hash:(NSString *)string {
	return string;
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