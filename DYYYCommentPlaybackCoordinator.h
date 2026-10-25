#import <UIKit/UIKit.h>

@interface DYYYCommentPlaybackCoordinator : NSObject
+ (void)registerViewModel:(id)viewModel;
+ (void)commentController:(UIViewController *)controller visible:(BOOL)visible;
+ (BOOL)ownsPlayback;
+ (BOOL)shouldSkipLifecycle:(UIViewController *)controller;
@end
