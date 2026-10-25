#import "AwemeHeaders.h"
#import "DYYYCommentPlaybackCoordinator.h"

%hook AWECommentMediaFeedParams

- (BOOL (^)(void))panelVideoHasPausedByComment {
    BOOL (^originalBlock)(void) = %orig;
    if (![DYYYCommentPlaybackCoordinator ownsPlayback]) return originalBlock;
    return ^BOOL {
        return [DYYYCommentPlaybackCoordinator ownsPlayback] || (originalBlock ? originalBlock() : NO);
    };
}

- (BOOL (^)(void))fullPanelShouldPreventPlay {
    BOOL (^originalBlock)(void) = %orig;
    if (![DYYYCommentPlaybackCoordinator ownsPlayback]) return originalBlock;
    return ^BOOL {
        return [DYYYCommentPlaybackCoordinator ownsPlayback] || (originalBlock ? originalBlock() : NO);
    };
}

%end

%hook _TtC33AWECommentPanelContainerSwiftImpl30CommentContainerInnerViewModel

- (instancetype)init {
    id viewModel = %orig;
    [DYYYCommentPlaybackCoordinator registerViewModel:viewModel];
    return viewModel;
}

- (void)setTabManager:(id)tabManager {
    %orig(tabManager);
    [DYYYCommentPlaybackCoordinator registerViewModel:self];
}

%end
