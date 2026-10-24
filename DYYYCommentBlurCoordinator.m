#import "DYYYCommentBlurCoordinator.h"
#import "DYYYFullscreenCoordinator.h"
#import "DYYYUtils.h"
#import <objc/runtime.h>

@interface DYYYCommentBlurState : NSObject
@property(nonatomic, strong) NSMapTable<UIView *, id> *backgrounds;
@property(nonatomic, strong) NSMapTable<UIView *, NSNumber *> *opaqueValues;
@property(nonatomic, strong) NSMapTable<UIView *, UIView *> *danmuBackgrounds;
@property(nonatomic, strong) NSMapTable<UIView *, NSNumber *> *hiddenValues;
@property(nonatomic, weak) UIView *panel;
@property(nonatomic, assign) BOOL discoveredLists;
@property(nonatomic, assign) BOOL applying;
@property(nonatomic, weak) UIVisualEffectView *effectView;
@property(nonatomic, assign) UIBlurEffectStyle style;
@property(nonatomic, assign) CGFloat transparency;
@end
@implementation DYYYCommentBlurState
@end

@implementation DYYYCommentBlurCoordinator
+ (void)clearBackground:(UIView *)view state:(DYYYCommentBlurState *)state {
    if (![state.backgrounds objectForKey:view]) {
        [state.backgrounds setObject:view.backgroundColor ?: [NSNull null] forKey:view];
    }
    if (view.backgroundColor && CGColorGetAlpha(view.backgroundColor.CGColor) > 0) view.backgroundColor = [UIColor clearColor];
}
+ (void)clearTextBackground:(UIView *)view state:(DYYYCommentBlurState *)state {
    if (![state.opaqueValues objectForKey:view]) [state.opaqueValues setObject:@(view.opaque) forKey:view];
    state.applying = YES;
    [self clearBackground:view state:state];
    if (view.opaque) view.opaque = NO;
    state.applying = NO;
}
+ (void)updatePanel:(UIViewController *)controller {
    UIView *view = controller.viewIfLoaded;
    if (!view) return;
    DYYYCommentBlurState *state = objc_getAssociatedObject(view, @selector(updatePanel:));
    if (!DYYYGetBool(@"DYYYEnableCommentBlur")) {
        if (!state) return;
        [state.effectView removeFromSuperview];
        for (UIView *background in state.danmuBackgrounds.objectEnumerator) [background removeFromSuperview];
        for (UIView *child in state.hiddenValues.keyEnumerator) child.hidden = [state.hiddenValues objectForKey:child].boolValue;
        for (UIView *background in state.backgrounds.keyEnumerator) {
            if (objc_getAssociatedObject(background, @selector(layoutListView:)) == state) {
                objc_setAssociatedObject(background, @selector(layoutListView:), nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            NSNumber *opaque = [state.opaqueValues objectForKey:background];
            if (opaque && !background.opaque) background.opaque = opaque.boolValue;
            id color = [state.backgrounds objectForKey:background];
            // 原生已重新设置背景时不覆盖新状态。
            if (!background.backgroundColor || CGColorGetAlpha(background.backgroundColor.CGColor) == 0) {
                background.backgroundColor = color == [NSNull null] ? nil : color;
            }
        }
        objc_setAssociatedObject(view, @selector(updatePanel:), nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    if (!view.window) return;
    if (!state) {
        state = [DYYYCommentBlurState new];
        state.backgrounds = [NSMapTable weakToStrongObjectsMapTable];
        state.opaqueValues = [NSMapTable weakToStrongObjectsMapTable];
        state.danmuBackgrounds = [NSMapTable weakToStrongObjectsMapTable];
        state.hiddenValues = [NSMapTable weakToStrongObjectsMapTable];
        state.panel = view;
        objc_setAssociatedObject(view, @selector(updatePanel:), state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [self clearBackground:view state:state];
    // 40.7 的实际评论列表自带不透明背景，会遮住根视图上的毛玻璃。
    // 先处理直接滚动子视图；新面板仅做一次有界发现，文字标签一并去掉底色。
    for (UIView *child in view.subviews) {
        if ([child isKindOfClass:[UIScrollView class]]) [self clearBackground:child state:state];
    }
    if (!state.discoveredLists) {
        state.discoveredLists = YES;
        NSMutableArray<UIView *> *pending = [view.subviews mutableCopy];
        for (NSUInteger index = 0; index < pending.count && index < 512; index++) {
            UIView *child = pending[index];
            if ([child isKindOfClass:[UIScrollView class]]) [self clearBackground:child state:state];
            if ([child isKindOfClass:[UILabel class]] || [child isKindOfClass:NSClassFromString(@"YYLabel")]) [self clearTextBackground:child state:state];
            for (UIView *descendant in child.subviews) {
                if (pending.count >= 512) break;
                [pending addObject:descendant];
            }
        }
    }
    CGFloat transparency = [[[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYCommentBlurTransparent"] floatValue];
    if (transparency <= 0 || transparency > 1) transparency = 0.9;
    UIBlurEffectStyle style = [DYYYUtils isDarkMode] ? UIBlurEffectStyleDark : UIBlurEffectStyleLight;
    UIVisualEffectView *effect = state.effectView;
    if (!effect || effect.superview != view) {
        [DYYYUtils applyBlurEffectToView:view transparency:transparency blurViewTag:999];
        for (UIView *child in view.subviews) {
            if ([child isKindOfClass:[UIVisualEffectView class]] && child.tag == 999) {
                effect = (UIVisualEffectView *)child;
                state.effectView = effect;
                effect.userInteractionEnabled = NO;
                break;
            }
        }
        state.style = style;
        state.transparency = transparency;
    } else if (state.style != style || fabs(state.transparency - transparency) > 0.001) {
        [DYYYUtils applyBlurEffectToView:view transparency:transparency blurViewTag:999];
        state.style = style;
        state.transparency = transparency;
    }
    if (effect && !CGRectEqualToRect(effect.frame, view.bounds)) effect.frame = view.bounds;
}
+ (DYYYCommentBlurState *)stateForContentView:(UIView *)view {
    if (![NSThread isMainThread] || !DYYYGetBool(@"DYYYEnableCommentBlur")) return nil;
    DYYYCommentBlurState *state = objc_getAssociatedObject(view, @selector(layoutListView:));
    if (!state.panel || objc_getAssociatedObject(state.panel, @selector(updatePanel:)) != state || ![view isDescendantOfView:state.panel]) {
        state = nil;
        objc_setAssociatedObject(view, @selector(layoutListView:), nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        UIView *ancestor = view.superview;
        for (NSUInteger depth = 0; ancestor && depth < 16; depth++, ancestor = ancestor.superview) {
            state = objc_getAssociatedObject(ancestor, @selector(updatePanel:));
            if (state) break;
        }
        if (state) objc_setAssociatedObject(view, @selector(layoutListView:), state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return state.panel ? state : nil;
}
+ (void)layoutDanmuBackground:(UIView *)container controller:(UIViewController *)controller enabled:(BOOL)enabled {
    DYYYCommentBlurState *state = objc_getAssociatedObject(controller.viewIfLoaded, @selector(updatePanel:));
    UIView *target = container.superview.subviews.firstObject;
    if (!state || !target) return;
    UIView *background = [state.danmuBackgrounds objectForKey:target];
    UIView *originalChild = target.subviews.firstObject;
    if (!enabled) {
        [background removeFromSuperview];
        [state.danmuBackgrounds removeObjectForKey:target];
        NSNumber *hidden = [state.hiddenValues objectForKey:originalChild];
        if (hidden) {
            originalChild.hidden = hidden.boolValue;
            [state.hiddenValues removeObjectForKey:originalChild];
        }
        return;
    }
    if (originalChild && originalChild != background) {
        if (![state.hiddenValues objectForKey:originalChild]) [state.hiddenValues setObject:@(originalChild.hidden) forKey:originalChild];
        if (!originalChild.hidden) originalChild.hidden = YES;
    }
    if (!background) {
        background = [[UIView alloc] initWithFrame:target.bounds];
        background.backgroundColor = UIColor.whiteColor;
        background.userInteractionEnabled = NO;
        background.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [state.danmuBackgrounds setObject:background forKey:target];
        [target addSubview:background];
    }
    if (!CGRectEqualToRect(background.frame, target.bounds)) background.frame = target.bounds;
}

+ (void)layoutListView:(UIView *)view {
    DYYYCommentBlurState *state = [self stateForContentView:view];
    // 新版正文列表位于 UICollectionViewCell 内，清除外层背景不足以透出材质。
    if (state) [self clearBackground:view state:state];
}
+ (void)layoutTextView:(UIView *)view {
    DYYYCommentBlurState *state = [self stateForContentView:view];
    // 原生复用昵称、时间及回复标签时会重新设置不透明底色。
    if (state) [self clearTextBackground:view state:state];
}
+ (UIColor *)backgroundColorForTextView:(UIView *)view proposed:(UIColor *)color {
    DYYYCommentBlurState *state = [self stateForContentView:view];
    if (!state || state.applying) return color;
    // 原生可只重画而不触发布局，在写入入口拦住底色，并记住最新的恢复值。
    [state.backgrounds setObject:color ?: [NSNull null] forKey:view];
    if (![state.opaqueValues objectForKey:view]) [state.opaqueValues setObject:@(view.opaque) forKey:view];
    state.applying = YES;
    if (view.opaque) view.opaque = NO;
    state.applying = NO;
    return [UIColor clearColor];
}
+ (BOOL)opaqueForTextView:(UIView *)view proposed:(BOOL)opaque {
    DYYYCommentBlurState *state = [self stateForContentView:view];
    if (!state || state.applying) return opaque;
    if (![state.backgrounds objectForKey:view]) [state.backgrounds setObject:view.backgroundColor ?: [NSNull null] forKey:view];
    if (![state.opaqueValues objectForKey:view]) [state.opaqueValues setObject:@(opaque) forKey:view];
    return NO;
}
+ (void)layoutController:(UIViewController *)controller {
    if (![NSThread isMainThread]) return;
    Class innerClass = NSClassFromString(@"AWECommentPanelContainerSwiftImpl.CommentContainerInnerViewController");
    if (!innerClass) return;
    if ([controller isKindOfClass:innerClass]) {
        [self updatePanel:controller];
        return;
    }
    Class containerClass = NSClassFromString(@"AWECommentContainerViewController");
    if (!containerClass || ![controller isKindOfClass:containerClass]) return;
    // 宿主回调覆盖新版 Swift 面板没有调用旧父类布局方法的情况。
    NSMutableArray<UIViewController *> *pending = [controller.childViewControllers mutableCopy];
    for (NSUInteger index = 0; index < pending.count && index < 32; index++) {
        UIViewController *child = pending[index];
        if ([child isKindOfClass:innerClass]) {
            [self updatePanel:child];
            [DYYYFullscreenCoordinator commentController:child visible:child.viewIfLoaded.window != nil];
        } else if (pending.count < 32) {
            [pending addObjectsFromArray:child.childViewControllers];
        }
    }
}
@end
