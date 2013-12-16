# TJImageCache
*Yet another Objective-C image cache.*

This is the image cache I use for [Wootie](http://j.mp/wootie), [Avery](http://itunes.apple.com/us/app/avery/id442157573?mt=8), and other side projects of mine. It's designed for ease-of-use and performance. It uses ARC and should be backwards compatible back to iOS 4, though I haven't tested that and it is definitely backwards compatible with iOS 5.

## Fetching an Image

To fetch an image, use one of the following methods.

1. `+ (UIImage *)imageAtURL:(NSString *)url depth:(TJImageCacheDepth)depth delegate:(id<TJImageCacheDelegate>)delegate`
2. `+ (UIImage *)imageAtURL:(NSString *)url delegate:(id<TJImageCacheDelegate>)delegate`
3. `+ (UIImage *)imageAtURL:(NSString *)url depth:(TJImageCacheDepth)depth`
4. `+ (UIImage *)imageAtURL:(NSString *)url`

In the event that the image is already in memory, each of these methods returns a `UIImage *`. If not, the `TJImageCacheDelegate` methods will be called back on the delegate you provide.

## Auditing

To implement your own cache auditing policy, you can use `+auditCacheWithBlock:(BOOL (^)(NSString *hashedURL, NSDate *lastAccess, NSDate *createdDate))block completionBlock:(void (^)(void))completionBlock`. `block` is invoked for every image the cache knows of on low priority a background thread, returning `NO` from the block means the image will be deleted, returning `YES` means it will be preserved. The completion block is invoked when cache auditing is finished.

There are two convenience methods you can use to remove images based off of age, `+auditCacheRemovingFilesOlderThanDate:` and `+auditCacheRemovingFilesLastAccessedBeforeDate:`. Using these will remove images older than a certain date or images that were last accessed before a certain date respectively.

There's another simple way you can use to clean up the cache if you know all of the images you want to preserve. You can call `+addAuditImageURLToPreserve:` with each image URL you want to keep and then `+commitAuditCache` to clean the cache preserving all images you specified.

## About TJImageCacheDepth

This `depth` parameter is in several of the aforementioned methods, it's an enum used to tell TJImageCache how far into the cache it should go before giving up.

- `TJImageCacheDepthMemory` should be used if you *only* want the cache to check memory for the specified image, when a user is scrolling through a grid of images at a million miles an hour for example.

- `TJImageCacheDepthDisk` should be used if you want TJImageCache to check memory, then the disk subsequently on a cache miss.

- `TJImageCacheDepthInternet` tells TJImageCache to go the whole nine yards checking memory, the disk, then actually fetching the image from the [the tubes](http://en.wikipedia.org/wiki/Series_of_tubes) on cache misses. This is generally what you'll want to use once a user stops scrolling.

# Other Open Source Projects

Fun fact, TJImageCache plays quite nicely with [OLImageView](https://github.com/ondalabs/OLImageView) if you replace `IMAGE_CLASS` with `OLImage` in [TJImageCache.h](https://github.com/tijoinc/TJImageCache/blob/master/TJImageCache.h#L4).
