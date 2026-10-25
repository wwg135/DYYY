#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 安装绕登录的 GF/Dtrait 前置链与 TTNetwork 内部 URL 改写。
/// 由主 `%ctor` 调用；官方包在绕登录关闭后透传原 IMP，数字分身在登录会话内继续抑制指纹。
FOUNDATION_EXPORT void DYYYLoginRepairInstallHooks(void);

NS_ASSUME_NONNULL_END
