//
//  TJImagePriorityLoader.m
//  Wootie
//
//  Created by Tim Johnsen on 6/4/20.
//

#import "TJImagePriorityLoader.h"

@interface TJImagePriorityLoader () <TJImageCacheDelegate>

@property (nonatomic) NSMutableDictionary<NSString *, NSHashTable<id<TJImageCacheDelegate>> *> *delegates;
@property (nonatomic) NSMutableDictionary<NSNumber *, NSMutableSet<NSString *> *> *imageURLsForPriorities;

@end

@implementation TJImagePriorityLoader

- (instancetype)init
{
    if (self = [super init]) {
        self.delegates = [NSMutableDictionary new];
        self.imageURLsForPriorities = [NSMutableDictionary new];
    }
    return self;
}

- (nullable UIImage *)imageAtURL:(NSString *const)url delegate:(nullable const id<TJImageCacheDelegate>)delegate priority:(NSUInteger)priority
{
    UIImage *const image = [TJImageCache imageAtURL:url
                                              depth:TJImageCacheDepthMemory
                                           delegate:self];
    if (!image) {
        NSNumber *const priorityKey = @(priority);
        NSMutableSet<NSString *> *imageURLsForPriority = self.imageURLsForPriorities[priorityKey];
        if (imageURLsForPriority) {
            [imageURLsForPriority addObject:url];
        } else {
            imageURLsForPriority = [NSMutableSet setWithObject:url];
            self.imageURLsForPriorities[priorityKey] = imageURLsForPriority;
        }
        
        NSHashTable<id<TJImageCacheDelegate>> *delegates = self.delegates[url];
        if (!delegates) {
            delegates = [NSHashTable weakObjectsHashTable];
            self.delegates[url] = delegates;
        }
        [delegates addObject:delegate];
        
        // Load next images
        [self _tryProcessNextPriorityImagesRemovingImageURLString:nil];
    }
    
    return image;
}

- (void)didGetImage:(UIImage *)image atURL:(NSString *)url
{
    // Forward message
    for (id<TJImageCacheDelegate> delegate in self.delegates[url]) {
        [delegate didGetImage:image atURL:url];
    }
    [self.delegates removeObjectForKey:url];
    
    // Load next images
    [self _tryProcessNextPriorityImagesRemovingImageURLString:url];
}

- (void)didFailToGetImageAtURL:(NSString *)url
{
    // Forward message
    for (id<TJImageCacheDelegate> delegate in self.delegates[url]) {
        [delegate didFailToGetImageAtURL:url];
    }
    [self.delegates removeObjectForKey:url];
    
    // Load next images
    [self _tryProcessNextPriorityImagesRemovingImageURLString:url];
}

- (void)_tryProcessNextPriorityImagesRemovingImageURLString:(NSString *)imageURLString
{
    if (imageURLString) {
        NSMutableArray *const keysToRemove = [NSMutableArray new];
        [self.imageURLsForPriorities enumerateKeysAndObjectsUsingBlock:^(NSNumber * _Nonnull key, NSMutableSet<NSString *> * _Nonnull obj, BOOL * _Nonnull stop) {
            [obj removeObject:imageURLString];
            if (obj.count == 0) {
                [keysToRemove addObject:key];
            }
        }];
        [self.imageURLsForPriorities removeObjectsForKeys:keysToRemove];
    }
    
    NSMutableIndexSet *const indexSet = [NSMutableIndexSet new];
    for (NSNumber *priorityKey in self.imageURLsForPriorities) {
        [indexSet addIndex:priorityKey.unsignedIntegerValue];
    }
    
    const NSInteger firstIndex = indexSet.firstIndex;
    if (firstIndex != NSNotFound) {
        NSNumber *const priorityKey = @(firstIndex);
        NSLog(@"Initiating load of %@ containing %@", priorityKey, self.imageURLsForPriorities[priorityKey]);
        NSMutableSet<NSString *> *const imageURLs = self.imageURLsForPriorities[priorityKey];
        [self.imageURLsForPriorities removeObjectForKey:priorityKey];
        for (NSString *const urlString in imageURLs) {
            UIImage *const image = [TJImageCache imageAtURL:urlString
                                                      depth:TJImageCacheDepthNetwork
                                                   delegate:self];
            if (image) {
                [self didGetImage:image atURL:urlString];
            }
        }
    }
}

@end
