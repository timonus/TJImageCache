//
//  TJTextAttachment.h
//  Wootie
//
//  Created by Tim Johnsen on 9/5/22.
//

#import <UIKit/UIKit.h>

extern NSString *const kTJTextAttachmentRemoteImageFileType;

NS_ASSUME_NONNULL_BEGIN

@interface TJTextAttachment : NSTextAttachment

- (instancetype)initWithURL:(NSURL *)url;

@end

NS_ASSUME_NONNULL_END
