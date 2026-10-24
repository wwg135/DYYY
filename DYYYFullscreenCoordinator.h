#import <UIKit/UIKit.h>

/// 协调推荐页全屏与创作者页分页、互动区；不修改 Metal 渲染视图。
@interface DYYYFullscreenCoordinator : NSObject
+ (NSString *)buildIdentifier;
+ (BOOL)usesRecommendedLayoutForController:(UIViewController *)controller;
+ (BOOL)isCreatorDetailController:(UIViewController *)controller;
+ (CGFloat)bottomInsetForCreator:(CGFloat)inset controller:(UIViewController *)controller;
+ (void)reconcileCreatorPaging:(UIViewController *)controller;
+ (void)layoutCreatorInteraction:(UIViewController *)controller;
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
