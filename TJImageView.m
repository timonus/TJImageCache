// TJImageView
// By Tim Johnsen

#import "TJImageView.h"
#import "TJImageCache.h"

@interface TJImageView () <TJImageCacheDelegate>

@property (nonatomic, strong) UIImageView *imageView;

@end

@implementation TJImageView

#pragma mark - UIView

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.imageView = [[UIImageView alloc] initWithFrame:self.bounds];
        self.imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:self.imageView];
        
        // Defaults
        self.backgroundColor = [UIColor blackColor];
        self.imageView.contentMode = UIViewContentModeScaleAspectFill;
        self.imageView.opaque = YES;
        self.imageView.clipsToBounds = YES;
    }
    return self;
}

#pragma mark - Properties

- (void)setImageURLString:(NSString *)imageURLString
{
    if (imageURLString != _imageURLString && ![imageURLString isEqualToString:_imageURLString]) {
        _imageURLString = [imageURLString copy];
        
        self.imageView.image = [TJImageCache imageAtURL:imageURLString delegate:self];
        self.imageView.alpha = (self.imageView.image != nil) ? 1.0 : 0.0;
    }
}

#pragma mark - TJImageCacheDelegate

- (void)didGetImage:(UIImage *)image atURL:(NSString *)url
{
    if ([url isEqualToString:self.imageURLString] && !self.imageView.image) {
        self.imageView.image = image;
        [UIView animateWithDuration:0.25 delay:0.0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
            self.imageView.alpha = 1.0;
        } completion:nil];
    }
}

@end
