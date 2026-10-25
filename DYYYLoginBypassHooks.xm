#import "AwemeHeaders.h"
#import "DYYYLoginBypassManager.h"
#import "DYYYLoginRepairHooks.h"

static BOOL DYYYLoginBypassEnabled(void) {
    return [DYYYLoginBypassManager isLoginBypassEnabled];
}

static BOOL DYYYShouldBlockVersionUpdateWorkflow(void) {
    return DYYYGetBool(@"DYYYNoUpdates") || DYYYLoginBypassEnabled();
}

static void DYYYLoginBypassInvokeCloseCallback(id callback) {
    if (!callback) {
        return;
    }

    void (^completionBlock)(void) = callback;
    completionBlock();
}

static NSString *DYYYLoginBypassReplacementBundleIdentifier(NSString *bundleIdentifier) {
    return [DYYYLoginBypassManager replacementBundleIdentifier:bundleIdentifier];
}

static NSString *DYYYLoginBypassHeaderValueByReplacingBundleIdentifier(NSString *value, NSString *field) {
    return [DYYYLoginBypassManager headerValueByReplacingBundleIdentifier:value field:field];
}

static NSDictionary *DYYYLoginBypassHeadersByReplacingBundleIdentifiers(NSDictionary *headers) {
    return [DYYYLoginBypassManager headersByReplacingBundleIdentifiers:headers];
}

static NSURL *DYYYLoginBypassURLByReplacingBundleIdentifier(NSURL *url) {
    return [DYYYLoginBypassManager URLByReplacingTargetBundleIdentifiers:url];
}

%group DYYYLoginBypassCore

%hook NSBundle
- (NSString *)bundleIdentifier {
    NSString *bundleIdentifier = %orig;
    return DYYYLoginBypassReplacementBundleIdentifier(bundleIdentifier);
}

- (NSDictionary *)infoDictionary {
    NSDictionary *infoDictionary = %orig;
    if (![infoDictionary isKindOfClass:[NSDictionary class]]) {
        return infoDictionary;
    }

    NSString *bundleIdentifier = infoDictionary[@"CFBundleIdentifier"];
    NSString *replacementIdentifier = DYYYLoginBypassReplacementBundleIdentifier(bundleIdentifier);
    if (![replacementIdentifier isKindOfClass:[NSString class]] || replacementIdentifier.length == 0 ||
        [replacementIdentifier isEqualToString:bundleIdentifier]) {
        return infoDictionary;
    }

    NSMutableDictionary *mutableInfoDictionary = [infoDictionary mutableCopy];
    mutableInfoDictionary[@"CFBundleIdentifier"] = replacementIdentifier;
    return mutableInfoDictionary;
}
%end

%hook NSURLRequest
- (NSURL *)URL {
    NSURL *url = %orig;
    return DYYYLoginBypassURLByReplacingBundleIdentifier(url);
}
%end

%hook NSMutableURLRequest
- (void)setValue:(NSString *)value forHTTPHeaderField:(NSString *)field {
    %orig(DYYYLoginBypassHeaderValueByReplacingBundleIdentifier(value, field), field);
}

- (void)addValue:(NSString *)value forHTTPHeaderField:(NSString *)field {
    %orig(DYYYLoginBypassHeaderValueByReplacingBundleIdentifier(value, field), field);
}

- (void)setURL:(NSURL *)url {
    %orig(DYYYLoginBypassURLByReplacingBundleIdentifier(url));
}
%end

%hook NSURLSessionConfiguration
- (NSDictionary *)HTTPAdditionalHeaders {
    NSDictionary *headers = %orig;
    return DYYYLoginBypassHeadersByReplacingBundleIdentifiers(headers);
}

- (void)setHTTPAdditionalHeaders:(NSDictionary *)headers {
    %orig(DYYYLoginBypassHeadersByReplacingBundleIdentifiers(headers));
}
%end

%end

%group DYYYLoginBypassAccountLifecycle

%hook AWEUserServiceListener

- (void)didFinishLoginWithUid:(NSString *)userID {
    %orig(userID);
    [DYYYLoginBypassManager handleOfficialLoginCompletionWithUserID:userID];
}

%end

%end

%group DYYYLoginBypassAccountLogout

%hook AWEUserServiceListener

- (void)didFinishLogoutWithUid:(NSString *)userID {
    %orig(userID);
    [DYYYLoginBypassManager handleOfficialLogout];
}

%end

%end

%group DYYYLoginBypassAccountLifecycleDidFinishLogin

%hook AWEUserServiceListener

- (void)didFinishLogin:(id)user {
    %orig(user);
    [DYYYLoginBypassManager handleOfficialLoginCompletionWithUserID:user];
}

%end

%end

%group DYYYLoginBypassAccountMulticast

%hook TTAccountMulticast

- (void)broadcastLoginSuccess:(id)user platform:(id)platform reason:(long long)reason {
    %orig(user, platform, reason);
    [DYYYLoginBypassManager handleOfficialLoginCompletionWithUserID:user];
}

%end

%end

%group DYYYLoginBypassVersionUpdateAlert
%hook AWEVersionUpdateAlert
- (BOOL)canShow {
    return DYYYShouldBlockVersionUpdateWorkflow() ? NO : %orig;
}

- (BOOL)canShowWithUpgradeStatus {
    return DYYYShouldBlockVersionUpdateWorkflow() ? NO : %orig;
}

- (BOOL)isUpgradeStatusVersionValid {
    return DYYYShouldBlockVersionUpdateWorkflow() ? NO : %orig;
}

- (BOOL)versionCompareForNeedUpgrade {
    return DYYYShouldBlockVersionUpdateWorkflow() ? NO : %orig;
}

- (void)showWithCloseCallback:(id)closeCallback {
    if (DYYYShouldBlockVersionUpdateWorkflow()) {
        DYYYLoginBypassInvokeCloseCallback(closeCallback);
        return;
    }
    %orig(closeCallback);
}

- (void)_showUpgradeModal {
    if (DYYYShouldBlockVersionUpdateWorkflow()) {
        return;
    }
    %orig;
}

- (void)showDialog {
    if (DYYYShouldBlockVersionUpdateWorkflow()) {
        return;
    }
    %orig;
}

- (void)requestNewVersion {
    if (DYYYShouldBlockVersionUpdateWorkflow()) {
        return;
    }
    %orig;
}
%end
%end

%group DYYYLoginBypassVersionUpdatePopup
%hook AWEVersionUpdatePopup
- (BOOL)isShowing {
    return DYYYShouldBlockVersionUpdateWorkflow() ? NO : %orig;
}

- (void)showDialog {
    if (DYYYShouldBlockVersionUpdateWorkflow()) {
        return;
    }
    %orig;
}

- (void)showInfoPanel {
    if (DYYYShouldBlockVersionUpdateWorkflow()) {
        return;
    }
    %orig;
}

- (void)p_showDialog {
    if (DYYYShouldBlockVersionUpdateWorkflow()) {
        return;
    }
    %orig;
}

- (void)p_showInfoPanel {
    if (DYYYShouldBlockVersionUpdateWorkflow()) {
        return;
    }
    %orig;
}
%end
%end

%group DYYYLoginBypassVersionUpdateWorkflow
%hook AWEVersionUpdateWorkflow
- (void)startVersionUpdateWorkflow:(id)request completion:(id)completion {
    if (DYYYShouldBlockVersionUpdateWorkflow()) {
        DYYYLoginBypassInvokeCloseCallback(completion);
        return;
    }
    %orig(request, completion);
}

- (void)openAppStore {
    if (DYYYShouldBlockVersionUpdateWorkflow()) {
        return;
    }
    %orig;
}

- (void)showLoadingView {
    if (DYYYShouldBlockVersionUpdateWorkflow()) {
        return;
    }
    %orig;
}
%end
%end

%group DYYYLoginBypassTeenVersionUpdateManager
%hook AWETeenVersionUpdateManager
- (BOOL)canShow {
    return DYYYShouldBlockVersionUpdateWorkflow() ? NO : %orig;
}

- (void)showWithCloseCallback:(id)closeCallback {
    if (DYYYShouldBlockVersionUpdateWorkflow()) {
        DYYYLoginBypassInvokeCloseCallback(closeCallback);
        return;
    }
    %orig(closeCallback);
}

- (void)p_showUpgradeAlert {
    if (DYYYShouldBlockVersionUpdateWorkflow()) {
        return;
    }
    %orig;
}

- (BOOL)versionCompareForUpgrade {
    return DYYYShouldBlockVersionUpdateWorkflow() ? NO : %orig;
}

- (void)requestNewVersion {
    if (DYYYShouldBlockVersionUpdateWorkflow()) {
        return;
    }
    %orig;
}
%end
%end

%group DYYYLoginBypassPreLoginAlert
%hook AWEPreLoginAlertManager
- (BOOL)canShow {
    return DYYYShouldBlockVersionUpdateWorkflow() ? NO : %orig;
}

- (BOOL)canShowNow {
    return DYYYShouldBlockVersionUpdateWorkflow() ? NO : %orig;
}
%end
%end

%group DYYYLoginBypassPreLoginFrequency
%hook AWEPreLoginAlertManager
- (BOOL)isShowFrequencySatisfied {
    return DYYYShouldBlockVersionUpdateWorkflow() ? NO : %orig;
}

- (BOOL)isShowFrequencySatisfiedByLoginStrategy {
    return DYYYShouldBlockVersionUpdateWorkflow() ? NO : %orig;
}
%end
%end

%group DYYYLoginBypassNewVersionAlert
%hook AWENewVersionAlertManager
- (BOOL)canShow {
    return DYYYShouldBlockVersionUpdateWorkflow() ? NO : %orig;
}
%end
%end


%group DYYYLoginBypassVersionUpdateManager

%hook AWEVersionUpdateManager

- (void)startVersionUpdateWorkflow:(id)arg1 completion:(id)arg2 {
    if (DYYYShouldBlockVersionUpdateWorkflow()) {
        DYYYLoginBypassInvokeCloseCallback(arg2);
    } else {
        %orig;
    }
}

- (id)workflow {
    return DYYYShouldBlockVersionUpdateWorkflow() ? nil : %orig;
}

- (id)badgeModule {
    return DYYYShouldBlockVersionUpdateWorkflow() ? nil : %orig;
}

%end

%end


%ctor {
    // 宿主初始化期间不创建账号服务，也不提前改写 Bundle 身份。
    dispatch_async(dispatch_get_main_queue(), ^{
        [DYYYLoginBypassManager configureInitialStateIfNeeded];
        %init(DYYYLoginBypassCore);
        DYYYLoginRepairInstallHooks();

        Class loginListenerClass = objc_getClass("AWEUserServiceListener");
        if (loginListenerClass && class_getInstanceMethod(loginListenerClass, @selector(didFinishLoginWithUid:))) {
            %init(DYYYLoginBypassAccountLifecycle);
        }
        if (loginListenerClass && class_getInstanceMethod(loginListenerClass, @selector(didFinishLogoutWithUid:))) {
            %init(DYYYLoginBypassAccountLogout);
        }
        if (loginListenerClass && class_getInstanceMethod(loginListenerClass, @selector(didFinishLogin:))) {
            %init(DYYYLoginBypassAccountLifecycleDidFinishLogin);
        }
        Class accountMulticastClass = objc_getClass("TTAccountMulticast");
        if (accountMulticastClass &&
            class_getInstanceMethod(accountMulticastClass, @selector(broadcastLoginSuccess:platform:reason:))) {
            %init(DYYYLoginBypassAccountMulticast);
        }
        if (objc_getClass("AWEVersionUpdateManager")) {
            %init(DYYYLoginBypassVersionUpdateManager);
        }
        if (objc_getClass("AWEVersionUpdateAlert")) {
            %init(DYYYLoginBypassVersionUpdateAlert);
        }
        if (objc_getClass("AWEVersionUpdatePopup")) {
            %init(DYYYLoginBypassVersionUpdatePopup);
        }
        if (objc_getClass("AWEVersionUpdateWorkflow")) {
            %init(DYYYLoginBypassVersionUpdateWorkflow);
        }
        if (objc_getClass("AWETeenVersionUpdateManager")) {
            %init(DYYYLoginBypassTeenVersionUpdateManager);
        }
        Class preLoginAlertClass = objc_getClass("AWEPreLoginAlertManager");
        if (preLoginAlertClass && class_getInstanceMethod(preLoginAlertClass, @selector(canShow)) &&
            class_getInstanceMethod(preLoginAlertClass, @selector(canShowNow))) {
            %init(DYYYLoginBypassPreLoginAlert);
        }
        if (preLoginAlertClass && class_getInstanceMethod(preLoginAlertClass, @selector(isShowFrequencySatisfied)) &&
            class_getInstanceMethod(preLoginAlertClass, @selector(isShowFrequencySatisfiedByLoginStrategy))) {
            %init(DYYYLoginBypassPreLoginFrequency);
        }
        Class newVersionAlertClass = objc_getClass("AWENewVersionAlertManager");
        if (newVersionAlertClass && class_getInstanceMethod(newVersionAlertClass, @selector(canShow))) {
            %init(DYYYLoginBypassNewVersionAlert);
        }
    });
}
