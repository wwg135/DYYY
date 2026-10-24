#import <UIKit/UIKit.h>

/// 跟随实际评论面板更新材质，并在关闭开关时恢复原生背景。
@interface DYYYCommentBlurCoordinator : NSObject
+ (void)layoutListView:(UIView *)view;
+ (void)layoutTextView:(UIView *)view;
+ (UIColor *)backgroundColorForTextView:(UIView *)view proposed:(UIColor *)color;
+ (BOOL)opaqueForTextView:(UIView *)view proposed:(BOOL)opaque;
+ (void)layoutController:(UIViewController *)controller;
+ (void)layoutDanmuBackground:(UIView *)container controller:(UIViewController *)controller enabled:(BOOL)enabled;
@end
