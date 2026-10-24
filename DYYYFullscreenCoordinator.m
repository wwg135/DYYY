#import "DYYYFullscreenCoordinator.h"
#import "DYYYFullscreenGeometry.h"
#import "AwemeHeaders.h"
#import <objc/runtime.h>

@interface DYYYFullscreenPlayerState : NSObject
@property(nonatomic, weak) UIViewController *owner;
@property(nonatomic, assign) CGRect nativeFrame;
@property(nonatomic, assign) CGRect lastAppliedFrame;
@property(nonatomic, assign) BOOL hasNativeFrame;
@property(nonatomic, assign) CGSize closedInteractionSize;
@property(nonatomic, assign) CGRect captionWindowFrame;
@property(nonatomic, assign) BOOL hasCaptionFrame;
@property(nonatomic, assign) BOOL captionAdjusted;
@property(nonatomic, assign) CGPoint captionNativeCenter;
@property(nonatomic, assign) CGPoint captionAppliedCenter;
@property(nonatomic, assign) BOOL applying;
@property(nonatomic, assign) BOOL adjusted;
@property(nonatomic, assign) CGRect normalWindowFrame;
@property(nonatomic, assign) BOOL hasNormalWindowFrame;
@property(nonatomic, assign) CGSize normalRenderSize;
@property(nonatomic, weak) UIWindow *normalWindow;
@property(nonatomic, weak) UIView *normalCell;
@property(nonatomic, assign) CGRect normalCellWindowFrame;
@end
@implementation DYYYFullscreenPlayerState
@end

@implementation DYYYFullscreenCoordinator
+ (NSString *)buildIdentifier { return @"fullscreen-viewport-20261023.22"; }
// Live 图文也含 TTPlayerView 和有效视频尺寸，不能用播放器存在与否区分。
+ (BOOL)isImageContentController:(UIViewController *)controller {
    for (NSUInteger depth = 0; controller && depth < 5; depth++, controller = controller.parentViewController) {
        if (![controller respondsToSelector:@selector(model)]) continue;
        AWEAwemeModel *model = [(AWEPlayInteractionViewController *)controller model];
        if (![model isKindOfClass:NSClassFromString(@"AWEAwemeModel")]) continue;
        if ([model respondsToSelector:@selector(awemeType)] && model.awemeType == 68) return YES;
        if ([model respondsToSelector:@selector(albumImages)] && model.albumImages.count > 0) return YES;
        if ([model respondsToSelector:@selector(isLivePhoto)] && model.isLivePhoto) return YES;
        if ([model respondsToSelector:@selector(animatedImageVideoInfo)] && model.animatedImageVideoInfo) return YES;
        return NO;
    }
    return NO;
}
+ (NSHashTable<UIView *> *)players {
    static NSHashTable *players;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ players = [NSHashTable weakObjectsHashTable]; });
    return players;
}
+ (NSHashTable<UIView *> *)tabBars {
    static NSHashTable *views;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ views = [NSHashTable weakObjectsHashTable]; });
    return views;
}
+ (NSHashTable<UIViewController *> *)interactions {
    static NSHashTable *controllers;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ controllers = [NSHashTable weakObjectsHashTable]; });
    return controllers;
}
+ (void)invalidateGuides {
    static BOOL scheduled = NO;
    if (scheduled) return;
    scheduled = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        scheduled = NO;
        for (UIViewController *controller in [self interactions].allObjects) [controller.viewIfLoaded setNeedsLayout];
        for (UIView *player in [self players].allObjects) if (player.window) [player setNeedsLayout];
    });
}
+ (void)registerTabBar:(UIView *)tabBar {
    if (![NSThread isMainThread]) return;
    [[self tabBars] addObject:tabBar];
    CGRect rect = tabBar.window ? [tabBar convertRect:tabBar.bounds toView:tabBar.window] : CGRectNull;
    NSString *signature = [NSString stringWithFormat:@"%p/%@/%d", tabBar.window, NSStringFromCGRect(rect), [self visible:tabBar]];
    NSString *previous = objc_getAssociatedObject(tabBar, @selector(registerTabBar:));
    if (![signature isEqualToString:previous]) {
        objc_setAssociatedObject(tabBar, @selector(registerTabBar:), signature, OBJC_ASSOCIATION_COPY_NONATOMIC);
        [self invalidateGuides];
    }
}
+ (void)layoutInteraction:(UIViewController *)controller {
    if (![NSThread isMainThread]) return;
    UIView *view = controller.viewIfLoaded;
    UIView *parent = view.superview;
    if (!view.window || !parent || view.bounds.size.width < parent.bounds.size.width * 0.8) return;
    [[self interactions] addObject:controller];
    if ([self isImageContentController:controller]) return;
    DYYYFullscreenPlayerState *state = [self state:view];
    CGRect current = view.frame;
    if (!state.hasNativeFrame || !CGRectEqualToRect(current, state.lastAppliedFrame)) state.nativeFrame = current;
    state.hasNativeFrame = YES;
    CGRect target = state.nativeFrame;
    target.size.height = MIN(target.size.height, MAX(0, CGRectGetMaxY(parent.bounds) - target.origin.y));
    if (DYYYGetBool(@"DYYYEnableFullScreen")) {
        target.size.height = MAX(0, CGRectGetMaxY(parent.bounds) - target.origin.y);
        CGRect guide = [parent convertRect:target toView:view.window];
        // Feed 的前后两页在滚动中有不同的窗口 y；先移除页平移，
        // 否则 Tab 裁剪会把互动层高度从 896 连续改到 827，反过来干扰滚动布局。
        CGFloat pageTranslation = CGRectGetMinY([parent convertRect:parent.bounds toView:view.window]) - CGRectGetMinY(view.window.bounds);
        guide.origin.y -= pageTranslation;
        for (UIView *tabBar in [self tabBars].allObjects) {
            if (tabBar.window != view.window || ![self visible:tabBar]) continue;
            CGRect tabRect = [tabBar convertRect:tabBar.bounds toView:view.window];
            if (CGRectGetMinY(tabRect) < CGRectGetMidY(guide)) continue;
            CGRect available = [DYYYFullscreenGeometry unoccludedViewport:guide top:CGRectGetMinY(guide) panel:tabRect gap:0];
            if (!CGRectIsNull(available)) guide = available;
        }
        guide.origin.y += pageTranslation;
        target = [parent convertRect:guide fromView:view.window];
    }
    BOOL activeComment = [self hasCommentInWindow:view.window];
    if (DYYYGetBool(@"DYYYEnableFullScreen")) {
        if (activeComment && state.normalWindow == view.window && state.closedInteractionSize.height > 0) {
            // 评论隐藏 Tab 并不代表信息区可扩高，否则原生底部约束会下跳一个 Tab 高度。
            target.size.height = state.closedInteractionSize.height;
        } else if (!activeComment) {
            state.closedInteractionSize = target.size;
            state.normalWindow = view.window;
        }
    } else {
        state.closedInteractionSize = CGSizeZero;
    }
    state.lastAppliedFrame = target;
    if (fabs(current.size.height - target.size.height) > 0.25 || fabs(current.origin.y - target.origin.y) > 0.25) {
        view.frame = target;
    }
    NSString *signature = [NSString stringWithFormat:@"%@/%d/%d", NSStringFromCGRect(target),
                           DYYYGetBool(@"DYYYEnableFullScreen"), DYYYGetBool(@"DYYYEnableCommentBlur")];
    NSString *previous = objc_getAssociatedObject(controller, @selector(layoutInteraction:));
    if (![signature isEqualToString:previous]) {
        objc_setAssociatedObject(controller, @selector(layoutInteraction:), signature, OBJC_ASSOCIATION_COPY_NONATOMIC);
        // 仅几何输入变化时更新播放器，不能每次 layout 都再次标记自身。
        for (UIView *player in [self players].allObjects) if (player.window == view.window) [player setNeedsLayout];
    }
}
+ (NSHashTable<UIView *> *)informationLabels {
    static NSHashTable *labels;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ labels = [NSHashTable weakObjectsHashTable]; });
    return labels;
}
+ (void)layoutInformationLabel:(UIView *)label {
    if (![NSThread isMainThread] || !label.window || !label.superview) return;
    DYYYFullscreenPlayerState *state = [self state:label];
    [[self informationLabels] addObject:label];
    BOOL active = DYYYGetBool(@"DYYYEnableFullScreen") && [self hasCommentInWindow:label.window];
    if (!active) {
        if (state.captionAdjusted && CGPointEqualToPoint(label.center, state.captionAppliedCenter)) label.center = state.captionNativeCenter;
        state.captionAdjusted = NO;
        state.captionWindowFrame = [label convertRect:label.bounds toView:label.window];
        state.hasCaptionFrame = DYYYGetBool(@"DYYYEnableFullScreen");
        state.normalWindow = label.window;
        return;
    }
    if (!state.hasCaptionFrame || state.normalWindow != label.window) return;
    CGRect current = [label convertRect:label.bounds toView:label.window];
    CGFloat shift = CGRectGetMaxY(current) - CGRectGetMaxY(state.captionWindowFrame);
    if (shift > 0.25) {
        if (!state.captionAdjusted || !CGPointEqualToPoint(label.center, state.captionAppliedCenter)) state.captionNativeCenter = label.center;
        // 只拦截越过关闭态底边的下移，保留普通评论合法的向上平移和缩放。
        CGRect target = current;
        target.origin.y -= shift;
        CGPoint center = label.center;
        center.y += CGRectGetMidY([label.superview convertRect:target fromView:label.window]) - CGRectGetMidY(label.frame);
        state.captionAppliedCenter = center;
        state.captionAdjusted = YES;
        label.center = center;
    }
}
+ (void)rememberInteractionGuide:(UIViewController *)controller {
    UIView *view = controller.viewIfLoaded;
    if (![NSThread isMainThread] || !view.window || !DYYYGetBool(@"DYYYEnableFullScreen") || [self hasCommentInWindow:view.window]) return;
    DYYYFullscreenPlayerState *state = [self state:view];
    state.closedInteractionSize = view.frame.size;
    state.normalWindow = view.window;
}
+ (CGRect)frameForInteractionView:(UIView *)view proposed:(CGRect)frame {
    // 只访问已注册的视频互动根视图；不为每次 UIView.setFrame 遍历 responder。
    DYYYFullscreenPlayerState *state = objc_getAssociatedObject(view, @selector(state:));
    if (state.closedInteractionSize.height > 0 && state.normalWindow == view.window &&
        frame.size.width >= state.closedInteractionSize.width * 0.8 &&
        DYYYGetBool(@"DYYYEnableFullScreen") && [self hasCommentInWindow:view.window]) {
        frame.size.height = state.closedInteractionSize.height;
    }
    return frame;
}
+ (NSHashTable<UIViewController *> *)comments {
    static NSHashTable *comments;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ comments = [NSHashTable weakObjectsHashTable]; });
    return comments;
}
+ (NSMapTable<UIWindow *, NSNumber *> *)pendingComments {
    static NSMapTable *windows;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ windows = [NSMapTable weakToStrongObjectsMapTable]; });
    return windows;
}
+ (NSMapTable<UIViewController *, UIWindow *> *)commentWindows {
    static NSMapTable *windows;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ windows = [NSMapTable weakToWeakObjectsMapTable]; });
    return windows;
}
+ (void)beginCommentInWindow:(UIWindow *)window {
    if (![NSThread isMainThread] || !window || !DYYYGetBool(@"DYYYEnableFullScreen")) return;
    if (![self hasCommentInWindow:window]) {
        for (UIView *label in [self informationLabels].allObjects) {
            if (label.window != window || ![self visible:label]) continue;
            [self layoutInformationLabel:label];
        }
    }
    // 先冻结关闭态，再执行原生打开动作。动画开始早于 viewDidLayoutSubviews。
    // 未成功显示的面板自动在 5 秒后失效，不留下持续的 UI 工作。
    [[self pendingComments] setObject:@(CACurrentMediaTime() + 5) forKey:window];
}
+ (DYYYFullscreenPlayerState *)state:(UIView *)player {
    DYYYFullscreenPlayerState *state = objc_getAssociatedObject(player, @selector(state:));
    if (!state) {
        state = [DYYYFullscreenPlayerState new];
        objc_setAssociatedObject(player, @selector(state:), state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return state;
}
+ (BOOL)visible:(UIView *)view {
    if (!view.window) return NO;
    CGFloat alpha = 1;
    for (UIView *v = view; v; v = v.superview) {
        alpha *= v.alpha;
        if (v.hidden || alpha < 0.01) return NO;
    }
    return CGRectIntersectsRect([view convertRect:view.bounds toView:view.window], view.window.bounds);
}
+ (UIViewController *)owner:(UIView *)player state:(DYYYFullscreenPlayerState *)state {
    if (state.owner && state.owner.viewIfLoaded.window == player.window && [player isDescendantOfView:state.owner.viewIfLoaded]) return state.owner;
    UIResponder *responder = player;
    for (NSUInteger i = 0; responder && i < 16; i++, responder = responder.nextResponder) {
        if ([responder isKindOfClass:[UIViewController class]]) {
            NSString *name = NSStringFromClass(responder.class);
            if ([name containsString:@"PlayVideoViewController"] || [self isImageContentController:(UIViewController *)responder]) {
                state.owner = (UIViewController *)responder;
                return state.owner;
            }
        }
    }
    return nil;
}
+ (UIView *)cellForPlayer:(UIView *)player owner:(UIViewController *)owner {
    for (UIView *view = player.superview; view && ![view isKindOfClass:[UIWindow class]]; view = view.superview) {
        NSString *name = NSStringFromClass(view.class);
        if ([name containsString:@"FeedViewCell"] || [name containsString:@"DetailTableViewCell"]) return view;
    }
    return owner.parentViewController.viewIfLoaded.superview ?: owner.viewIfLoaded.superview;
}
+ (CGRect)panelInWindow:(UIWindow *)window viewport:(CGRect)viewport {
    CGRect result = CGRectNull;
    for (UIViewController *controller in [self comments].allObjects) {
        UIView *view = controller.viewIfLoaded;
        if (view.window != window || ![self visible:view]) continue;
        CGRect rect = [view convertRect:view.bounds toView:window];
        // 过滤全屏宿主；使用真正的半屏评论根视图，避免取到整页容器。
        if (rect.size.height < window.bounds.size.height * 0.25 || CGRectGetMinY(rect) <= CGRectGetMinY(viewport) + 1) continue;
        if (CGRectIntersectsRect(rect, viewport) && (CGRectIsNull(result) || CGRectGetMinY(rect) < CGRectGetMinY(result))) result = rect;
    }
    return result;
}
+ (BOOL)hasCommentInWindow:(UIWindow *)window {
    if (!window) return NO;
    NSNumber *deadline = [[self pendingComments] objectForKey:window];
    if (deadline.doubleValue > CACurrentMediaTime()) return YES;
    if (deadline) [[self pendingComments] removeObjectForKey:window];
    for (UIViewController *controller in [self comments].allObjects) {
        if (controller.viewIfLoaded.window == window) return YES;
    }
    return NO;
}
+ (CGRect)targetForPlayer:(UIView *)player native:(CGRect)native state:(DYYYFullscreenPlayerState *)state {
    if (!DYYYGetBool(@"DYYYEnableFullScreen") || ![self visible:player]) return native;
    UIWindow *window = player.window;
    UIViewController *owner = [self owner:player state:state];
    if ([self isImageContentController:owner]) {
        state.hasNormalWindowFrame = NO;
        state.normalRenderSize = CGSizeZero;
        return native;
    }
    BOOL activeComment = [self hasCommentInWindow:window];
    UIView *cell = [self cellForPlayer:player owner:owner];
    if (DYYYGetBool(@"DYYYEnableCommentBlur") && activeComment && state.hasNormalWindowFrame && state.normalWindow == window &&
        state.normalCell == cell && cell.window == window && player.superview) {
        // 预加载下一页时记录的窗口 y 不能直接用于已滚到屏幕中心的页面。
        CGRect reference = [cell convertRect:cell.bounds toView:window];
        CGRect normal = [DYYYFullscreenGeometry translateRect:state.normalWindowFrame fromReference:state.normalCellWindowFrame toReference:reference];
        if (!CGRectIsNull(normal)) return [player.superview convertRect:normal fromView:window];
    }
    if (!owner || !cell || cell.window != window || !player.superview || window.bounds.size.width >= window.bounds.size.height) return native;
    CGRect viewport = CGRectIntersection([cell convertRect:cell.bounds toView:window], window.bounds);
    if (CGRectIsNull(viewport) || viewport.size.width < window.bounds.size.width * 0.8) return native;
    CGSize media = CGSizeZero;
    if ([owner respondsToSelector:@selector(getPlayerVideoSize)]) media = [(AWEPlayVideoViewController *)owner getPlayerVideoSize];
    if (media.width <= 0 || media.height <= 0) {
        // 复用播放器切到图文时，不能沿用上一条视频的毛玻璃关闭态。
        state.hasNormalWindowFrame = NO;
        state.normalRenderSize = CGSizeZero;
        return native;
    }
    CGRect panel = DYYYGetBool(@"DYYYEnableCommentBlur") ? CGRectNull : [self panelInWindow:window viewport:viewport];
    if (!CGRectIsNull(panel)) {
        // 标准导航区域之外保留完整视频；不在原生评论平移上再累加偏移。
        CGFloat top = MAX(CGRectGetMinY(viewport), window.safeAreaInsets.top + 44);
        CGRect available = [DYYYFullscreenGeometry unoccludedViewport:viewport top:top panel:panel gap:8];
        // 原生“铺满”可能让 Metal 按屏幕比例裁剪；按实际渲染比例适配，
        // 不能只按视频源尺寸缩小容器，否则 Metal 仍会溢出评论可用区。
        CGSize rendered = state.normalRenderSize;
        if (state.hasNormalWindowFrame && state.normalWindow == window && rendered.width > 0 && rendered.height > 0) media = rendered;
        CGRect fit = [DYYYFullscreenGeometry aspectFit:media inRect:available];
        return CGRectIsNull(fit) ? native : [player.superview convertRect:fit fromView:window];
    }
    if (media.width > media.height) {
        // 横屏视频沿用原生信息层的布局高度；背景仍由全高 Feed 承载。
        for (UIViewController *controller in [self interactions].allObjects) {
            UIView *interaction = controller.viewIfLoaded;
            if (interaction.window != window || ![interaction isDescendantOfView:cell]) continue;
            CGRect guide = [interaction convertRect:interaction.bounds toView:window];
            if (guide.size.height > viewport.size.height * 0.6 && guide.size.height <= viewport.size.height) native.size.height = guide.size.height;
            break;
        }
        if (!activeComment) {
            state.normalWindowFrame = [player.superview convertRect:native toView:window];
            state.normalCell = cell;
            state.normalCellWindowFrame = [cell convertRect:cell.bounds toView:window];
            state.hasNormalWindowFrame = YES;
            state.normalWindow = window;
        }
        return native;
    }
    // 竖屏媒体扩展到本页底部；不影响宽度缩小的原生面板/小窗布局。
    if (fabs(native.size.width - viewport.size.width) < 1 && fabs(native.origin.x) < 1) native.size.height = MAX(native.size.height, viewport.size.height);
    if (!activeComment) {
        state.normalWindowFrame = [player.superview convertRect:native toView:window];
        state.normalCell = cell;
        state.normalCellWindowFrame = [cell convertRect:cell.bounds toView:window];
        state.hasNormalWindowFrame = YES;
        state.normalWindow = window;
    }
    return native;
}
+ (CGRect)frameForPlayer:(UIView *)player proposed:(CGRect)frame {
    if (![NSThread isMainThread]) return frame;
    DYYYFullscreenPlayerState *state = [self state:player];
    if (state.applying) return frame;
    state.nativeFrame = frame;
    state.hasNativeFrame = YES;
    return [self targetForPlayer:player native:frame state:state];
}
+ (void)preparePlayer:(UIView *)player {
    if (![NSThread isMainThread]) return;
    DYYYFullscreenPlayerState *state = [self state:player];
    if (state.applying) return;
    [[self players] addObject:player];
    if ([self isImageContentController:[self owner:player state:state]]) {
        state.hasNormalWindowFrame = NO;
        state.normalRenderSize = CGSizeZero;
        return;
    }
    if (!state.hasNativeFrame) { state.nativeFrame = player.frame; state.hasNativeFrame = YES; }
    CGRect target = [self targetForPlayer:player native:state.nativeFrame state:state];
    state.adjusted = !CGRectEqualToRect(target, state.nativeFrame);
    CGRect current = player.frame;
    if (fabs(current.origin.x - target.origin.x) + fabs(current.origin.y - target.origin.y) + fabs(current.size.width - target.size.width) + fabs(current.size.height - target.size.height) > 0.25) {
        state.applying = YES;
        player.frame = target;
        state.applying = NO;
    }
}
+ (UIView *)renderView:(UIView *)player {
    for (UIView *view in player.subviews) {
        NSString *name = NSStringFromClass(view.class);
        if ([name hasPrefix:@"TTMetal"] || [name containsString:@"RenderView"]) return view;
    }
    return nil;
}
// 仅记录媒体渲染尺寸；全屏观看按钮完全沿用原生位置。
+ (void)finishPlayer:(UIView *)player {
    if (![NSThread isMainThread]) return;
    DYYYFullscreenPlayerState *state = [self state:player];
    if ([self isImageContentController:[self owner:player state:state]]) return;
    if (DYYYGetBool(@"DYYYEnableFullScreen") && DYYYGetBool(@"DYYYEnableCommentBlur") && [self hasCommentInWindow:player.window]) [self preparePlayer:player];
    UIView *render = [self renderView:player];
    if (DYYYGetBool(@"DYYYEnableFullScreen") && ![self hasCommentInWindow:player.window] &&
        state.hasNormalWindowFrame && render.bounds.size.width > 0 && render.bounds.size.height > 0) {
        state.normalRenderSize = render.bounds.size;
    }
}
+ (void)commentController:(UIViewController *)controller visible:(BOOL)visible {
    if (![NSThread isMainThread]) {
        __weak UIViewController *weakController = controller;
        dispatch_async(dispatch_get_main_queue(), ^{ if (weakController) [self commentController:weakController visible:visible]; });
        return;
    }
    UIView *view = controller.viewIfLoaded;
    CGRect rect = visible && view.window ? [view convertRect:view.bounds toView:view.window] : CGRectNull;
    NSString *signature = [NSString stringWithFormat:@"%p/%@/%d/%d/%d", view.window, NSStringFromCGRect(rect), visible,
                           DYYYGetBool(@"DYYYEnableFullScreen"), DYYYGetBool(@"DYYYEnableCommentBlur")];
    NSString *previous = objc_getAssociatedObject(controller, @selector(commentController:visible:));
    if ([signature isEqualToString:previous]) return;
    objc_setAssociatedObject(controller, @selector(commentController:visible:), signature, OBJC_ASSOCIATION_COPY_NONATOMIC);
    if (visible) {
        [[self comments] addObject:controller];
        if (view.window) [[self commentWindows] setObject:view.window forKey:controller];
    } else {
        UIWindow *window = [[self commentWindows] objectForKey:controller] ?: view.window;
        [[self comments] removeObject:controller];
        [[self commentWindows] removeObjectForKey:controller];
        BOOL remaining = NO;
        for (UIViewController *other in [self comments].allObjects) if (other.viewIfLoaded.window == window) { remaining = YES; break; }
        if (window && !remaining) [[self pendingComments] removeObjectForKey:window];
    }
    // 同一轮布局只安排一次；不在评论回调里递归触发布局。
    static BOOL scheduled = NO;
    if (scheduled) return;
    scheduled = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        scheduled = NO;
        for (UIView *player in [self players].allObjects) if (player.window) [player setNeedsLayout];
    });
}
@end
