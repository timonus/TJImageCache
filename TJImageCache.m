// TJImageCache
// By Tim Johnsen

#import "TJImageCache.h"
#import <CommonCrypto/CommonDigest.h>

#pragma mark -
#pragma mark TJURLConnection

@interface TJImageCacheConnection : NSURLConnection

@property (nonatomic, retain) NSMutableData *data;
@property (retain) NSMutableArray *delegates;
@property (nonatomic, retain) NSString *url;

+ (TJImageCacheConnection *)connectionWithURL:(NSString *)url delegate:(id)delegate;

@end

@protocol TJURLConnectionDelegate <NSObject>

- (void)connectionDidFinishLoading:(TJImageCacheConnection *)connection;
- (void)connectionDidFail:(TJImageCacheConnection *)connection;

@end

@implementation TJImageCacheConnection : NSURLConnection

@synthesize data;
@synthesize delegates;
@synthesize url;

- (void)dealloc {
	[data release];
	[delegates release];
	[url release];
	
	[super dealloc];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)theData {
	[self.data appendData:theData];
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
	self.data = [NSMutableData data];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
	[TJImageCache connectionDidFinishLoading:self];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
	[TJImageCache connection:self didFailWithError:error];
}

+ (TJImageCacheConnection *)connectionWithURL:(NSString *)url delegate:(id)delegate {
	TJImageCacheConnection *connection = [[TJImageCacheConnection alloc] initWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:url]] delegate:connection];
	
	connection.delegates = [[NSMutableArray alloc] initWithObjects:delegate, nil];
	connection.url = [[url copy] autorelease];
	
	return [connection autorelease];
}

@end

#pragma mark -
#pragma mark TJImageCache

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
	
	// Load from memory
	
	NSString *hash = [TJImageCache _hash:url];
	__block UIImage *image = [[TJImageCache _cache] objectForKey:hash];
	
	// Load from disk
	
	if (!image && depth != TJImageCacheDepthMemory) {
		
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
			image = [UIImage imageWithContentsOfFile:[TJImageCache _pathForURL:url]];
			
			if (image) {
				// tell delegate about success
				[[TJImageCache _cache] setObject:image forKey:hash];
				
				if ([delegate respondsToSelector:@selector(didGetImage:atURL:)]) {
					[delegate didGetImage:image atURL:url];
				}
			} else {
				if (depth == TJImageCacheDepthFull) {
					
					// setup or add to delegate ball wrapped in locks...
					
					dispatch_async(dispatch_get_main_queue(), ^{
						
						// Load from the interwebs using NSURLConnection delegate
						
						// LOCK
						
						if ([[TJImageCache _requests] objectForKey:hash]) {
							if (delegate) {
								[[[[TJImageCache _requests] objectForKey:hash] objectForKey:@"delegates"] addObject:delegate];
							}
						} else {
							[[TJImageCache _requests] setObject:[TJImageCacheConnection connectionWithURL:url delegate:delegate] forKey:hash];
						}
						
						// UNLOCK
						
					});
				} else {
					// tell delegate about failure
					if ([delegate respondsToSelector:@selector(didFailToGetImageAtURL:)]) {
						[delegate didFailToGetImageAtURL:url];
					}
				}
			}
		});
	}
	
	return image;
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

+ (void)removeImageAtURL:(NSString *)url {
	[[TJImageCache _cache] removeObjectForKey:[TJImageCache _hash:url]];
	
	[[NSFileManager defaultManager] removeItemAtPath:[TJImageCache _pathForURL:url] error:nil];
}

+ (void)dumpDiskCache {
	[[NSFileManager defaultManager] removeItemAtPath:[TJImageCache _pathForURL:nil] error:nil];
}

+ (void)dumpMemoryCache {
	[[TJImageCache _cache] removeAllObjects];
}

#pragma mark -
#pragma mark NSURLConnectionDelegate

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
	// LOCK
	
	// UNLOCK
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
	// LOCK
	
	// UNLOCK	
}

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