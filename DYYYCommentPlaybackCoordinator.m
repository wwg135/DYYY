#import "DYYYCommentPlaybackCoordinator.h"
#import "AwemeHeaders.h"
#import "DYYYFloatingButtonCoordinator.h"

@interface DYYYCommentPlaybackCoordinator ()
@property(nonatomic, strong) NSHashTable *viewModels;
@property(nonatomic, weak) UIViewController *commentController;
@property(nonatomic, weak) _TtC33AWECommentPanelContainerSwiftImpl30CommentContainerInnerViewModel *pausedViewModel;
@end

@implementation DYYYCommentPlaybackCoordinator

+ (instancetype)shared {
    static DYYYCommentPlaybackCoordinator *coordinator;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        coordinator = [self new];
        coordinator.viewModels = [NSHashTable weakObjectsHashTable];
    });
    return coordinator;
}

#pragma mark - 原生评论暂停与恢复

+ (void)registerViewModel:(id)viewModel {
    if (!viewModel) return;
    if (!NSThread.isMainThread) {
        __weak id weakViewModel = viewModel;
        dispatch_async(dispatch_get_main_queue(), ^{ [self registerViewModel:weakViewModel]; });
        return;
    }
    [[self shared].viewModels addObject:viewModel];
    [self pauseIfNeeded];
}

+ (void)pauseIfNeeded {
    DYYYCommentPlaybackCoordinator *coordinator = [self shared];
    if (!coordinator.commentController || coordinator.pausedViewModel || !DYYYGetBool(@"DYYYCommentPausePlayback")) return;

    AWEPlayInteractionViewController *current = (id)[DYYYFloatingButtonCoordinator currentInteractionController];
    id bestViewModel = nil;
    CGFloat bestScore = -CGFLOAT_MAX;
    for (_TtC33AWECommentPanelContainerSwiftImpl30CommentContainerInnerViewModel *viewModel in coordinator.viewModels.allObjects) {
        @try {
            if (![viewModel respondsToSelector:@selector(isFeedVideoPlaying)] || ![viewModel isFeedVideoPlaying]) continue;
            if (![viewModel respondsToSelector:@selector(pauseVideoIfPlayingWithoutShowingPauseIcon)]) continue;
            id player = [viewModel respondsToSelector:@selector(feedVideoPlayerController)] ? [viewModel feedVideoPlayerController] : nil;
            CGFloat score = 0;
            if ([player isKindOfClass:UIViewController.class]) {
                UIView *view = ((UIViewController *)player).viewIfLoaded;
                if (view.window && !view.hidden) {
                    CGRect rect = [view convertRect:view.bounds toView:view.window];
                    CGRect visible = CGRectIntersection(rect, view.window.bounds);
                    if (!CGRectIsNull(visible)) score = visible.size.width * visible.size.height;
                }
            }
            if (current && [player respondsToSelector:@selector(model)]) {
                AWEAwemeModel *model = [player model];
                if (model == current.model || (model.itemID.length && [model.itemID isEqualToString:current.model.itemID])) score += 1.0e12;
            }
            if (score > bestScore) { bestScore = score; bestViewModel = viewModel; }
        } @catch (__unused NSException *exception) {
        }
    }
    @try {
        // 使用 main 中的原生入口，保留宿主评论暂停状态和媒体预览的恢复约定。
        [bestViewModel pauseVideoIfPlayingWithoutShowingPauseIcon];
        coordinator.pausedViewModel = bestViewModel;
    } @catch (NSException *exception) {
        NSLog(@"[DYYY] 评论暂停失败：%@", exception.reason);
    }
}

+ (void)commentController:(UIViewController *)controller visible:(BOOL)visible {
    if (!NSThread.isMainThread) {
        __weak UIViewController *weakController = controller;
        dispatch_async(dispatch_get_main_queue(), ^{ [self commentController:weakController visible:visible]; });
        return;
    }
    if (!controller) return;
    DYYYCommentPlaybackCoordinator *coordinator = [self shared];
    if (visible) {
        coordinator.commentController = controller;
        [self pauseIfNeeded];
        return;
    }
    if (coordinator.commentController != controller) return;
    if ([self shouldSkipLifecycle:controller]) return;
    id paused = coordinator.pausedViewModel;
    coordinator.commentController = nil;
    coordinator.pausedViewModel = nil;
    @try {
        if ([paused respondsToSelector:@selector(recoverPlayIfPauseByComment)]) [paused recoverPlayIfPauseByComment];
    } @catch (NSException *exception) {
        NSLog(@"[DYYY] 评论播放恢复失败：%@", exception.reason);
    }
}

+ (BOOL)ownsPlayback {
    return [self shared].pausedViewModel != nil;
}

+ (BOOL)shouldSkipLifecycle:(UIViewController *)controller {
    @try {
        if (![controller respondsToSelector:@selector(state)]) return NO;
        _TtC33AWECommentPanelContainerSwiftImpl31CommentViewControllerStateModel *state = [(AWECommentContainerViewController *)controller state];
        return [state respondsToSelector:@selector(isSkipCommentPanelLifecycle)] && state.isSkipCommentPanelLifecycle;
    } @catch (__unused NSException *exception) {
        return NO;
    }
}

@end
