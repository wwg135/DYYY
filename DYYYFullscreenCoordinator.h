#import <UIKit/UIKit.h>

/// 只协调播放器容器与评论面板；不修改 Metal 渲染视图。
@interface DYYYFullscreenCoordinator : NSObject
+ (NSString *)buildIdentifier;
+ (BOOL)isImageContentController:(UIViewController *)controller;
+ (void)registerTabBar:(UIView *)tabBar;
+ (void)layoutInteraction:(UIViewController *)controller;
+ (void)layoutInformationLabel:(UIView *)label;
+ (void)rememberInteractionGuide:(UIViewController *)controller;
+ (CGRect)frameForInteractionView:(UIView *)view proposed:(CGRect)frame;
+ (CGRect)frameForPlayer:(UIView *)player proposed:(CGRect)frame;
+ (void)preparePlayer:(UIView *)player;
+ (void)finishPlayer:(UIView *)player;
+ (void)beginCommentInWindow:(UIWindow *)window;
+ (BOOL)hasCommentInWindow:(UIWindow *)window;
+ (void)commentController:(UIViewController *)controller visible:(BOOL)visible;
@end
