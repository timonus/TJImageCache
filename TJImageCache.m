// TJImageCache
// TJImageCache
// By Tim Johnsen

#import "TJImageCache.h"
#import <CommonCrypto/CommonDigest.h>

#pragma mark -
#pragma mark TJImageCacheConnection

@interface TJImageCacheConnection : NSURLConnection

@property (nonatomic, retain) NSMutableData *data;
@property (retain) NSMutableSet *delegates;
@property (nonatomic, retain) NSString *url;

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

@end

#pragma mark -
#pragma mark TJImageCache

@interface TJImageCache ()

+ (NSString *)_pathForURL:(NSString *)url;
+ (NSString *)_hash:(NSString *)string;

+ (NSMutableDictionary *)_requests;
+ (NSRecursiveLock *)_requestLock;
+ (NSCache *)_cache;

@end

@implementation TJImageCache

#pragma mark -
#pragma mark Image Fetching

+ (UIImage *)imageAtURL:(NSString *)url delegate:(id<TJImageCacheDelegate>)delegate {
	return [self imageAtURL:url depth:TJImageCacheDepthInternet delegate:delegate];
}

+ (UIImage *)imageAtURL:(NSString *)url depth:(TJImageCacheDepth)depth {
	return [self imageAtURL:url depth:depth delegate:nil];
}

+ (UIImage *)imageAtURL:(NSString *)url {
	return [self imageAtURL:url depth:TJImageCacheDepthInternet delegate:nil];
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
				if (depth == TJImageCacheDepthInternet) {
					
					// setup or add to delegate ball wrapped in locks...
					
					dispatch_async(dispatch_get_main_queue(), ^{
						
						// Load from the interwebs using NSURLConnection delegate
						
						[[TJImageCache _requestLock] lock];
						
						if ([[TJImageCache _requests] objectForKey:hash]) {
							if (delegate) {
								TJImageCacheConnection *connection = [[TJImageCache _requests] objectForKey:hash];
								[connection.delegates addObject:delegate];
							}
						} else {
							TJImageCacheConnection *connection = [[TJImageCacheConnection alloc] initWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:url]] delegate:[TJImageCache class]];
							connection.url = [[url copy] autorelease];
							connection.delegates = [NSMutableSet setWithObject:delegate];
							
							[[TJImageCache _requests] setObject:connection forKey:hash];
							[connection release];
						}
						
						[[TJImageCache _requestLock] lock];
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
	
	return TJImageCacheDepthInternet;
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

+ (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
	[(TJImageCacheConnection *)connection setData:[NSMutableData data]];
}

+ (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)theData {
	[[(TJImageCacheConnection *)connection data] appendData:theData];
}

+ (void)connectionDidFinishLoading:(NSURLConnection *)connection {
	[[TJImageCache _requestLock] lock];
	
	// process image
	UIImage *image = [UIImage imageWithData:[(TJImageCacheConnection *)connection data]];
	
	if (image) {
		
		NSString *url = [(TJImageCacheConnection *)connection url];
	
		// Cache in Memory
		[[TJImageCache _cache] setObject:image forKey:[TJImageCache _hash:url]];
		
		// Cache to Disk
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
			[UIImagePNGRepresentation(image) writeToFile:[TJImageCache _pathForURL:url] atomically:YES];
		});
		
		// Inform Delegates
		for (id delegate in [(TJImageCacheConnection *)connection delegates]) {
			[delegate didGetImage:image atURL:url];
		}
		
		// Remove the connection
		[[TJImageCache _requests] removeObjectForKey:[TJImageCache _hash:url]];
		
	} else {
		[TJImageCache performSelector:@selector(connection:didFailWithError:) withObject:connection withObject:nil];
	}
	
	[[TJImageCache _requestLock] unlock];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
	[[TJImageCache _requestLock] lock];
	
	NSString *url = [(TJImageCacheConnection *)connection url];
	
	// Inform Delegates
	for (id delegate in [(TJImageCacheConnection *)connection delegates]) {
		[delegate didFailToGetImageAtURL:url];
	}
	
	// Remove the connection
	[[TJImageCache _requests] removeObjectForKey:[TJImageCache _hash:url]];
	
	[[TJImageCache _requestLock] unlock];
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

+ (NSRecursiveLock *)_requestLock {
	static NSRecursiveLock *lock = nil;
	static dispatch_once_t token;
	dispatch_once(&token, ^{
		lock = [[NSRecursiveLock alloc] init];
	});
	
	return lock;
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