#import <Foundation/Foundation.h>

@class UIViewController;

typedef NS_OPTIONS(NSUInteger, DYYYFloatingButtonVisibility) {
    DYYYFloatingButtonVisibilityNone = 0,
    DYYYFloatingButtonVisibilitySpeed = 1 << 0,
    DYYYFloatingButtonVisibilityClear = 1 << 1,
};

// 页面事件只登记事实，两个按钮的 hidden 统一在协调器中更新。
@interface DYYYFloatingButtonCoordinator : NSObject
+ (void)registerInteractionController:(UIViewController *)controller;
+ (UIViewController *)currentInteractionController;
+ (BOOL)isControllerVisible:(UIViewController *)controller;
+ (void)commentController:(UIViewController *)controller visible:(BOOL)visible;
+ (void)pureModeController:(UIViewController *)controller visible:(BOOL)visible;
+ (void)setApplicationActive:(BOOL)active;
+ (void)reloadConfiguration;
+ (void)refresh;
+ (void)setNeedsRefresh;

+ (DYYYFloatingButtonVisibility)visibilityWithPlayback:(BOOL)playback
                                           appActive:(BOOL)appActive
                                             comment:(BOOL)comment
                                            pureMode:(BOOL)pureMode
                                           clearMode:(BOOL)clearMode
                                        speedEnabled:(BOOL)speedEnabled
                                        clearEnabled:(BOOL)clearEnabled
                                    hideSpeedOnClear:(BOOL)hideSpeedOnClear;
@end
