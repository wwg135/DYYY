#import "DYYYFloatingButtonCoordinator.h"
#import "DYYYFloatClearButton.h"
#import "DYYYFullscreenCoordinator.h"
#import "DYYYFloatSpeedButton.h"
#import <UIKit/UIKit.h>
#import <math.h>

@interface DYYYFloatingButtonCoordinator ()
@property(nonatomic, strong) NSHashTable<UIViewController *> *interactions;
@property(nonatomic, strong) NSHashTable<UIViewController *> *comments;
@property(nonatomic, strong) NSHashTable<UIViewController *> *pureControllers;
@property(nonatomic, assign) BOOL applicationActive;
@property(nonatomic, assign) BOOL refreshScheduled;
@property(nonatomic, assign) BOOL refreshing;
@property(nonatomic, assign) BOOL configurationDirty;
@end

@implementation DYYYFloatingButtonCoordinator

#pragma mark - 唯一显示规则

+ (DYYYFloatingButtonVisibility)visibilityWithPlayback:(BOOL)playback
                                           appActive:(BOOL)appActive
                                             comment:(BOOL)comment
                                            pureMode:(BOOL)pureMode
                                           clearMode:(BOOL)clearMode
                                        speedEnabled:(BOOL)speedEnabled
                                        clearEnabled:(BOOL)clearEnabled
                                    hideSpeedOnClear:(BOOL)hideSpeedOnClear {
    // 清屏状态不能越过页面和前后台限制，消息页始终不显示按钮。
    if (!appActive || !playback) return DYYYFloatingButtonVisibilityNone;
    DYYYFloatingButtonVisibility visibility = DYYYFloatingButtonVisibilityNone;
    if (speedEnabled && (clearMode ? !hideSpeedOnClear : !comment)) {
        visibility |= DYYYFloatingButtonVisibilitySpeed;
    }
    // 清屏时保留退出入口；普通状态下，评论和纯净模式隐藏清屏按钮。
    if (clearEnabled && (clearMode || (!comment && !pureMode))) {
        visibility |= DYYYFloatingButtonVisibilityClear;
    }
    return visibility;
}

#pragma mark - 页面事实

+ (instancetype)sharedCoordinator {
    static DYYYFloatingButtonCoordinator *coordinator;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        coordinator = [[self alloc] init];
        coordinator.interactions = [NSHashTable weakObjectsHashTable];
        coordinator.comments = [NSHashTable weakObjectsHashTable];
        coordinator.pureControllers = [NSHashTable weakObjectsHashTable];
        coordinator.configurationDirty = YES;
        coordinator.applicationActive = UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
        [[NSNotificationCenter defaultCenter] addObserver:coordinator selector:@selector(defaultsDidChange:)
                                                    name:NSUserDefaultsDidChangeNotification object:nil];
    });
    return coordinator;
}

+ (BOOL)isControllerVisible:(UIViewController *)controller {
    UIView *view = controller.viewIfLoaded;
    UIWindow *window = view.window;
    if (!window || window.hidden || CGRectIsEmpty(view.bounds)) return NO;
    for (UIView *ancestor = view; ancestor; ancestor = ancestor.superview) {
        if (ancestor.hidden || ancestor.alpha <= 0.01) return NO;
    }
    CGRect rect = [view convertRect:view.bounds toView:window];
    if (!CGRectIntersectsRect(rect, window.bounds)) return NO;

    // 缓存页面可能仍挂在窗口上，只承认当前选中的 Tab 和导航栈顶。
    for (UIViewController *child = controller; child; child = child.parentViewController) {
        UIViewController *parent = child.parentViewController;
        if ([parent isKindOfClass:UITabBarController.class] && ((UITabBarController *)parent).selectedViewController != child) return NO;
        if ([parent isKindOfClass:UINavigationController.class] && ((UINavigationController *)parent).topViewController != child) return NO;
        UIViewController *presented = child.presentedViewController;
        if (presented.viewIfLoaded.window && !presented.isBeingDismissed) return NO;
    }
    return YES;
}

+ (UIViewController *)currentInteractionController {
    UIViewController *best = nil;
    CGFloat bestArea = 0;
    for (UIViewController *controller in [self sharedCoordinator].interactions) {
        if (![self isControllerVisible:controller]) continue;
        UIView *view = controller.viewIfLoaded;
        CGRect rect = [view convertRect:view.bounds toView:view.window];
        CGRect visible = CGRectIntersection(rect, view.window.bounds);
        CGFloat area = visible.size.width * visible.size.height;
        if (area > bestArea) {
            best = controller;
            bestArea = area;
        }
    }
    return best;
}

+ (void)registerInteractionController:(UIViewController *)controller {
    if (!controller || !NSThread.isMainThread) return;
    [[self sharedCoordinator].interactions addObject:controller];
    [self setNeedsRefresh];
}

+ (void)commentController:(UIViewController *)controller visible:(BOOL)visible {
    if (!controller || !NSThread.isMainThread) return;
    NSHashTable *controllers = [self sharedCoordinator].comments;
    if (visible) [controllers addObject:controller];
    else [controllers removeObject:controller];
    [self refresh];
}

+ (void)pureModeController:(UIViewController *)controller visible:(BOOL)visible {
    if (!controller || !NSThread.isMainThread) return;
    NSHashTable *controllers = [self sharedCoordinator].pureControllers;
    if (visible) [controllers addObject:controller];
    else [controllers removeObject:controller];
    [self refresh];
}

+ (void)setApplicationActive:(BOOL)active {
    [self sharedCoordinator].applicationActive = active;
    [self refresh];
}

#pragma mark - 配置与渲染

- (void)defaultsDidChange:(NSNotification *)notification {
    // 倍速索引、拖动位置等也会产生通知，同一轮主队列只合并刷新一次。
    dispatch_async(dispatch_get_main_queue(), ^{
        self.configurationDirty = YES;
        [DYYYFloatingButtonCoordinator setNeedsRefresh];
    });
}

+ (void)reloadConfiguration {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self reloadConfiguration]; });
        return;
    }
    [self sharedCoordinator].configurationDirty = YES;
    [self refresh];
}

+ (void)setNeedsRefresh {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self setNeedsRefresh]; });
        return;
    }
    DYYYFloatingButtonCoordinator *coordinator = [self sharedCoordinator];
    if (coordinator.refreshScheduled) return;
    coordinator.refreshScheduled = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        coordinator.refreshScheduled = NO;
        [self refresh];
    });
}

- (BOOL)hasVisibleController:(NSHashTable<UIViewController *> *)controllers inWindow:(UIWindow *)window {
    for (UIViewController *controller in controllers) {
        if (controller.viewIfLoaded.window == window && [DYYYFloatingButtonCoordinator isControllerVisible:controller]) return YES;
    }
    return NO;
}

+ (void)refresh {
    if (!NSThread.isMainThread) {
        [self setNeedsRefresh];
        return;
    }
    DYYYFloatingButtonCoordinator *coordinator = [self sharedCoordinator];
    if (coordinator.refreshing) return;
    coordinator.refreshing = YES;
    @try {
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        BOOL configurationChanged = coordinator.configurationDirty;
        if (coordinator.configurationDirty) {
            coordinator.configurationDirty = NO;
            initTargetClassNames();
        }
        // 配置方法只在内容变化时更新外观，不随每次布局重设标题、位置和淡出计时器。
        if (configurationChanged) [FloatingSpeedButton reloadConfiguration];
        // 倍速列表、默认倍速和索引也影响文案，仅配置通知时重算，普通布局不重算。
        if (configurationChanged) updateSpeedButtonUI();
        BOOL clearEnabled = [defaults boolForKey:@"DYYYEnableFloatClearButton"];
        BOOL purificationEnabled = [defaults boolForKey:@"DYYYEnablePure"];
        BOOL needsClearInstance = clearEnabled || purificationEnabled;
        UIViewController *current = [self currentInteractionController];
        UIWindow *window = current.viewIfLoaded.window;
        if (isFloatSpeedButtonEnabled && window) [FloatingSpeedButton attachToWindow:window interactionController:current];
        CGFloat configuredSize = [defaults floatForKey:@"DYYYEnableFloatClearButtonSize"];
        CGFloat clearSize = MIN(MAX(configuredSize > 0 ? configuredSize : 40.0, 20.0), 60.0);
        if (configurationChanged ||
            (needsClearInstance && window && (!hideButton || hideButton.window != window || fabs(hideButton.bounds.size.width - clearSize) > 0.01)) ||
            (!needsClearInstance && hideButton)) {
            reloadClearButtonConfiguration();
        }
        hideButton.homePurificationActive = purificationEnabled && [DYYYFullscreenCoordinator usesRecommendedLayoutForController:current];
        BOOL comment = window && [coordinator hasVisibleController:coordinator.comments inWindow:window];
        BOOL pureMode = window && [coordinator hasVisibleController:coordinator.pureControllers inWindow:window];
        DYYYFloatingButtonVisibility visibility = [self visibilityWithPlayback:current != nil
                                                                   appActive:coordinator.applicationActive
                                                                     comment:comment
                                                                    pureMode:pureMode
                                                                   clearMode:hideButton.isElementsHidden
                                                                speedEnabled:isFloatSpeedButtonEnabled
                                                                clearEnabled:clearEnabled
                                                            hideSpeedOnClear:[defaults boolForKey:@"DYYYHideSpeed"]];
        BOOL speedHidden = !(visibility & DYYYFloatingButtonVisibilitySpeed);
        // 自动净化由设置开关控制；手动清屏入口在离开首页后恢复。
        BOOL clearHidden = hideButton.homePurificationActive || !(visibility & DYYYFloatingButtonVisibilityClear);
        if (speedButton && speedButton.hidden != speedHidden) {
            speedButton.hidden = speedHidden;
            if (!speedHidden) {
                [speedButton resetFadeTimer];
                [speedButton.superview bringSubviewToFront:speedButton];
            }
        }
        if (speedButton.edgeIndicatorView) speedButton.edgeIndicatorView.hidden = speedHidden || !speedButton.isEdgeHidden;
        if (hideButton && hideButton.hidden != clearHidden) {
            hideButton.hidden = clearHidden;
            if (!clearHidden) [hideButton.superview bringSubviewToFront:hideButton];
        }
        if (hideButton.edgeIndicatorView) {
            hideButton.edgeIndicatorView.hidden = clearHidden || !hideButton.isElementsHidden;
        }
    } @finally {
        coordinator.refreshing = NO;
    }
}
@end
