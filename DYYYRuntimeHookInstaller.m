#import "DYYYRuntimeHookInstaller.h"

#import <os/lock.h>

static os_unfair_lock gDYYYRuntimeHookRegistryLock = OS_UNFAIR_LOCK_INIT;
static NSMutableDictionary<NSString *, NSDictionary<NSString *, NSValue *> *> *gDYYYRuntimeHookRegistry;

static BOOL DYYYClassOwnsSelector(Class cls, SEL selector) {
    unsigned int methodCount = 0;
    Method *methods = class_copyMethodList(cls, &methodCount);
    BOOL ownsSelector = NO;
    for (unsigned int index = 0; index < methodCount; index++) {
        if (method_getName(methods[index]) == selector) {
            ownsSelector = YES;
            break;
        }
    }
    free(methods);
    return ownsSelector;
}

static BOOL DYYYTypeEncodingAllowed(const char *actualEncoding,
                                    const char *const *allowedEncodings,
                                    NSUInteger allowedEncodingCount) {
    if (!actualEncoding || !allowedEncodings || allowedEncodingCount == 0) {
        return NO;
    }
    for (NSUInteger index = 0; index < allowedEncodingCount; index++) {
        const char *candidate = allowedEncodings[index];
        if (candidate && strcmp(actualEncoding, candidate) == 0) {
            return YES;
        }
    }
    return NO;
}

static NSString *DYYYRuntimeHookRegistryKey(DYYYRuntimeHookRequest request) {
    return [NSString stringWithFormat:@"%s|%@|%@",
                                      class_getName(request.targetClass) ?: "<missing>",
                                      request.classMethod ? @"+" : @"-",
                                      NSStringFromSelector(request.selector)];
}

DYYYRuntimeHookInstallResult DYYYInstallRuntimeHook(DYYYRuntimeHookRequest request) {
    DYYYRuntimeHookInstallResult result = {
        .status = DYYYRuntimeHookInstallStatusTargetClassMissing,
        .previousImplementation = NULL,
        .actualTypeEncoding = NULL,
        .methodWasInherited = NO,
    };
    if (!request.targetClass) {
        return result;
    }
    if (!request.replacement) {
        result.status = DYYYRuntimeHookInstallStatusReplacementMissing;
        return result;
    }

    Class installationClass = request.classMethod ? object_getClass(request.targetClass) : request.targetClass;
    Method method = class_getInstanceMethod(installationClass, request.selector);
    if (!method) {
        result.status = DYYYRuntimeHookInstallStatusTargetMethodMissing;
        return result;
    }

    const char *typeEncoding = method_getTypeEncoding(method);
    result.actualTypeEncoding = typeEncoding;
    if (!DYYYTypeEncodingAllowed(typeEncoding, request.allowedTypeEncodings, request.allowedTypeEncodingCount)) {
        result.status = DYYYRuntimeHookInstallStatusTypeEncodingMismatch;
        return result;
    }

    IMP currentImplementation = method_getImplementation(method);
    NSString *registryKey = DYYYRuntimeHookRegistryKey(request);
    os_unfair_lock_lock(&gDYYYRuntimeHookRegistryLock);
    if (!gDYYYRuntimeHookRegistry) {
        gDYYYRuntimeHookRegistry = [NSMutableDictionary dictionary];
    }
    NSDictionary<NSString *, NSValue *> *existing = gDYYYRuntimeHookRegistry[registryKey];
    if (existing) {
        IMP installedReplacement = [existing[@"replacement"] pointerValue];
        IMP previousImplementation = [existing[@"previous"] pointerValue];
        result.previousImplementation = previousImplementation;
        if (installedReplacement == request.replacement) {
            if (request.originalImplementation) {
                *request.originalImplementation = previousImplementation;
            }
            result.status = DYYYRuntimeHookInstallStatusAlreadyInstalled;
        } else {
            result.status = DYYYRuntimeHookInstallStatusConflict;
        }
        os_unfair_lock_unlock(&gDYYYRuntimeHookRegistryLock);
        return result;
    }
    if (currentImplementation == request.replacement) {
        result.status = DYYYRuntimeHookInstallStatusReplacementSelfReference;
        os_unfair_lock_unlock(&gDYYYRuntimeHookRegistryLock);
        return result;
    }

    BOOL ownsSelector = DYYYClassOwnsSelector(installationClass, request.selector);
    result.methodWasInherited = !ownsSelector;
    BOOL installed = NO;
    if (!ownsSelector) {
        installed = class_addMethod(installationClass, request.selector, request.replacement, typeEncoding);
    } else {
        method_setImplementation(method, request.replacement);
        installed = YES;
    }
    if (!installed) {
        result.status = DYYYRuntimeHookInstallStatusConflict;
        os_unfair_lock_unlock(&gDYYYRuntimeHookRegistryLock);
        return result;
    }

    result.previousImplementation = currentImplementation;
    if (request.originalImplementation) {
        *request.originalImplementation = currentImplementation;
    }
    gDYYYRuntimeHookRegistry[registryKey] = @{
        @"replacement" : [NSValue valueWithPointer:request.replacement],
        @"previous" : [NSValue valueWithPointer:currentImplementation],
    };
    result.status = DYYYRuntimeHookInstallStatusInstalled;
    os_unfair_lock_unlock(&gDYYYRuntimeHookRegistryLock);
    return result;
}

NSString *DYYYRuntimeHookInstallStatusName(DYYYRuntimeHookInstallStatus status) {
    switch (status) {
        case DYYYRuntimeHookInstallStatusInstalled: return @"installed";
        case DYYYRuntimeHookInstallStatusAlreadyInstalled: return @"already-installed";
        case DYYYRuntimeHookInstallStatusTargetClassMissing: return @"class-missing";
        case DYYYRuntimeHookInstallStatusTargetMethodMissing: return @"method-missing";
        case DYYYRuntimeHookInstallStatusTypeEncodingMismatch: return @"encoding-mismatch";
        case DYYYRuntimeHookInstallStatusReplacementMissing: return @"replacement-missing";
        case DYYYRuntimeHookInstallStatusReplacementSelfReference: return @"replacement-self-reference";
        case DYYYRuntimeHookInstallStatusConflict: return @"conflict";
    }
    return @"unknown";
}
