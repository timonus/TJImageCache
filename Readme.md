# TJImageCache

## Configuring

You must configure the cache using either `+configureWithDefaultRootPath` or `+configureWithRootPath:` before attempting to load any images, I recommend doing so in `-application:didFinishLaunchingWithOptions:`. `+configureWithDefaultRootPath` is best if you have a standalone app, but `+configureWithRootPath:` is useful when building extensions.

## Fetching an Image

To fetch an image, use one of the following methods.

1. `+imageAtURL:depth:delegate:`
2. `+imageAtURL:delegate:`
3. `+imageAtURL:depth:`
4. `+imageAtURL:`

In the event that the image is already in memory, each of these methods returns an image. If not, the `TJImageCacheDelegate` methods will be called back on the delegate you provide.

## Auditing

To implement your own cache auditing policy, you can use `+auditCacheWithBlock:completionBlock:`. `block` is invoked for every image the cache knows of on low priority a background thread, returning `NO` from the block means the image will be deleted, returning `YES` means it will be preserved. The completion block is invoked when cache auditing is finished.

There are two convenience methods you can use to remove images based off of age, `+auditCacheRemovingFilesOlderThanDate:` and `+auditCacheRemovingFilesLastAccessedBeforeDate:`. Using these will remove images older than a certain date or images that were last accessed before a certain date respectively.

## About TJImageCacheDepth

This `depth` parameter is in several of the aforementioned methods, it's an enum used to tell TJImageCache how far into the cache it should go before giving up.

- `TJImageCacheDepthMemory` should be used if you *only* want the cache to check memory for the specified image, when a user is scrolling through a grid of images at a million miles an hour for example.

- `TJImageCacheDepthDisk` should be used if you want TJImageCache to check memory, then the disk subsequently on a cache miss.

- `TJImageCacheDepthInternet` tells TJImageCache to go the whole nine yards checking memory, the disk, then actually fetching the image from the [the tubes](http://en.wikipedia.org/wiki/Series_of_tubes) on cache misses. This is generally what you'll want to use once a user stops scrolling.

# Other Open Source Projects

Fun fact, TJImageCache plays quite nicely with [OLImageView](https://github.com/ondalabs/OLImageView) if you replace `IMAGE_CLASS` with `OLImage` in [TJImageCache.h](https://github.com/tijoinc/TJImageCache/blob/master/TJImageCache.h#L4).
