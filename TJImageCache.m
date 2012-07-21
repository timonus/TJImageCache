// TJImageCache
// By Tim Johnsen

#import "TJImageCache.h"
#import <CommonCrypto/CommonDigest.h>
#import <sys/xattr.h>

#pragma mark -
#pragma mark TJImageCacheConnection

// This class allows for backwards compatibility with NSURLConnection's sendAsynchronousRequest:queue:completionHandler: in iOS 4

@interface TJImageCacheConnection : NSURLConnection

@end

@implementation TJImageCacheConnection

+ (void)sendAsynchronousRequest:(NSURLRequest *)request queue:(NSOperationQueue *)queue completionHandler:(void (^)(NSURLResponse *, NSData *, NSError *))handler {
	
	static BOOL canSendAsync = NO;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		if ([super respondsToSelector:@selector(sendAsynchronousRequest:queue:completionHandler:)]) {
			canSendAsync = YES;
		}
	});
	
	if (canSendAsync) {
		[super sendAsynchronousRequest:request queue:queue completionHandler:handler];
	} else {
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
			NSURLResponse *response = nil;
			NSError *error = nil;
			NSData *data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
			
			[queue addOperationWithBlock:^{
				handler(response, data, error);
			}];
		});
	}
}

@end

#pragma mark -
#pragma mark TJImageCache

@interface TJImageCache ()

+ (void)_createDirectory;
+ (NSString *)_pathForURL:(NSString *)url;

+ (NSMutableDictionary *)_requestDelegates;
+ (NSCache *)_cache;

+ (NSOperationQueue *)_networkQueue;
+ (NSOperationQueue *)_readQueue;
+ (NSOperationQueue *)_writeQueue;

@end

@implementation TJImageCache

#pragma mark -
#pragma mark Hashing

+ (NSString *)hash:(NSString *)string {
	const char* str = [string UTF8String];
    unsigned char result[CC_MD5_DIGEST_LENGTH];
    CC_MD5(str, strlen(str), result);
	
    NSMutableString *ret = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH*2];
    for(int i = 0; i<CC_MD5_DIGEST_LENGTH; i++) {
        [ret appendFormat:@"%02x",result[i]];
    }
    return ret;
}

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
	
	if (!url) {
		return nil;
	}
	
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		[self _createDirectory];
	});
	
	// Load from memory
	
	NSString *hash = [TJImageCache hash:url];
	__block UIImage *image = [[TJImageCache _cache] objectForKey:hash];
	
	// Load from disk
	
	if (!image && depth != TJImageCacheDepthMemory) {
		
		[[TJImageCache _readQueue] addOperationWithBlock:^{
			NSString *path = [TJImageCache _pathForURL:url];
			image = [UIImage imageWithContentsOfFile:path];
			
			if (image) {
				// update last access date
				[[NSFileManager defaultManager] setAttributes:[NSDictionary dictionaryWithObject:[NSDate date] forKey:NSFileModificationDate] ofItemAtPath:path error:nil];
				
				// add to in-memory cache
				[[TJImageCache _cache] setObject:image forKey:hash];
				
				// tell delegate about success
				if ([delegate respondsToSelector:@selector(didGetImage:atURL:)]) {
					[image retain];
					dispatch_async(dispatch_get_main_queue(), ^{
						[delegate didGetImage:image atURL:url];
						[image release];
					});
				}
			} else {
				if (depth == TJImageCacheDepthInternet) {
					
					// setup or add to delegate ball wrapped in locks...
					
					dispatch_async(dispatch_get_main_queue(), ^{
						
						// Load from the interwebs using NSURLConnection delegate
						
						if ([[TJImageCache _requestDelegates] objectForKey:hash]) {
							if (delegate) {
								NSMutableSet *delegatesForConnection = [[TJImageCache _requestDelegates] objectForKey:hash];
								[delegatesForConnection addObject:delegate];
							}
						} else {
							NSMutableSet *delegatesForConnection = [[[NSMutableSet alloc] init] autorelease];
							if (delegate) {
								[delegatesForConnection addObject:delegate];
							}
							
							[[self _requestDelegates] setObject:delegatesForConnection forKey:hash];
							
							[TJImageCacheConnection sendAsynchronousRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:url]] queue:[self _networkQueue] completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
								
								// process image
								UIImage *image = [UIImage imageWithData:data];
								
								if (image) {
									
									// Cache in Memory
									[[TJImageCache _cache] setObject:image forKey:hash];
									
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
										[[TJImageCache _requestDelegates] removeObjectForKey:[TJImageCache hash:url]];
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
										[[TJImageCache _requestDelegates] removeObjectForKey:[TJImageCache hash:url]];
									});
								}
							}];
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

#pragma mark -
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

#pragma mark -
#pragma mark Cache Manipulation

+ (void)removeImageAtURL:(NSString *)url {
	[[TJImageCache _cache] removeObjectForKey:[TJImageCache hash:url]];
	
	[[NSFileManager defaultManager] removeItemAtPath:[TJImageCache _pathForURL:url] error:nil];
}

+ (void)dumpDiskCache {
	[[NSFileManager defaultManager] removeItemAtPath:[TJImageCache _pathForURL:nil] error:nil];
	[self _createDirectory];
}

+ (void)dumpMemoryCache {
	[[TJImageCache _cache] removeAllObjects];
}

#pragma mark -
#pragma mark Cache Auditing

+ (void)auditCacheWithBlock:(BOOL (^)(NSString *hashedURL, NSDate *lastAccess, NSDate *createdDate))block {
	dispatch_sync(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
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
	});
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

#pragma mark -
#pragma mark Private

+ (void)_createDirectory {
	BOOL isDir = NO;
	NSString *path = [TJImageCache _pathForURL:nil];
	if (!([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir] && isDir)) {
		[[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
		
		// Don't back up
		
		const char* filePath = [path fileSystemRepresentation];
		const char* attrName = "com.apple.MobileBackup";
		u_int8_t attrValue = 1;
		setxattr(filePath, attrName, &attrValue, sizeof(attrValue), 0, 0);
	}
}

+ (NSString *)_pathForURL:(NSString *)url {
	static NSString *path = nil;
	static dispatch_once_t token;
	dispatch_once(&token, ^{
		path = [[[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingPathComponent:@"TJImageCache"] retain];
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
		[cache setCountLimit:100];
	});
	
	return cache;
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

@end