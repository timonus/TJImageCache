# TJImageCache

## Configuring

You must configure the cache using either `+configureWithDefaultRootPath` or `+configureWithRootPath:` before attempting to load any images, I recommend doing so in `-application:didFinishLaunchingWithOptions:`. `+configureWithDefaultRootPath` is best if you have a standalone app, but `+configureWithRootPath:` is useful when building extensions.

## Fetching an Image

To fetch an image, use one of the following methods.

1. `+imageAtURL:depth:delegate:backgroundDecode:`
2. `+imageAtURL:depth:delegate:`
3. `+imageAtURL:delegate:`
4. `+imageAtURL:depth:`
5. `+imageAtURL:`

In the event that the image is already in memory, each of these methods returns an image. If not, the `TJImageCacheDelegate` methods will be called back on the delegate you provide.

You can cancel an in-progress image load using `+cancelImageLoadForURL:delegate:`.

## Image Views

TJImageCache comes with some convenience views / categories for working directly with views. There's a few that I've built for different purposes over time.

- `UIImageView+TJImageCache` is a category that adds remote image loading methods to `UIImageView`. It's a simple drop-in solution.
- `TJProgressiveImageView` allows you to specify more than one image to load progressively. The image at index 0 is always loaded with max depth = network, and secondary images are loaded opportunistically with a depth you provide ("disk" depth recommended).
- `TJFastImageView` (Deprecated) is a performance-tuned image view subclass that rounds its contents and adds a stroke around their border off the main thread. This was originally written to make [Opener](http://www.opener.link)'s app icon rendering buttery smooth. Might be a little heavy handed for everyday use. (There's also a `TJFastImageButton` class that has similar innards but for a `UIButton` that I was building for another app, but haven't touched in a long time. Your mileage may vary with that.)
- `TJImageView` is the oldest convenience class this library provides. It may not be super performant, but is also good for general use. It has some niceties like a background color while the image is loading and a fade in animation once it loads.

## Auditing

To implement your own cache auditing policy, you can use `+auditCacheWithBlock:completionBlock:`. `block` is invoked for every image the cache knows of on low priority a background thread, returning `NO` from the block means the image will be deleted, returning `YES` means it will be preserved. The completion block is invoked when cache auditing is finished.

There are two convenience methods you can use to remove images based off of age, `+auditCacheRemovingFilesOlderThanDate:` and `+auditCacheRemovingFilesLastAccessedBeforeDate:`. Using these will remove images older than a certain date or images that were last accessed before a certain date respectively.

## Sizing

`TJImageCache` has a handy feature that automatically tracks changes in its disk cache size. You can observe this using KVO on the `approximateDiskCacheSize` property. This property will be `nil` initially, but it is populated as a result of any of the three following method calls and updated from then on.

- `+auditCache...`
- `+computeDiskCacheSizeIfNeeded`
- `+getDiskCacheSize:`

Most apps will call one of the auditing methods to clean up their cache, which means automatic size tracking will usually happen for free with no additional method calls. If you need a simple, transactional way of getting the size of the cache you can use `+getDiskCacheSize:`.

# Other Notes

- `TJImageCache` plays quite nicely with [OLImageView](https://github.com/ondalabs/OLImageView) if you replace `IMAGE_CLASS` with `OLImage` in [TJImageCache.h](https://github.com/tijoinc/TJImageCache/blob/master/TJImageCache.h#L4). This allows you to load and play animated GIFs.
- You can use `TJImageCache` in macOS apps by replacing `IMAGE_CLASS` with `NSImage`.
