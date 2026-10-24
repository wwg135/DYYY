#import "DYYYFloatingButtonCoordinator.h"
#import "DYYYFloatSpeedButton.h"
#import "DYYYFloatClearButton.h"
#import <assert.h>

@interface UIView ()
@property(nonatomic, strong) NSMutableArray<UIView *> *children;
@end
@implementation UIView
- (instancetype)init {
    if ((self = [super init])) {
        _alpha = 1;
        _bounds = _frame = CGRectMake(0, 0, 414, 896);
        _children = [NSMutableArray array];
    }
    return self;
}
- (NSArray *)subviews { return self.children; }
- (UIWindow *)window { return [self isKindOfClass:UIWindow.class] ? (UIWindow *)self : self.superview.window; }
- (void)addSubview:(UIView *)view {
    [view removeFromSuperview];
    [self.children addObject:view];
    view.superview = self;
}
- (void)removeFromSuperview {
    [self.superview.children removeObject:self];
    self.superview = nil;
}
- (void)bringSubviewToFront:(UIView *)view {
    [self.children removeObject:view];
    [self.children addObject:view];
}
- (CGRect)convertRect:(CGRect)rect toView:(UIView *)target {
    for (UIView *view = self; view && view != target; view = view.superview) {
        rect = CGRectOffset(rect, view.frame.origin.x, view.frame.origin.y);
    }
    return rect;
}
@end
@implementation UIWindow @end
@implementation UIButton @end
@implementation UIViewController @end
@implementation UINavigationController @end
@implementation UITabBarController @end
@implementation UIApplication
+ (instancetype)sharedApplication {
    static UIApplication *app;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ app = [self new]; });
    return app;
}
@end

FloatingSpeedButton *speedButton;
HideUIButton *hideButton;
BOOL isFloatSpeedButtonEnabled;
static UIWindow *testWindow;
static NSUInteger attachments;
static NSUInteger titleUpdates;

// 用真实协调器计算页面与显示状态；按钮外观、清屏内容和 UIKit 动画由夹具替代。
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wincomplete-implementation"
@implementation FloatingSpeedButton
+ (void)reloadConfiguration {
    isFloatSpeedButtonEnabled = [NSUserDefaults.standardUserDefaults boolForKey:@"DYYYEnableFloatSpeedButton"];
}
+ (void)attachToWindow:(UIWindow *)window interactionController:(UIViewController *)controller {
    if (!speedButton) { speedButton = [self new]; speedButton.hidden = YES; }
    speedButton.interactionController = controller;
    if (speedButton.window != window) { [window addSubview:speedButton]; attachments++; }
}
- (void)resetFadeTimer {}
@end
@implementation HideUIButton @end
#pragma clang diagnostic pop
void initTargetClassNames(void) {}
void updateSpeedButtonUI(void) { titleUpdates++; }
void reloadClearButtonConfiguration(void) {
    if (![NSUserDefaults.standardUserDefaults boolForKey:@"DYYYEnableFloatClearButton"]) {
        [hideButton removeFromSuperview];
        hideButton = nil;
        return;
    }
    if (!hideButton) { hideButton = [HideUIButton new]; hideButton.hidden = YES; }
    CGFloat size = [NSUserDefaults.standardUserDefaults floatForKey:@"DYYYEnableFloatClearButtonSize"] ?: 40;
    hideButton.bounds = CGRectMake(0, 0, size, size);
    if (hideButton.window != testWindow) [testWindow addSubview:hideButton];
}

static UIViewController *controllerIn(UIViewController *parent, UIView *view) {
    UIViewController *controller = [UIViewController new];
    controller.parentViewController = parent;
    controller.viewIfLoaded = view;
    return controller;
}

static void expectButtons(BOOL speed, BOOL clear) {
    [DYYYFloatingButtonCoordinator refresh];
    assert((speedButton && !speedButton.hidden) == speed);
    assert((hideButton && !hideButton.hidden) == clear);
}

int main(void) {
    @autoreleasepool {
        // 256 种开关/页面组合；页面与前后台限制始终优先于清屏。
        // 索引位依次是评论、纯净、清屏、清屏隐藏倍速；值为产品规则的期望按钮掩码。
        const NSUInteger expectedContexts[16] = {3, 0, 1, 0, 3, 3, 3, 3, 3, 0, 1, 0, 2, 2, 2, 2};
        for (unsigned state = 0; state < 256; state++) {
            BOOL playback = state & 1, active = state & 2, comment = state & 4, pure = state & 8;
            BOOL clear = state & 16, speedEnabled = state & 32, clearEnabled = state & 64, hideSpeed = state & 128;
            NSUInteger actual = [DYYYFloatingButtonCoordinator visibilityWithPlayback:playback appActive:active comment:comment pureMode:pure
                                                                           clearMode:clear speedEnabled:speedEnabled clearEnabled:clearEnabled hideSpeedOnClear:hideSpeed];
            NSUInteger context = (comment ? 1 : 0) | (pure ? 2 : 0) | (clear ? 4 : 0) | (hideSpeed ? 8 : 0);
            NSUInteger enabled = (speedEnabled ? DYYYFloatingButtonVisibilitySpeed : 0) | (clearEnabled ? DYYYFloatingButtonVisibilityClear : 0);
            NSUInteger expected = playback && active ? expectedContexts[context] & enabled : 0;
            assert(actual == expected);
        }

        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        [defaults setBool:YES forKey:@"DYYYEnableFloatSpeedButton"];
        [defaults setBool:YES forKey:@"DYYYEnableFloatClearButton"];
        testWindow = [UIWindow new];
        UITabBarController *tabs = [UITabBarController new];
        UINavigationController *home = [UINavigationController new];
        home.parentViewController = tabs;
        UIView *feedView = [UIView new];
        [testWindow addSubview:feedView];
        UIViewController *feed = controllerIn(home, feedView);
        home.topViewController = feed;
        tabs.selectedViewController = home;
        [DYYYFloatingButtonCoordinator registerInteractionController:feed];
        [DYYYFloatingButtonCoordinator setApplicationActive:YES];
        expectButtons(YES, YES);
        FloatingSpeedButton *originalButton = speedButton;
        [DYYYFloatingButtonCoordinator reloadConfiguration];
        NSUInteger previousUpdates = titleUpdates;
        for (int i = 0; i < 100; i++) [DYYYFloatingButtonCoordinator refresh];
        assert(titleUpdates == previousUpdates);

        // Feed 保留在窗口，切消息后返回不再触发注册或播放 VC 出现事件。
        UIViewController *messages = [UIViewController new];
        for (int i = 0; i < 12; i++) {
            tabs.selectedViewController = messages;
            expectButtons(NO, NO);
            tabs.selectedViewController = home;
            expectButtons(YES, YES);
            assert(speedButton == originalButton && attachments == 1);
        }

        UIView *newFeedView = [UIView new];
        [testWindow addSubview:newFeedView];
        UIViewController *nextFeed = controllerIn(home, newFeedView);
        home.topViewController = nextFeed;
        [DYYYFloatingButtonCoordinator registerInteractionController:nextFeed];
        expectButtons(YES, YES);
        assert([DYYYFloatingButtonCoordinator currentInteractionController] == nextFeed);
        // 旧页面的迟到回调只重新观察事实，不会覆盖新页面状态。
        [DYYYFloatingButtonCoordinator refresh];
        expectButtons(YES, YES);

        UIViewController *comment1 = controllerIn(nextFeed, [UIView new]);
        UIViewController *comment2 = controllerIn(nextFeed, [UIView new]);
        [newFeedView addSubview:comment1.viewIfLoaded];
        [newFeedView addSubview:comment2.viewIfLoaded];
        [DYYYFloatingButtonCoordinator commentController:comment1 visible:YES];
        [DYYYFloatingButtonCoordinator commentController:comment2 visible:YES];
        expectButtons(NO, NO);
        [DYYYFloatingButtonCoordinator commentController:comment1 visible:NO];
        expectButtons(NO, NO);
        [DYYYFloatingButtonCoordinator commentController:comment2 visible:NO];
        expectButtons(YES, YES);

        hideButton.isElementsHidden = YES;
        [defaults setBool:YES forKey:@"DYYYHideSpeed"];
        expectButtons(NO, YES);
        tabs.selectedViewController = messages;
        expectButtons(NO, NO);
        tabs.selectedViewController = home;
        expectButtons(NO, YES);
        hideButton.isElementsHidden = NO;
        expectButtons(YES, YES);
        [DYYYFloatingButtonCoordinator setApplicationActive:NO];
        expectButtons(NO, NO);
        [DYYYFloatingButtonCoordinator setApplicationActive:YES];
        expectButtons(YES, YES);

        home.topViewController = messages;
        expectButtons(NO, NO);
        home.topViewController = nextFeed;
        newFeedView.hidden = YES;
        expectButtons(NO, NO);
        newFeedView.hidden = NO;
        expectButtons(YES, YES);
        UIViewController *modal = controllerIn(nil, [UIView new]);
        [testWindow addSubview:modal.viewIfLoaded];
        nextFeed.presentedViewController = modal;
        expectButtons(NO, NO);
        nextFeed.presentedViewController = nil;
        expectButtons(YES, YES);
        UIViewController *pure = controllerIn(nextFeed, [UIView new]);
        [newFeedView addSubview:pure.viewIfLoaded];
        [DYYYFloatingButtonCoordinator pureModeController:pure visible:YES];
        expectButtons(YES, NO);
        [DYYYFloatingButtonCoordinator pureModeController:pure visible:NO];
        expectButtons(YES, YES);
        [defaults setBool:NO forKey:@"DYYYEnableFloatSpeedButton"];
        [defaults setBool:NO forKey:@"DYYYEnableFloatClearButton"];
        expectButtons(NO, NO);
        assert(!hideButton);
        puts("Floating buttons: 256 policies, cached Tab return, stale callbacks, overlapping comments, clear mode, app state and navigation passed");
    }
}
