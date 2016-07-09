// TJImageView
// By Tim Johnsen

#import <UIKit/UIKit.h>

extern const NSTimeInterval kTJImageViewDefaultImageAppearanceAnimationDuration;

@interface TJImageView : UIView

@property (nonatomic, copy) NSString *imageURLString;
@property (nonatomic, strong, readonly) UIImageView *imageView;

@property (nonatomic, assign) NSTimeInterval imageAppearanceAnimationDuration;

@end
