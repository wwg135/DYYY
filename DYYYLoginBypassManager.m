#import "DYYYLoginBypassManager.h"

#import "AwemeHeaders.h"
#import "DYYYUtils.h"
#import <objc/message.h>
#import <stdatomic.h>

static NSString *const kDYYYLoginBypassManagerEnabledKey = @"DYYYEnableLoginBypass";
static NSString *const kDYYYOfficialAwemeBundleIdentifier = @"com.ss.iphone.ugc.Aweme";
static NSString *const kDYYYLoginBypassDisabledToast = @"检测账号登录，绕登录设置关闭";
static NSString *const kDYYYLoginBypassManualCloseToast = @"检测登录态失败，请手动关闭绕登录设置";

typedef NS_ENUM(NSUInteger, DYYYOfficialAccountLoginState) {
    DYYYOfficialAccountLoginStateUnknown,
    DYYYOfficialAccountLoginStateLoggedOut,
    DYYYOfficialAccountLoginStateLoggedIn,
};

static NSString *dyyyLoginBypassDefaultsDomainName = nil;
static BOOL dyyyLoginBypassInitialConfigurationPending = NO;
static BOOL dyyyLoginBypassDisableInFlight = NO;
static BOOL dyyyLoginBypassPostLoginNetworkRestore = NO;
static CFAbsoluteTime dyyyLoginBypassLastHandledAt = 0;
static atomic_bool dyyyLoginBypassEnabled = false;

@implementation DYYYLoginBypassManager

#pragma mark - Official account helpers

+ (DYYYOfficialAccountLoginState)officialAccountLoginState {
    Class serviceClass = NSClassFromString(@"AWEUserService");
    if (!serviceClass || ![serviceClass respondsToSelector:@selector(sharedService)]) {
        return DYYYOfficialAccountLoginStateUnknown;
    }

    @try {
        AWEUserService *service = ((id (*)(id, SEL))objc_msgSend)(serviceClass, @selector(sharedService));
        if (!service || ![service respondsToSelector:@selector(isLogin)]) {
            return DYYYOfficialAccountLoginStateUnknown;
        }

        return [service isLogin] ? DYYYOfficialAccountLoginStateLoggedIn : DYYYOfficialAccountLoginStateLoggedOut;
    } @catch (NSException *exception) {
        NSLog(@"[DYYY][绕登录] 账号登录态检测异常：%@", exception.reason);
        return DYYYOfficialAccountLoginStateUnknown;
    }
}

+ (nullable NSString *)normalizedUserID:(id)value {
    NSString *userID = nil;
    if ([value isKindOfClass:NSString.class]) {
        userID = value;
    } else if ([value respondsToSelector:@selector(stringValue)]) {
        userID = [value stringValue];
    }

    userID = [userID stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (userID.length == 0 ||
        [userID rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location != NSNotFound) {
        return nil;
    }

    NSCharacterSet *nonZeroDigits = [NSCharacterSet characterSetWithCharactersInString:@"123456789"];
    return [userID rangeOfCharacterFromSet:nonZeroDigits].location == NSNotFound ? nil : userID;
}

+ (nullable NSString *)userIDFromLoginPayload:(id)userIDOrAccount {
    NSString *direct = [self normalizedUserID:userIDOrAccount];
    if (direct.length > 0) {
        return direct;
    }
    if (!userIDOrAccount) {
        return nil;
    }

    @try {
        if ([userIDOrAccount respondsToSelector:@selector(userID)]) {
            return [self normalizedUserID:[userIDOrAccount userID]];
        }
    } @catch (NSException *exception) {
        NSLog(@"[DYYY][绕登录] 解析登录载荷 UID 异常：%@", exception.reason);
    }
    return nil;
}

+ (nullable NSString *)currentOfficialUserID {
    Class serviceClass = NSClassFromString(@"AWEUserService");
    if (!serviceClass || ![serviceClass respondsToSelector:@selector(sharedService)]) {
        return nil;
    }

    @try {
        AWEUserService *service = ((id (*)(id, SEL))objc_msgSend)(serviceClass, @selector(sharedService));
        if (!service) {
            return nil;
        }

        if ([service respondsToSelector:@selector(userID)]) {
            NSString *serviceUserID = [self normalizedUserID:[service userID]];
            if (serviceUserID.length > 0) {
                return serviceUserID;
            }
        }

        if ([service respondsToSelector:@selector(currentLoginUser)]) {
            AWEUserModel *currentUser = [service currentLoginUser];
            if ([currentUser respondsToSelector:@selector(userID)]) {
                return [self normalizedUserID:[currentUser userID]];
            }
        }
    } @catch (NSException *exception) {
        NSLog(@"[DYYY][绕登录] 读取官方 UID 异常：%@", exception.reason);
    }
    return nil;
}

+ (BOOL)officialUserServiceConfirmsLoginWithUserID:(NSString *)callbackUserID {
    Class serviceClass = NSClassFromString(@"AWEUserService");
    if (!serviceClass || ![serviceClass respondsToSelector:@selector(sharedService)]) {
        return NO;
    }

    @try {
        AWEUserService *service = ((id (*)(id, SEL))objc_msgSend)(serviceClass, @selector(sharedService));
        if (!service ||
            ![service respondsToSelector:@selector(isLogin)] ||
            ![service respondsToSelector:@selector(userID)] ||
            ![service isLogin]) {
            return NO;
        }

        NSString *serviceUserID = [self normalizedUserID:[service userID]];
        NSString *modelUserID = nil;
        if ([service respondsToSelector:@selector(currentLoginUser)]) {
            AWEUserModel *currentUser = [service currentLoginUser];
            if ([currentUser respondsToSelector:@selector(userID)]) {
                modelUserID = [self normalizedUserID:[currentUser userID]];
            }
        }

        return (serviceUserID.length > 0 && [serviceUserID isEqualToString:callbackUserID]) ||
               (modelUserID.length > 0 && [modelUserID isEqualToString:callbackUserID]);
    } @catch (NSException *exception) {
        NSLog(@"[DYYY][绕登录] 官方账号服务状态校验异常：%@", exception.reason);
        return NO;
    }
}

+ (BOOL)officialUserServiceConfirmsLoginWeakly {
    return [self officialAccountLoginState] == DYYYOfficialAccountLoginStateLoggedIn;
}

#pragma mark - Defaults / initial configuration

+ (void)reloadCachedPreference {
    id storedValue = [NSUserDefaults.standardUserDefaults objectForKey:kDYYYLoginBypassManagerEnabledKey];
    atomic_store_explicit(&dyyyLoginBypassEnabled, storedValue == nil || [storedValue boolValue], memory_order_release);
}

+ (BOOL)hasPersistentLoginBypassSetting {
    if (dyyyLoginBypassDefaultsDomainName.length == 0) {
        return YES;
    }

    @try {
        NSDictionary *persistentDomain =
            [NSUserDefaults.standardUserDefaults persistentDomainForName:dyyyLoginBypassDefaultsDomainName];
        return persistentDomain[kDYYYLoginBypassManagerEnabledKey] != nil;
    } @catch (NSException *exception) {
        NSLog(@"[DYYY][绕登录] 读取首次配置状态异常：%@", exception.reason);
        return YES;
    }
}

+ (void)persistLoginBypassEnabled:(BOOL)enabled {
    atomic_store_explicit(&dyyyLoginBypassEnabled, enabled, memory_order_release);
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:kDYYYLoginBypassManagerEnabledKey];
    [NSUserDefaults.standardUserDefaults synchronize];
    dyyyLoginBypassInitialConfigurationPending = NO;
}

+ (BOOL)finalizeInitialConfigurationIfPossible {
    if (!dyyyLoginBypassInitialConfigurationPending || [self hasPersistentLoginBypassSetting]) {
        dyyyLoginBypassInitialConfigurationPending = NO;
        return YES;
    }

    DYYYOfficialAccountLoginState loginState = [self officialAccountLoginState];
    if (loginState == DYYYOfficialAccountLoginStateUnknown) {
        return NO;
    }

    BOOL shouldEnable = loginState == DYYYOfficialAccountLoginStateLoggedOut;
    [self persistLoginBypassEnabled:shouldEnable];
    NSLog(@"[DYYY][绕登录] 首次配置已完成，当前账号%@登录，绕登录已%@",
          shouldEnable ? @"未" : @"已",
          shouldEnable ? @"开启" : @"关闭");
    return YES;
}

+ (void)attemptInitialConfigurationWithRetryIndex:(NSUInteger)retryIndex {
    if ([self finalizeInitialConfigurationIfPossible]) {
        return;
    }

    static NSArray<NSNumber *> *retryDelays = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      retryDelays = @[ @0.2, @0.8, @2.0 ];
    });
    if (retryIndex >= retryDelays.count) {
        NSLog(@"[DYYY][绕登录] 首次配置登录态仍未知，保持运行时默认开启");
        return;
    }

    NSTimeInterval delay = retryDelays[retryIndex].doubleValue;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      [self attemptInitialConfigurationWithRetryIndex:retryIndex + 1];
    });
}

+ (void)configureInitialStateIfNeeded {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      [self reloadCachedPreference];
      // 全局 Bundle/网络 Hook 只读取缓存；账号探测与偏好读取不进入这些基础 getter。
      [NSNotificationCenter.defaultCenter addObserverForName:NSUserDefaultsDidChangeNotification
                                                    object:nil
                                                     queue:nil
                                                usingBlock:^(__unused NSNotification *notification) {
        [self reloadCachedPreference];
      }];
      @try {
          dyyyLoginBypassDefaultsDomainName = NSBundle.mainBundle.bundleIdentifier.copy;
      } @catch (NSException *exception) {
          NSLog(@"[DYYY][绕登录] 获取首次配置持久化域异常：%@", exception.reason);
          return;
      }
      if (dyyyLoginBypassDefaultsDomainName.length == 0) {
          return;
      }
      if ([self hasPersistentLoginBypassSetting]) {
          if ([self officialAccountLoginState] == DYYYOfficialAccountLoginStateLoggedIn) {
              dyyyLoginBypassPostLoginNetworkRestore = YES;
          }
          return;
      }

      // 同步探测：已登录场景尽早写 NO，避免 registerDefaults=YES 造成短暂误开。
      DYYYOfficialAccountLoginState loginState = [self officialAccountLoginState];
      if (loginState == DYYYOfficialAccountLoginStateLoggedIn) {
          dyyyLoginBypassPostLoginNetworkRestore = YES;
          [self persistLoginBypassEnabled:NO];
          NSLog(@"[DYYY][绕登录] 首次同步配置：已登录，绕登录已关闭");
          return;
      }
      if (loginState == DYYYOfficialAccountLoginStateLoggedOut) {
          [self persistLoginBypassEnabled:YES];
          NSLog(@"[DYYY][绕登录] 首次同步配置：未登录，绕登录已开启");
          return;
      }

      dyyyLoginBypassInitialConfigurationPending = YES;
      dispatch_async(dispatch_get_main_queue(), ^{
        [self attemptInitialConfigurationWithRetryIndex:0];
      });
    });

    dispatch_async(dispatch_get_main_queue(), ^{
      [self attemptReconcileWithRetryIndex:0];
    });
}

#pragma mark - Bundle identity / request rewrite

+ (NSArray<NSString *> *)officialFamilyBundleIdentifiers {
    static NSArray<NSString *> *bundleIdentifiers = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      bundleIdentifiers = @[
          @"com.ss.iphone.ugc.Aweme",
          @"com.ss.iphone.ugc.Aweme.beta",
          @"com.ss.iphone.ugc.Aweme.internal",
          @"com.ss.iphone.ugc.Aweme.lite",
          @"com.ss.iphone.ugc.aweme.lite"
      ];
    });
    return bundleIdentifiers;
}

+ (BOOL)isNumericAwemeCloneBundleIdentifier:(NSString *)bundleIdentifier {
    if (bundleIdentifier.length != kDYYYOfficialAwemeBundleIdentifier.length + 4) {
        return NO;
    }
    if (![bundleIdentifier hasPrefix:kDYYYOfficialAwemeBundleIdentifier]) {
        return NO;
    }
    NSString *suffix = [bundleIdentifier substringFromIndex:kDYYYOfficialAwemeBundleIdentifier.length];
    NSCharacterSet *nonDigits = NSCharacterSet.decimalDigitCharacterSet.invertedSet;
    return [suffix rangeOfCharacterFromSet:nonDigits].location == NSNotFound;
}

+ (NSString *)realMainBundleIdentifier {
    // 初始化在安装基础 Hook 前已记录原始域名，避免读取 plist 时重入 URL getter 的 dispatch_once。
    return dyyyLoginBypassDefaultsDomainName ?: @"";
}

+ (BOOL)isNumericAwemeCloneProcess {
    return [self isNumericAwemeCloneBundleIdentifier:[self realMainBundleIdentifier]];
}

+ (BOOL)shouldApplyEmojiBundleSpoof {
    return !dyyyLoginBypassPostLoginNetworkRestore && [self isLoginBypassEnabled];
}

+ (BOOL)shouldMaintainCloneSessionIdentity {
    if (![self isNumericAwemeCloneProcess]) {
        return NO;
    }
    return [self isLoginBypassEnabled] || dyyyLoginBypassPostLoginNetworkRestore;
}

+ (BOOL)isTargetBundleIdentifier:(id)value {
    if (![value isKindOfClass:NSString.class]) {
        return NO;
    }
    NSString *bundleIdentifier = value;
    for (NSString *officialIdentifier in [self officialFamilyBundleIdentifiers]) {
        if ([bundleIdentifier isEqualToString:officialIdentifier]) {
            return YES;
        }
    }
    return [self isNumericAwemeCloneBundleIdentifier:bundleIdentifier];
}

+ (NSArray<NSString *> *)emojiSuffixes {
    static NSArray<NSString *> *suffixes = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      suffixes = @[
          @"\U0001F60A", @"\U0001F60E", @"\U0001F914", @"\U0001F609", @"\U0001F60B", @"\U0001F60D", @"\U0001F970",
          @"\U0001F618", @"\U0001F617", @"\U0001F619", @"\U0001F61A", @"\U0001F642", @"\U0001F917", @"\U0001F929",
          @"\U0001F928", @"\U0001F9D0", @"\U0001F913", @"\U0001F607", @"\U0001F973", @"\U0001F60C", @"\U0001F60F",
          @"\U0001F612", @"\U0001F643"
      ];
    });
    return suffixes;
}

+ (BOOL)shouldApplyLoginNetworkCamouflage {
    if ([self isNumericAwemeCloneProcess]) {
        return [self shouldMaintainCloneSessionIdentity];
    }
    return [self shouldApplyEmojiBundleSpoof];
}

+ (NSMutableDictionary<NSString *, NSString *> *)replacementCache {
    static NSMutableDictionary<NSString *, NSString *> *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      cache = [NSMutableDictionary dictionary];
      [NSTimer scheduledTimerWithTimeInterval:60.0
                                      repeats:YES
                                        block:^(__unused NSTimer *timer) {
                                          @synchronized(cache) {
                                              [cache removeAllObjects];
                                          }
                                        }];
    });
    return cache;
}

+ (NSString *)replacementBundleIdentifier:(NSString *)bundleIdentifier {
    if (![bundleIdentifier isKindOfClass:NSString.class] || ![self isTargetBundleIdentifier:bundleIdentifier]) {
        return bundleIdentifier;
    }

    // 分身在绕登录或登录会话内映射为精确官方包名，不加 emoji。
    if ([self isNumericAwemeCloneBundleIdentifier:bundleIdentifier]) {
        return [self shouldMaintainCloneSessionIdentity] ? kDYYYOfficialAwemeBundleIdentifier : bundleIdentifier;
    }

    if (![self shouldApplyEmojiBundleSpoof]) {
        return bundleIdentifier;
    }

    NSMutableDictionary<NSString *, NSString *> *cache = [self replacementCache];
    @synchronized(cache) {
        NSString *cachedValue = cache[bundleIdentifier];
        if (cachedValue.length > 0) {
            return cachedValue;
        }

        NSArray<NSString *> *suffixes = [self emojiSuffixes];
        if (suffixes.count == 0) {
            return bundleIdentifier;
        }

        NSString *suffix = suffixes[arc4random_uniform((uint32_t)suffixes.count)];
        NSString *replacement = [bundleIdentifier stringByAppendingString:suffix];
        if (replacement.length > 0 && cache.count <= 99) {
            cache[bundleIdentifier] = replacement;
        }
        return replacement.length > 0 ? replacement : bundleIdentifier;
    }
}

+ (NSString *)headerValueByReplacingBundleIdentifier:(NSString *)value field:(NSString *)field {
    if (![value isKindOfClass:NSString.class] || ![field isKindOfClass:NSString.class]) {
        return value;
    }

    NSString *lowercaseField = field.lowercaseString;
    BOOL isBundleHeaderField = [lowercaseField isEqualToString:@"x-bundle-id"] || [lowercaseField isEqualToString:@"bundle-identifier"] ||
                               [lowercaseField isEqualToString:@"app-bundle-id"] || [lowercaseField isEqualToString:@"x-app-bundle-id"];
    if (!isBundleHeaderField || ![self isTargetBundleIdentifier:value]) {
        return value;
    }
    return [self replacementBundleIdentifier:value];
}

+ (NSDictionary *)headersByReplacingBundleIdentifiers:(NSDictionary *)headers {
    if (![headers isKindOfClass:NSDictionary.class]) {
        return headers;
    }

    NSMutableDictionary *mutableHeaders = [headers mutableCopy];
    NSArray<NSString *> *headerKeys = @[ @"X-Bundle-ID", @"X-App-Bundle-ID", @"Bundle-Identifier", @"App-Bundle-ID" ];
    for (NSString *headerKey in headerKeys) {
        id value = mutableHeaders[headerKey];
        if ([self isTargetBundleIdentifier:value]) {
            mutableHeaders[headerKey] = [self replacementBundleIdentifier:value];
        }

        NSString *lowercaseKey = headerKey.lowercaseString;
        id lowercaseValue = mutableHeaders[lowercaseKey];
        if ([self isTargetBundleIdentifier:lowercaseValue]) {
            mutableHeaders[lowercaseKey] = [self replacementBundleIdentifier:lowercaseValue];
        }
    }
    return mutableHeaders;
}

+ (NSString *)stringByReplacingTargetBundleIdentifiers:(NSString *)value {
    if (![value isKindOfClass:NSString.class] || value.length == 0) {
        return value;
    }
    if (![self shouldApplyLoginNetworkCamouflage]) {
        return value;
    }

    NSString *updatedString = value;
    NSMutableArray<NSString *> *candidates = [NSMutableArray array];
    if ([self shouldApplyEmojiBundleSpoof]) {
        NSArray<NSString *> *officialIdentifiers = [self officialFamilyBundleIdentifiers];
        if (officialIdentifiers.count > 0) {
            [candidates addObjectsFromArray:officialIdentifiers];
        }
    }
    if ([self shouldMaintainCloneSessionIdentity]) {
        static NSRegularExpression *cloneRegex = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
          cloneRegex = [NSRegularExpression regularExpressionWithPattern:@"com\\.ss\\.iphone\\.ugc\\.Aweme\\d{4}"
                                                                 options:0
                                                                   error:nil];
        });
        NSArray<NSTextCheckingResult *> *cloneMatches =
            [cloneRegex matchesInString:value options:0 range:NSMakeRange(0, value.length)];
        for (NSTextCheckingResult *match in cloneMatches) {
            NSString *cloneIdentifier = [value substringWithRange:match.range];
            if (cloneIdentifier.length > 0 && ![candidates containsObject:cloneIdentifier]) {
                [candidates addObject:cloneIdentifier];
            }
        }
    }

    // 先替换更长的 clone / lite / beta，避免 `Aweme` 前缀把 `Aweme3760` 截断替换坏。
    [candidates sortUsingComparator:^NSComparisonResult(NSString *left, NSString *right) {
      if (left.length == right.length) {
          return [right compare:left];
      }
      return left.length < right.length ? NSOrderedDescending : NSOrderedAscending;
    }];

    for (NSString *candidate in candidates) {
        if (![updatedString containsString:candidate]) {
            continue;
        }
        updatedString = [updatedString stringByReplacingOccurrencesOfString:candidate
                                                                 withString:[self replacementBundleIdentifier:candidate]];
    }
    return updatedString;
}

+ (NSURL *)URLByReplacingTargetBundleIdentifiers:(NSURL *)url {
    if (![url isKindOfClass:NSURL.class]) {
        return url;
    }

    NSString *absoluteString = url.absoluteString;
    if (absoluteString.length == 0) {
        return url;
    }

    NSString *updatedString = [self stringByReplacingTargetBundleIdentifiers:absoluteString];
    if ([updatedString isEqualToString:absoluteString]) {
        return url;
    }
    return [NSURL URLWithString:updatedString] ?: url;
}

+ (BOOL)isLoginBypassEnabled {
    return atomic_load_explicit(&dyyyLoginBypassEnabled, memory_order_acquire);
}

#pragma mark - Toast / disable pipeline

+ (void)showToastOnMainQueue:(NSString *)text {
    if (text.length == 0) {
        return;
    }
    dispatch_block_t showBlock = ^{
      [DYYYUtils showToast:text];
    };
    if ([NSThread isMainThread]) {
        showBlock();
    } else {
        dispatch_async(dispatch_get_main_queue(), showBlock);
    }
}

+ (void)markDisablePipelineFinished {
    dyyyLoginBypassDisableInFlight = NO;
    dyyyLoginBypassLastHandledAt = CFAbsoluteTimeGetCurrent();
}

+ (BOOL)shouldStartDisablePipeline {
    if (![self isLoginBypassEnabled]) {
        return NO;
    }

    // 双通道几乎同时回调时只启动一轮；失败后允许再次登录重试。
    if (dyyyLoginBypassDisableInFlight || (CFAbsoluteTimeGetCurrent() - dyyyLoginBypassLastHandledAt) < 2.0) {
        return NO;
    }

    dyyyLoginBypassDisableInFlight = YES;
    dyyyLoginBypassPostLoginNetworkRestore = YES;
    NSLog(@"[DYYY][绕登录] 登录成功回调：将关闭版本门控开关；分身继续维持指纹抑制与官方包名");
    return YES;
}

+ (BOOL)disableIfOfficialLoginIsConfirmedWithUserID:(nullable NSString *)userID allowWeakMatch:(BOOL)allowWeakMatch {
    if (![self isLoginBypassEnabled]) {
        [self markDisablePipelineFinished];
        return YES;
    }

    NSString *resolvedUserID = userID.length > 0 ? userID : [self currentOfficialUserID];
    BOOL confirmed = NO;
    if (resolvedUserID.length > 0) {
        confirmed = [self officialUserServiceConfirmsLoginWithUserID:resolvedUserID];
    }
    if (!confirmed && allowWeakMatch) {
        confirmed = [self officialUserServiceConfirmsLoginWeakly];
        if (confirmed && resolvedUserID.length == 0) {
            resolvedUserID = [self currentOfficialUserID];
        }
    }
    if (!confirmed) {
        return NO;
    }

    [self persistLoginBypassEnabled:NO];
    NSLog(@"[DYYY][绕登录] 已通过官方账号服务确认登录(uid=%@)，自动关闭绕登录开关", resolvedUserID ?: @"unknown");
    [self showToastOnMainQueue:kDYYYLoginBypassDisabledToast];
    [self markDisablePipelineFinished];
    return YES;
}

+ (void)attemptDisableWithUserID:(nullable NSString *)userID retryIndex:(NSUInteger)retryIndex {
    static NSArray<NSNumber *> *retryDelays = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      retryDelays = @[ @0.2, @0.8, @2.0 ];
    });

    BOOL isLastAttempt = retryIndex >= retryDelays.count;
    if ([self disableIfOfficialLoginIsConfirmedWithUserID:userID allowWeakMatch:isLastAttempt]) {
        return;
    }

    if (isLastAttempt) {
        dyyyLoginBypassPostLoginNetworkRestore = NO;
        NSLog(@"[DYYY][绕登录] 登录态校验失败，请手动关闭绕登录开关");
        [self showToastOnMainQueue:kDYYYLoginBypassManualCloseToast];
        [self markDisablePipelineFinished];
        return;
    }

    NSTimeInterval delay = retryDelays[retryIndex].doubleValue;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      [self attemptDisableWithUserID:userID retryIndex:retryIndex + 1];
    });
}

+ (void)attemptReconcileWithRetryIndex:(NSUInteger)retryIndex {
    static NSArray<NSNumber *> *retryDelays = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      retryDelays = @[ @0.2, @0.8, @2.0 ];
    });

    DYYYOfficialAccountLoginState loginState = [self officialAccountLoginState];
    if (loginState == DYYYOfficialAccountLoginStateLoggedIn) {
        dyyyLoginBypassPostLoginNetworkRestore = YES;
        if ([self isLoginBypassEnabled]) {
            [self persistLoginBypassEnabled:NO];
            NSLog(@"[DYYY][绕登录] 启动对账：官方账号已登录，绕登录已关闭");
            [self showToastOnMainQueue:kDYYYLoginBypassDisabledToast];
        }
        return;
    }
    if (loginState == DYYYOfficialAccountLoginStateLoggedOut || retryIndex >= retryDelays.count) {
        if (loginState == DYYYOfficialAccountLoginStateLoggedOut) {
            dyyyLoginBypassPostLoginNetworkRestore = NO;
        }
        return;
    }

    NSTimeInterval delay = retryDelays[retryIndex].doubleValue;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      [self attemptReconcileWithRetryIndex:retryIndex + 1];
    });
}

+ (void)handleOfficialLoginCompletionWithUserID:(nullable id)userIDOrAccount {
    dyyyLoginBypassPostLoginNetworkRestore = YES;

    NSString *normalizedUserID = [self userIDFromLoginPayload:userIDOrAccount];
    if (normalizedUserID.length == 0) {
        normalizedUserID = [self currentOfficialUserID];
    }

    if (![self shouldStartDisablePipeline]) {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
      [self attemptDisableWithUserID:normalizedUserID retryIndex:0];
    });
}

+ (void)handleOfficialLogout {
    dyyyLoginBypassPostLoginNetworkRestore = NO;
    NSLog(@"[DYYY][绕登录] 已退出登录，结束分身会话身份");
}

@end
