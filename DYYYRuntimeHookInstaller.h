#import <Foundation/Foundation.h>
#import <objc/runtime.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, DYYYRuntimeHookInstallStatus) {
    DYYYRuntimeHookInstallStatusInstalled,
    DYYYRuntimeHookInstallStatusAlreadyInstalled,
    DYYYRuntimeHookInstallStatusTargetClassMissing,
    DYYYRuntimeHookInstallStatusTargetMethodMissing,
    DYYYRuntimeHookInstallStatusTypeEncodingMismatch,
    DYYYRuntimeHookInstallStatusReplacementMissing,
    DYYYRuntimeHookInstallStatusReplacementSelfReference,
    DYYYRuntimeHookInstallStatusConflict,
};

typedef struct {
    const char *identifier;
    Class targetClass;
    SEL selector;
    BOOL classMethod;
    IMP replacement;
    const char *_Nonnull const *_Nullable allowedTypeEncodings;
    NSUInteger allowedTypeEncodingCount;
    IMP _Nullable *_Nullable originalImplementation;
} DYYYRuntimeHookRequest;

typedef struct {
    DYYYRuntimeHookInstallStatus status;
    IMP _Nullable previousImplementation;
    const char *_Nullable actualTypeEncoding;
    BOOL methodWasInherited;
} DYYYRuntimeHookInstallResult;

FOUNDATION_EXPORT DYYYRuntimeHookInstallResult DYYYInstallRuntimeHook(DYYYRuntimeHookRequest request);
FOUNDATION_EXPORT NSString *DYYYRuntimeHookInstallStatusName(DYYYRuntimeHookInstallStatus status);

NS_ASSUME_NONNULL_END
