#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface DYYYLoginBypassManager : NSObject

/// 首次注入时按官方登录态写入默认开关；未登录默认开，已登录默认关。
+ (void)configureInitialStateIfNeeded;

/// 运行时门控：含首次配置 pending 时对已登录态的即时抑制，避免短暂误开。
+ (BOOL)isLoginBypassEnabled;

/// 多开副本在绕登录或登录会话内映射为精确官方 `com.ss.iphone.ugc.Aweme`；emoji 只用于未登录绕过期间的官方/Lite。
+ (NSString *)replacementBundleIdentifier:(NSString *)bundleIdentifier;

/// GF/Dtrait 抑制：官方包仅未登录绕过期间为 YES；数字分身在绕登录或登录会话内保持 YES，直到退出登录。
+ (BOOL)shouldApplyLoginNetworkCamouflage;

+ (nullable NSString *)headerValueByReplacingBundleIdentifier:(nullable NSString *)value field:(nullable NSString *)field;
+ (nullable NSDictionary *)headersByReplacingBundleIdentifiers:(nullable NSDictionary *)headers;
+ (nullable NSString *)stringByReplacingTargetBundleIdentifiers:(nullable NSString *)value;
+ (nullable NSURL *)URLByReplacingTargetBundleIdentifiers:(nullable NSURL *)url;

/// 官方登录完成双通道入口（AWEUserServiceListener / TTAccountMulticast）。
+ (void)handleOfficialLoginCompletionWithUserID:(nullable id)userIDOrAccount;

/// 退出登录后结束分身会话身份，并恢复下一次绕登录的伪装资格。
+ (void)handleOfficialLogout;

@end

NS_ASSUME_NONNULL_END
