#import "DYYYLoginRepairHooks.h"

#import "DYYYLoginBypassManager.h"

#import <objc/runtime.h>
#import <stdatomic.h>
#import <string.h>

static const NSUInteger kDYYYLoginRepairExpectedInstallCount = 29;

typedef void (*DYYYLoginRepairVoidIMP)(id, SEL);
typedef void (*DYYYLoginRepairVoidBoolIMP)(id, SEL, BOOL);
typedef void (*DYYYLoginRepairVoidObjectIMP)(id, SEL, id);
typedef BOOL (*DYYYLoginRepairBoolIMP)(id, SEL);
typedef id (*DYYYLoginRepairObjectIMP)(id, SEL);
typedef id (*DYYYLoginRepairObjectArgIMP)(id, SEL, id);
typedef void (*DYYYLoginRepairVoidBlockIMP)(id, SEL, id);
typedef id (*DYYYLoginRepairBlockIMP)(id, SEL);
typedef void (*DYYYLoginRepairStatusCollectFetchIMP)(id, SEL, BOOL, id, int, id);
typedef void (*DYYYLoginRepairStatusCollectParamsIMP)(id, SEL, id, id, int, id);
typedef id (*DYYYLoginRepairEncryptDtraitIMP)(id, SEL, long long, unsigned long long, id, id *);

static atomic_bool gDYYYLoginRepairHooksStarted = false;

#define DYYY_LR_SLOT(name) static IMP gOrig_##name = NULL

DYYY_LR_SLOT(setEnableCollectGF);
DYYY_LR_SLOT(enableCollectGF);
DYYY_LR_SLOT(setEnableDtrait);
DYYY_LR_SLOT(enableDtrait);
DYYY_LR_SLOT(setRequestNeedDtraitBlock);
DYYY_LR_SLOT(requestNeedDtraitBlock);
DYYY_LR_SLOT(fetchGFIfNeeded);
DYYY_LR_SLOT(preloadDtraitID);
DYYY_LR_SLOT(refreshDtraitConfigID);
DYYY_LR_SLOT(gfManager);
DYYY_LR_SLOT(dtraitCollectConfigEmpty);
DYYY_LR_SLOT(dtraitConfigFromFile);
DYYY_LR_SLOT(encryptConfigFromFile);
DYYY_LR_SLOT(delayCollectGF);
DYYY_LR_SLOT(preloadDtraitGF);
DYYY_LR_SLOT(refreshDtraitConfigGF);
DYYY_LR_SLOT(requestBindDtrait);
DYYY_LR_SLOT(saveDtraitConfig);
DYYY_LR_SLOT(saveEncryptConfigWith);
DYYY_LR_SLOT(saveRemoteConfigIfNeeded);
DYYY_LR_SLOT(startStatusCollectFetch);
DYYY_LR_SLOT(startStatusCollectParams);
DYYY_LR_SLOT(addDtraitRequestFilter);
DYYY_LR_SLOT(encryptDtrait);
DYYY_LR_SLOT(ttHttpSetURL);
DYYY_LR_SLOT(ttHttpChromiumSetUrlString);
DYYY_LR_SLOT(ttHttpChromiumSetURL);
DYYY_LR_SLOT(ttAccountSetURLString);
DYYY_LR_SLOT(ttNetworkTransferedURL);

static BOOL DYYYLoginRepairEnabled(void) {
    return [DYYYLoginBypassManager shouldApplyLoginNetworkCamouflage];
}

static void DYYYLoginRepairLogTriggerOnce(SEL selector) {
    static NSMutableSet<NSString *> *logged = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      logged = [NSMutableSet set];
    });
    NSString *name = NSStringFromSelector(selector);
    if (name.length == 0) {
        return;
    }
    @synchronized(logged) {
        if ([logged containsObject:name]) {
            return;
        }
        [logged addObject:name];
    }
    NSLog(@"[DYYY][绕登录] hook-trigger %@", name);
}

static BOOL DYYYLoginRepairClassDefinesSelector(Class targetClass, SEL selector) {
    unsigned int methodCount = 0;
    Method *methods = class_copyMethodList(targetClass, &methodCount);
    BOOL found = NO;
    for (unsigned int index = 0; index < methodCount; index++) {
        if (method_getName(methods[index]) == selector) {
            found = YES;
            break;
        }
    }
    free(methods);
    return found;
}

static BOOL DYYYLoginRepairEncodingAllowed(const char *actual, const char *const *allowed, size_t allowedCount) {
    if (!actual) {
        return NO;
    }
    for (size_t index = 0; index < allowedCount; index++) {
        if (allowed[index] && strcmp(actual, allowed[index]) == 0) {
            return YES;
        }
    }
    return NO;
}

static BOOL DYYYLoginRepairInstallHook(Class targetClass,
                                       SEL selector,
                                       BOOL classMethod,
                                       const char *const *allowedEncodings,
                                       size_t allowedCount,
                                       IMP replacement,
                                       IMP *originalSlot) {
    if (!targetClass || !selector || !allowedEncodings || allowedCount == 0 || !replacement || !originalSlot) {
        return NO;
    }

    Class hookClass = classMethod ? object_getClass(targetClass) : targetClass;
    if (!hookClass) {
        return NO;
    }
    if (!DYYYLoginRepairClassDefinesSelector(hookClass, selector)) {
        NSLog(@"[DYYY][绕登录] hook-skip class=%s sel=%@ classMethod=%d encoding=(absent-on-class)",
              class_getName(targetClass), NSStringFromSelector(selector), classMethod ? 1 : 0);
        return NO;
    }

    Method method = classMethod ? class_getClassMethod(targetClass, selector) : class_getInstanceMethod(targetClass, selector);
    const char *actualTypeEncoding = method ? method_getTypeEncoding(method) : NULL;
    if (!method || !DYYYLoginRepairEncodingAllowed(actualTypeEncoding, allowedEncodings, allowedCount)) {
        NSLog(@"[DYYY][绕登录] hook-skip class=%s sel=%@ classMethod=%d encoding=%s",
              class_getName(targetClass), NSStringFromSelector(selector), classMethod ? 1 : 0,
              actualTypeEncoding ?: "(null)");
        return NO;
    }

    IMP currentIMP = method_getImplementation(method);
    if (currentIMP == replacement) {
        return YES;
    }
    if (*originalSlot) {
        return NO;
    }

    IMP originalIMP = method_setImplementation(method, replacement);
    if (!originalIMP || originalIMP == replacement) {
        return NO;
    }
    *originalSlot = originalIMP;
    return YES;
}

#pragma mark - Replacements

static void DYYYLoginRepairSetEnableCollectGF(id self, SEL _cmd, BOOL enabled) {
    DYYYLoginRepairLogTriggerOnce(_cmd);
    BOOL gated = DYYYLoginRepairEnabled() ? NO : enabled;
    DYYYLoginRepairVoidBoolIMP original = (DYYYLoginRepairVoidBoolIMP)gOrig_setEnableCollectGF;
    if (original) {
        original(self, _cmd, gated);
    }
}

static BOOL DYYYLoginRepairEnableCollectGF(id self, SEL _cmd) {
    DYYYLoginRepairLogTriggerOnce(_cmd);
    if (DYYYLoginRepairEnabled()) {
        return NO;
    }
    DYYYLoginRepairBoolIMP original = (DYYYLoginRepairBoolIMP)gOrig_enableCollectGF;
    return original ? original(self, _cmd) : NO;
}

static void DYYYLoginRepairSetEnableDtrait(id self, SEL _cmd, BOOL enabled) {
    DYYYLoginRepairLogTriggerOnce(_cmd);
    BOOL gated = DYYYLoginRepairEnabled() ? NO : enabled;
    DYYYLoginRepairVoidBoolIMP original = (DYYYLoginRepairVoidBoolIMP)gOrig_setEnableDtrait;
    if (original) {
        original(self, _cmd, gated);
    }
}

static BOOL DYYYLoginRepairEnableDtrait(id self, SEL _cmd) {
    DYYYLoginRepairLogTriggerOnce(_cmd);
    if (DYYYLoginRepairEnabled()) {
        return NO;
    }
    DYYYLoginRepairBoolIMP original = (DYYYLoginRepairBoolIMP)gOrig_enableDtrait;
    return original ? original(self, _cmd) : NO;
}

static void DYYYLoginRepairSetRequestNeedDtraitBlock(id self, SEL _cmd, id block) {
    DYYYLoginRepairLogTriggerOnce(_cmd);
    DYYYLoginRepairVoidBlockIMP original = (DYYYLoginRepairVoidBlockIMP)gOrig_setRequestNeedDtraitBlock;
    if (original) {
        original(self, _cmd, DYYYLoginRepairEnabled() ? nil : block);
    }
}

static id DYYYLoginRepairRequestNeedDtraitBlock(id self, SEL _cmd) {
    DYYYLoginRepairLogTriggerOnce(_cmd);
    if (DYYYLoginRepairEnabled()) {
        return nil;
    }
    DYYYLoginRepairBlockIMP original = (DYYYLoginRepairBlockIMP)gOrig_requestNeedDtraitBlock;
    return original ? original(self, _cmd) : nil;
}

static void DYYYLoginRepairFetchGFIfNeeded(id self, SEL _cmd) {
    DYYYLoginRepairLogTriggerOnce(_cmd);
    if (DYYYLoginRepairEnabled()) {
        return;
    }
    DYYYLoginRepairVoidIMP original = (DYYYLoginRepairVoidIMP)gOrig_fetchGFIfNeeded;
    if (original) {
        original(self, _cmd);
    }
}

static void DYYYLoginRepairPreloadDtraitID(id self, SEL _cmd) {
    DYYYLoginRepairLogTriggerOnce(_cmd);
    if (DYYYLoginRepairEnabled()) {
        return;
    }
    DYYYLoginRepairVoidIMP original = (DYYYLoginRepairVoidIMP)gOrig_preloadDtraitID;
    if (original) {
        original(self, _cmd);
    }
}

static void DYYYLoginRepairRefreshDtraitConfigID(id self, SEL _cmd, id config) {
    DYYYLoginRepairLogTriggerOnce(_cmd);
    if (DYYYLoginRepairEnabled()) {
        return;
    }
    DYYYLoginRepairVoidObjectIMP original = (DYYYLoginRepairVoidObjectIMP)gOrig_refreshDtraitConfigID;
    if (original) {
        original(self, _cmd, config);
    }
}

static id DYYYLoginRepairGFManager(id self, SEL _cmd) {
    DYYYLoginRepairLogTriggerOnce(_cmd);
    if (DYYYLoginRepairEnabled()) {
        return nil;
    }
    DYYYLoginRepairObjectIMP original = (DYYYLoginRepairObjectIMP)gOrig_gfManager;
    return original ? original(self, _cmd) : nil;
}

static BOOL DYYYLoginRepairDtraitCollectConfigEmpty(id self, SEL _cmd) {
    DYYYLoginRepairLogTriggerOnce(_cmd);
    if (DYYYLoginRepairEnabled()) {
        return YES;
    }
    DYYYLoginRepairBoolIMP original = (DYYYLoginRepairBoolIMP)gOrig_dtraitCollectConfigEmpty;
    return original ? original(self, _cmd) : YES;
}

static id DYYYLoginRepairDtraitConfigFromFile(id self, SEL _cmd) {
    DYYYLoginRepairLogTriggerOnce(_cmd);
    if (DYYYLoginRepairEnabled()) {
        return nil;
    }
    DYYYLoginRepairObjectIMP original = (DYYYLoginRepairObjectIMP)gOrig_dtraitConfigFromFile;
    return original ? original(self, _cmd) : nil;
}

static id DYYYLoginRepairEncryptConfigFromFile(id self, SEL _cmd) {
    DYYYLoginRepairLogTriggerOnce(_cmd);
    if (DYYYLoginRepairEnabled()) {
        return nil;
    }
    DYYYLoginRepairObjectIMP original = (DYYYLoginRepairObjectIMP)gOrig_encryptConfigFromFile;
    return original ? original(self, _cmd) : nil;
}

static void DYYYLoginRepairDelayCollectGF(id self, SEL _cmd) {
    DYYYLoginRepairLogTriggerOnce(_cmd);
    if (DYYYLoginRepairEnabled()) {
        return;
    }
    DYYYLoginRepairVoidIMP original = (DYYYLoginRepairVoidIMP)gOrig_delayCollectGF;
    if (original) {
        original(self, _cmd);
    }
}

static void DYYYLoginRepairPreloadDtraitGF(id self, SEL _cmd) {
    DYYYLoginRepairLogTriggerOnce(_cmd);
    if (DYYYLoginRepairEnabled()) {
        return;
    }
    DYYYLoginRepairVoidIMP original = (DYYYLoginRepairVoidIMP)gOrig_preloadDtraitGF;
    if (original) {
        original(self, _cmd);
    }
}

static void DYYYLoginRepairRefreshDtraitConfigGF(id self, SEL _cmd, id config) {
    DYYYLoginRepairLogTriggerOnce(_cmd);
    if (DYYYLoginRepairEnabled()) {
        return;
    }
    DYYYLoginRepairVoidObjectIMP original = (DYYYLoginRepairVoidObjectIMP)gOrig_refreshDtraitConfigGF;
    if (original) {
        original(self, _cmd, config);
    }
}

static void DYYYLoginRepairRequestBindDtrait(id self, SEL _cmd) {
    DYYYLoginRepairLogTriggerOnce(_cmd);
    if (DYYYLoginRepairEnabled()) {
        return;
    }
    DYYYLoginRepairVoidIMP original = (DYYYLoginRepairVoidIMP)gOrig_requestBindDtrait;
    if (original) {
        original(self, _cmd);
    }
}

static void DYYYLoginRepairSaveDtraitConfig(id self, SEL _cmd, id config) {
    DYYYLoginRepairLogTriggerOnce(_cmd);
    if (DYYYLoginRepairEnabled()) {
        return;
    }
    DYYYLoginRepairVoidObjectIMP original = (DYYYLoginRepairVoidObjectIMP)gOrig_saveDtraitConfig;
    if (original) {
        original(self, _cmd, config);
    }
}

static void DYYYLoginRepairSaveEncryptConfigWith(id self, SEL _cmd, id config) {
    DYYYLoginRepairLogTriggerOnce(_cmd);
    if (DYYYLoginRepairEnabled()) {
        return;
    }
    DYYYLoginRepairVoidObjectIMP original = (DYYYLoginRepairVoidObjectIMP)gOrig_saveEncryptConfigWith;
    if (original) {
        original(self, _cmd, config);
    }
}

static void DYYYLoginRepairSaveRemoteConfigIfNeeded(id self, SEL _cmd, id config) {
    DYYYLoginRepairLogTriggerOnce(_cmd);
    if (DYYYLoginRepairEnabled()) {
        return;
    }
    DYYYLoginRepairVoidObjectIMP original = (DYYYLoginRepairVoidObjectIMP)gOrig_saveRemoteConfigIfNeeded;
    if (original) {
        original(self, _cmd, config);
    }
}

static void DYYYLoginRepairStartStatusCollectFetch(id self, SEL _cmd, BOOL fetchConfig, id secDtrait, int retryCount, id callback) {
    DYYYLoginRepairLogTriggerOnce(_cmd);
    if (DYYYLoginRepairEnabled()) {
        return;
    }
    DYYYLoginRepairStatusCollectFetchIMP original = (DYYYLoginRepairStatusCollectFetchIMP)gOrig_startStatusCollectFetch;
    if (original) {
        original(self, _cmd, fetchConfig, secDtrait, retryCount, callback);
    }
}

static void DYYYLoginRepairStartStatusCollectParams(id self, SEL _cmd, id params, id secDtrait, int retryCount, id callback) {
    DYYYLoginRepairLogTriggerOnce(_cmd);
    if (DYYYLoginRepairEnabled()) {
        return;
    }
    DYYYLoginRepairStatusCollectParamsIMP original = (DYYYLoginRepairStatusCollectParamsIMP)gOrig_startStatusCollectParams;
    if (original) {
        original(self, _cmd, params, secDtrait, retryCount, callback);
    }
}

static void DYYYLoginRepairAddDtraitRequestFilter(id self, SEL _cmd) {
    DYYYLoginRepairLogTriggerOnce(_cmd);
    if (DYYYLoginRepairEnabled()) {
        return;
    }
    DYYYLoginRepairVoidIMP original = (DYYYLoginRepairVoidIMP)gOrig_addDtraitRequestFilter;
    if (original) {
        original(self, _cmd);
    }
}

static id DYYYLoginRepairEncryptDtrait(id self, SEL _cmd, long long type, unsigned long long timeout, id path, id *outError) {
    DYYYLoginRepairLogTriggerOnce(_cmd);
    if (DYYYLoginRepairEnabled()) {
        if (outError) {
            *outError = nil;
        }
        return nil;
    }
    DYYYLoginRepairEncryptDtraitIMP original = (DYYYLoginRepairEncryptDtraitIMP)gOrig_encryptDtrait;
    return original ? original(self, _cmd, type, timeout, path, outError) : nil;
}

static id DYYYLoginRepairRewrittenURLValue(id value) {
    if ([value isKindOfClass:NSURL.class]) {
        return [DYYYLoginBypassManager URLByReplacingTargetBundleIdentifiers:value];
    }
    if ([value isKindOfClass:NSString.class]) {
        return [DYYYLoginBypassManager stringByReplacingTargetBundleIdentifiers:value];
    }
    return value;
}

static void DYYYLoginRepairSetURL(id self, SEL _cmd, id url, IMP originalIMP) {
    DYYYLoginRepairLogTriggerOnce(_cmd);
    DYYYLoginRepairVoidObjectIMP original = (DYYYLoginRepairVoidObjectIMP)originalIMP;
    if (original) {
        original(self, _cmd, DYYYLoginRepairRewrittenURLValue(url));
    }
}

static void DYYYLoginRepairTTHttpSetURL(id self, SEL _cmd, id url) {
    DYYYLoginRepairSetURL(self, _cmd, url, gOrig_ttHttpSetURL);
}

static void DYYYLoginRepairTTHttpChromiumSetUrlString(id self, SEL _cmd, id url) {
    DYYYLoginRepairSetURL(self, _cmd, url, gOrig_ttHttpChromiumSetUrlString);
}

static void DYYYLoginRepairTTHttpChromiumSetURL(id self, SEL _cmd, id url) {
    DYYYLoginRepairSetURL(self, _cmd, url, gOrig_ttHttpChromiumSetURL);
}

static void DYYYLoginRepairTTAccountSetURLString(id self, SEL _cmd, id url) {
    DYYYLoginRepairSetURL(self, _cmd, url, gOrig_ttAccountSetURLString);
}

static id DYYYLoginRepairTransferedURL(id self, SEL _cmd, id url, IMP originalIMP) {
    DYYYLoginRepairLogTriggerOnce(_cmd);
    DYYYLoginRepairObjectArgIMP original = (DYYYLoginRepairObjectArgIMP)originalIMP;
    id originalURL = original ? original(self, _cmd, url) : url;
    return DYYYLoginRepairRewrittenURLValue(originalURL);
}

static id DYYYLoginRepairTTNetworkTransferedURL(id self, SEL _cmd, id url) {
    return DYYYLoginRepairTransferedURL(self, _cmd, url, gOrig_ttNetworkTransferedURL);
}

#pragma mark - Install

void DYYYLoginRepairInstallHooks(void) {
    bool expected = false;
    if (!atomic_compare_exchange_strong(&gDYYYLoginRepairHooksStarted, &expected, true)) {
        return;
    }

    const char *boolGetter[] = {"B16@0:8"};
    const char *boolSetter[] = {"v20@0:8B16", "v20@0:8c16"};
    const char *voidNoArgs[] = {"v16@0:8"};
    const char *voidObject[] = {"v24@0:8@16"};
    const char *objectGetter[] = {"@16@0:8"};
    const char *blockSetter[] = {"v24@0:8@?16"};
    const char *blockGetter[] = {"@?16@0:8", "@16@0:8"};
    const char *statusCollectFetch[] = {"v40@0:8B16@20i28@?32"};
    const char *statusCollectParams[] = {"v44@0:8@16@24i32@?36"};
    const char *encryptDtrait[] = {"@48@0:8q16Q24@32^@40"};
    const char *transferedURL[] = {"@24@0:8@16"};

    typedef struct {
        const char *className;
        SEL selector;
        BOOL classMethod;
        const char *const *encodings;
        size_t encodingCount;
        IMP replacement;
        IMP *originalSlot;
    } DYYYLoginRepairSpec;

    DYYYLoginRepairSpec specs[] = {
        {"TTInstallIDManager", @selector(setEnableCollectGF:), NO, boolSetter, 2, (IMP)DYYYLoginRepairSetEnableCollectGF, &gOrig_setEnableCollectGF},
        {"TTInstallIDManager", @selector(enableCollectGF), NO, boolGetter, 1, (IMP)DYYYLoginRepairEnableCollectGF, &gOrig_enableCollectGF},
        {"TTInstallIDManager", @selector(setEnableDtrait:), NO, boolSetter, 2, (IMP)DYYYLoginRepairSetEnableDtrait, &gOrig_setEnableDtrait},
        {"TTInstallIDManager", @selector(enableDtrait), NO, boolGetter, 1, (IMP)DYYYLoginRepairEnableDtrait, &gOrig_enableDtrait},
        {"TTInstallIDManager", @selector(setRequestNeedDtraitBlock:), NO, blockSetter, 1, (IMP)DYYYLoginRepairSetRequestNeedDtraitBlock, &gOrig_setRequestNeedDtraitBlock},
        {"TTInstallIDManager", @selector(requestNeedDtraitBlock), NO, blockGetter, 2, (IMP)DYYYLoginRepairRequestNeedDtraitBlock, &gOrig_requestNeedDtraitBlock},
        {"TTInstallIDManager", NSSelectorFromString(@"_fetchGFIfNeeded"), NO, voidNoArgs, 1, (IMP)DYYYLoginRepairFetchGFIfNeeded, &gOrig_fetchGFIfNeeded},
        {"TTInstallIDManager", NSSelectorFromString(@"_preloadDtrait"), NO, voidNoArgs, 1, (IMP)DYYYLoginRepairPreloadDtraitID, &gOrig_preloadDtraitID},
        {"TTInstallIDManager", NSSelectorFromString(@"_refreshDtraitConfig:"), NO, voidObject, 1, (IMP)DYYYLoginRepairRefreshDtraitConfigID, &gOrig_refreshDtraitConfigID},
        {"TTInstallIDManager", @selector(gfManager), NO, objectGetter, 1, (IMP)DYYYLoginRepairGFManager, &gOrig_gfManager},
        {"TTInstallGFManager", @selector(dtraitCollectConfigEmpty), NO, boolGetter, 1, (IMP)DYYYLoginRepairDtraitCollectConfigEmpty, &gOrig_dtraitCollectConfigEmpty},
        {"TTInstallGFManager", @selector(dtraitConfigFromFile), NO, objectGetter, 1, (IMP)DYYYLoginRepairDtraitConfigFromFile, &gOrig_dtraitConfigFromFile},
        {"TTInstallGFManager", @selector(encryptConfigFromFile), NO, objectGetter, 1, (IMP)DYYYLoginRepairEncryptConfigFromFile, &gOrig_encryptConfigFromFile},
        {"TTInstallGFManager", @selector(delayCollectGFAfterRegisterSuccess), NO, voidNoArgs, 1, (IMP)DYYYLoginRepairDelayCollectGF, &gOrig_delayCollectGF},
        {"TTInstallGFManager", @selector(preloadDtrait), NO, voidNoArgs, 1, (IMP)DYYYLoginRepairPreloadDtraitGF, &gOrig_preloadDtraitGF},
        {"TTInstallGFManager", @selector(refreshDtraitConfig:), NO, voidObject, 1, (IMP)DYYYLoginRepairRefreshDtraitConfigGF, &gOrig_refreshDtraitConfigGF},
        {"TTInstallGFManager", @selector(requestBindDtrait), NO, voidNoArgs, 1, (IMP)DYYYLoginRepairRequestBindDtrait, &gOrig_requestBindDtrait},
        {"TTInstallGFManager", @selector(saveDtraitConfig:), NO, voidObject, 1, (IMP)DYYYLoginRepairSaveDtraitConfig, &gOrig_saveDtraitConfig},
        {"TTInstallGFManager", @selector(saveEncryptConfigWith:), NO, voidObject, 1, (IMP)DYYYLoginRepairSaveEncryptConfigWith, &gOrig_saveEncryptConfigWith},
        {"TTInstallGFManager", @selector(saveRemoteConfigIfNeeded:), NO, voidObject, 1, (IMP)DYYYLoginRepairSaveRemoteConfigIfNeeded, &gOrig_saveRemoteConfigIfNeeded},
        {"TTInstallGFManager", NSSelectorFromString(@"startStatusCollectWithFetchConfig:secDtrait:retryCount:callback:"), NO, statusCollectFetch, 1,
         (IMP)DYYYLoginRepairStartStatusCollectFetch, &gOrig_startStatusCollectFetch},
        {"TTInstallGFManager", NSSelectorFromString(@"startStatusCollectWithParams:secDtrait:retryCount:callback:"), NO, statusCollectParams, 1,
         (IMP)DYYYLoginRepairStartStatusCollectParams, &gOrig_startStatusCollectParams},
        {"TTInstallDtraitBizUtil", @selector(addDtraitRequestFilter), YES, voidNoArgs, 1, (IMP)DYYYLoginRepairAddDtraitRequestFilter, &gOrig_addDtraitRequestFilter},
        {"TTInstallDtraitBizUtil", NSSelectorFromString(@"encryptDtraitWithType:timtout:path:outError:"), YES, encryptDtrait, 1, (IMP)DYYYLoginRepairEncryptDtrait,
         &gOrig_encryptDtrait},
        {"TTHttpRequest", @selector(setURL:), NO, voidObject, 1, (IMP)DYYYLoginRepairTTHttpSetURL, &gOrig_ttHttpSetURL},
        {"TTHttpRequestChromium", @selector(setUrlString:), NO, voidObject, 1, (IMP)DYYYLoginRepairTTHttpChromiumSetUrlString, &gOrig_ttHttpChromiumSetUrlString},
        {"TTHttpRequestChromium", @selector(setURL:), NO, voidObject, 1, (IMP)DYYYLoginRepairTTHttpChromiumSetURL, &gOrig_ttHttpChromiumSetURL},
        {"TTAccountHttpRequest", @selector(setURLString:), NO, voidObject, 1, (IMP)DYYYLoginRepairTTAccountSetURLString, &gOrig_ttAccountSetURLString},
        {"TTNetworkManager", @selector(transferedURL:), NO, transferedURL, 1, (IMP)DYYYLoginRepairTTNetworkTransferedURL, &gOrig_ttNetworkTransferedURL},
    };

    NSUInteger targetCount = 0;
    NSUInteger installed = 0;
    NSMutableSet<NSString *> *seenClasses = [NSMutableSet set];
    for (size_t index = 0; index < sizeof(specs) / sizeof(specs[0]); index++) {
        Class cls = objc_getClass(specs[index].className);
        if (cls && ![seenClasses containsObject:@(specs[index].className)]) {
            [seenClasses addObject:@(specs[index].className)];
            targetCount += 1;
        }
        if (DYYYLoginRepairInstallHook(cls, specs[index].selector, specs[index].classMethod, specs[index].encodings, specs[index].encodingCount,
                                       specs[index].replacement, specs[index].originalSlot)) {
            installed += 1;
        }
    }

    NSLog(@"[DYYY][绕登录] hook-init status=%@ targets=%lu installed=%lu expected=%lu enabled=%d",
          installed == kDYYYLoginRepairExpectedInstallCount ? @"PASS" : @"PARTIAL", (unsigned long)targetCount, (unsigned long)installed,
          (unsigned long)kDYYYLoginRepairExpectedInstallCount, DYYYLoginRepairEnabled() ? 1 : 0);
}
