//
//  TJTextAttachment.m
//  Wootie
//
//  Created by Tim Johnsen on 9/5/22.
//

#import "TJTextAttachment.h"
#import "UIImageView+TJImageCache.h"
#import <MobileCoreServices/MobileCoreServices.h>

NSString *const kTJTextAttachmentRemoteImageFileType = @"public.url"; // kUTTypeURL

@interface TJTextAttachmentData : NSObject <NSCoding>

@property (nonatomic) NSURL *url;

//@property (nonatomic) BOOL automaticallyResizeParent;
//
//@property (nonatomic) NSNumber *aspectRatio; // what about container size??

// content mode? sizing properties?

@end

@implementation TJTextAttachmentData

- (instancetype)initWithCoder:(NSCoder *)coder
{
    if (self = [super init]) {
        self.url = [coder decodeObjectOfClass:[NSURL class] forKey:NSStringFromSelector(@selector(url))];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:self.url forKey:NSStringFromSelector(@selector(url))];
}

@end

API_AVAILABLE(ios(15))
@interface TJTextAttachmentViewProvider : NSTextAttachmentViewProvider <TJImageCacheDelegate>

@end

@implementation TJTextAttachmentViewProvider

- (instancetype)initWithTextAttachment:(NSTextAttachment *)textAttachment parentView:(UIView *)parentView textLayoutManager:(NSTextLayoutManager *)textLayoutManager location:(id<NSTextLocation>)location
{
    if (self = [super initWithTextAttachment:textAttachment parentView:parentView textLayoutManager:textLayoutManager location:location]) {
        
    }
    return self;
}

- (void)loadView
{
    UIImageView *imageView = [[UIImageView alloc] init];
    self.view = imageView;
    self.view.backgroundColor = [UIColor lightGrayColor]; // todo: make configurable
    // self resize...
    
    TJTextAttachmentData *data = [NSKeyedUnarchiver unarchiveObjectWithData:self.textAttachment.contents];
//    [imageView tj_setImageURLString:data.url.absoluteString];
//    [TJImageCache imageAtURL:data.url.absoluteString delegate:self];
    UIImage *image = [TJImageCache imageAtURL:data.url.absoluteString delegate:self];
    if (image) {
        [self updateWithImage:image];
    }
}

- (UIView *)parent
{
    for (UIView *view = self.view; view != nil; view = view.superview) {
        if ([view isKindOfClass:[UITextView class]] ||
            [view isKindOfClass:[UILabel class]] ||
            [view isKindOfClass:[UITextField class]]) {
            return view;
        }
    }
    return nil;
}

- (void)didGetImage:(UIImage *)image atURL:(NSString *)url
{
    [self updateWithImage:image];
}

- (void)updateWithImage:(UIImage *)image
{
    [(UIImageView *)self.view setImage:image];
    
    CGRect newBounds = (CGRect){CGPointZero, image.size};
    if (!CGRectEqualToRect(self.textAttachment.bounds, newBounds)) {
        // if (resize parent)
        NSAttributedString *const attr = [(UITextView *)[self parent] attributedText];
        NSMutableAttributedString *const attr2 = [attr mutableCopy];
        
        NSTextAttachment *const updatedAttachment = self.textAttachment;
        updatedAttachment.bounds = newBounds;
        
        [attr enumerateAttribute:NSAttachmentAttributeName inRange:NSMakeRange(0, attr.length) options:0 usingBlock:^(id  _Nullable value, NSRange range, BOOL * _Nonnull stop) {
            if (value == self.textAttachment) {
                // replace
//                [attr2 addAttribute:NSAttachmentAttributeName value:updatedAttachment range:range];
                [attr2 replaceCharactersInRange:range withAttributedString:[NSAttributedString attributedStringWithAttachment:updatedAttachment]];
            }
        }];
        
        [(UITextView *)[self parent] setAttributedText:attr2];
    }
}

@end

@implementation TJTextAttachment

- (instancetype)initWithURL:(NSURL *)url
{
    TJTextAttachmentData *data = [[TJTextAttachmentData alloc] init];
    data.url = url;
    return [self initWithData:[NSKeyedArchiver archivedDataWithRootObject:data requiringSecureCoding:NO error:nil] ofType:kTJTextAttachmentRemoteImageFileType];
}

- (instancetype)initWithData:(NSData *)contentData ofType:(NSString *)uti
{
    if (self = [super initWithData:contentData ofType:uti]) {
        if (@available(iOS 15.0, *)) {
            static dispatch_once_t onceToken;
            dispatch_once(&onceToken, ^{
                [NSTextAttachment registerTextAttachmentViewProviderClass:[TJTextAttachmentViewProvider class] forFileType:(__bridge NSString *)kUTTypeURL];
            });
        }
    }
    return self;
}

@end
