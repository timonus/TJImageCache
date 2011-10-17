# TJImageCache
*Yet another Objective-C image cache.*

This is a re-imagined version of TJImageDatabase, the image caching system I started with NGadget and have used in numerous other Apps including [Wootie](http://j.mp/wootie) and [Avery](http://itunes.apple.com/us/app/avery/id442157573?mt=8). It's designed for ease-of-use for the developer and to not bog down the system.

## Fetching an Image

To fetch an image, use one of the following methods.

1. `+ (UIImage *)imageAtURL:(NSString *)url depth:(TJImageCacheDepth)depth delegate:(id<TJImageCacheDelegate>)delegate`
2. `+ (UIImage *)imageAtURL:(NSString *)url delegate:(id<TJImageCacheDelegate>)delegate`
3. `+ (UIImage *)imageAtURL:(NSString *)url depth:(TJImageCacheDepth)depth`
4. `+ (UIImage *)imageAtURL:(NSString *)url`

In the event that the image is already in memory, each of these methods returns a `UIImage *`. If not, the `TJImageCacheDelegate` methods will be called back on the delegate you provide.

## About TJImageCacheDepth

This `depth` parameter is in several of the aforementioned methods, it's an enum used to tell TJImageCache how far into the cache it should go before giving up.

- `TJImageCacheDepthMemory` should be used if you *only* want the cache to check memory for the specified image, when a user is scrolling through a grid of images at a million miles an hour for example.

- `TJImageCacheDepthDisk` should be used if you want TJImageCache to check memory, then the disk subsequently on a cache miss.

- `TJImageCacheDepthInternet` tells TJImageCache to go the whole nine yards checking memory, the disk, then actually fetching the image from the [the tubes](http://en.wikipedia.org/wiki/Series_of_tubes) on cache misses. This is generally what you'll want to use once a user stops scrolling.