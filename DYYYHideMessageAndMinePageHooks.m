#import "DYYYHideMessageAndMinePageHooks.h"

#import "AwemeHeaders.h"

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <stdatomic.h>

static NSString *const kDYYYHideMessageTabStarMallKey = @"DYYYHideMessageTabStarMall";
static NSString *const kDYYYHideMineAvatarPlusKey = @"DYYYHideMineAvatarPlus";
static NSString *const kDYYYHideMineAICreationKey = @"DYYYHideMineAICreation";

typedef BOOL (*DYYYBoolIMP)(id, SEL);
typedef BOOL (*DYYYBoolContextIMP)(id, SEL, id);
typedef CGSize (*DYYYSizeIMP)(id, SEL);
typedef void (*DYYYVoidUpdateUIIMP)(id, SEL, UIView *, UIView *);
typedef void (*DYYYVoidLayoutIMP)(id, SEL);
typedef id (*DYYYIdDataIMP)(id, SEL, id);
typedef void (*DYYYVoidDataIMP)(id, SEL, id);

static atomic_bool gDYYYHideMessageAndMinePageHooksStarted = false;

static DYYYBoolIMP gOrigMessageTabResourceSlotCanShow = NULL;
static DYYYBoolIMP gOrigMessageTabResourceSlotV2CanShow = NULL;
static DYYYBoolIMP gOrigProfileStoryPublishCanShow = NULL;
static DYYYIdDataIMP gOrigGenericOperationBuildVirtualView = NULL;
static DYYYVoidDataIMP gOrigGenericOperationUpdateComponentData = NULL;
static DYYYVoidUpdateUIIMP gOrigProfileStoryPublishUpdateUI = NULL;

static BOOL DYYYHideMessageTabStarMallEnabled(void) {
    return DYYYGetBool(kDYYYHideMessageTabStarMallKey);
}

static BOOL DYYYHideMineAvatarPlusEnabled(void) {
    return DYYYGetBool(kDYYYHideMineAvatarPlusKey);
}

static BOOL DYYYHideMineAICreationEnabled(void) {
    return DYYYGetBool(kDYYYHideMineAICreationKey);
}

static void DYYYHideChromeView(UIView *view) {
    if (![view isKindOfClass:[UIView class]]) {
        return;
    }
    view.hidden = YES;
    view.alpha = 0.0;
    view.userInteractionEnabled = NO;
    view.accessibilityElementsHidden = YES;
}

static void DYYYHideProfileStoryPublishButton(id owner) {
    if (!owner) {
        return;
    }
    UIButton *publishButton = nil;
    @try {
        id value = [owner valueForKey:@"story25PublishButton"];
        if ([value isKindOfClass:[UIButton class]]) {
            publishButton = value;
        }
    } @catch (__unused NSException *exception) {
    }
    if (publishButton) {
        DYYYHideChromeView(publishButton);
    }
}

static void DYYYHideGenericOperationComponentChrome(id owner) {
    if (!owner) {
        return;
    }
    @try {
        id containerNode = [owner valueForKey:@"containerNode"];
        if ([containerNode isKindOfClass:[UIView class]]) {
            DYYYHideChromeView((UIView *)containerNode);
        } else if (containerNode && [containerNode respondsToSelector:@selector(setHidden:)]) {
            [containerNode setValue:@YES forKey:@"hidden"];
        }
    } @catch (__unused NSException *exception) {
    }
}

#pragma mark - Replacements

static BOOL DYYYMessageTabResourceSlotCanShowInNaviBar(id self, SEL _cmd) {
    if (DYYYHideMessageTabStarMallEnabled()) {
        return NO;
    }
    if (gOrigMessageTabResourceSlotCanShow) {
        return gOrigMessageTabResourceSlotCanShow(self, _cmd);
    }
    return YES;
}

static BOOL DYYYMessageTabResourceSlotV2CanShowInNaviBar(id self, SEL _cmd) {
    if (DYYYHideMessageTabStarMallEnabled()) {
        return NO;
    }
    if (gOrigMessageTabResourceSlotV2CanShow) {
        return gOrigMessageTabResourceSlotV2CanShow(self, _cmd);
    }
    return YES;
}

static BOOL DYYYProfileStoryPublishCanShow(id self, SEL _cmd) {
    if (DYYYHideMineAvatarPlusEnabled()) {
        return NO;
    }
    if (gOrigProfileStoryPublishCanShow) {
        return gOrigProfileStoryPublishCanShow(self, _cmd);
    }
    return YES;
}

static void DYYYProfileStoryPublishUpdateUI(id self, SEL _cmd, UIView *containerView, UIView *anchorView) {
    if (gOrigProfileStoryPublishUpdateUI) {
        gOrigProfileStoryPublishUpdateUI(self, _cmd, containerView, anchorView);
    }
    if (DYYYHideMineAvatarPlusEnabled()) {
        DYYYHideProfileStoryPublishButton(self);
    }
}

static id DYYYGenericOperationBuildVirtualView(id self, SEL _cmd, id data) {
    if (DYYYHideMineAICreationEnabled()) {
        return nil;
    }
    if (gOrigGenericOperationBuildVirtualView) {
        return gOrigGenericOperationBuildVirtualView(self, _cmd, data);
    }
    return nil;
}

static void DYYYGenericOperationUpdateComponentData(id self, SEL _cmd, id data) {
    if (gOrigGenericOperationUpdateComponentData) {
        gOrigGenericOperationUpdateComponentData(self, _cmd, data);
    }
    if (DYYYHideMineAICreationEnabled()) {
        DYYYHideGenericOperationComponentChrome(self);
    }
}

#pragma mark - Install

static BOOL DYYYInstallInstanceBOOLHook(Class cls,
                                         SEL selector,
                                         IMP replacement,
                                         DYYYBoolIMP *originalSlot,
                                         BOOL required,
                                         const char *logLabel) {
    if (!cls || !replacement || !originalSlot) {
        return NO;
    }

    Method existing = class_getInstanceMethod(cls, selector);
    if (!existing) {
        if (required) {
            NSLog(@"[DYYY][RuntimeHook][HideMessageAndMinePage] %@ 缺少 %@：%@",
                  logLabel,
                  NSStringFromSelector(selector),
                  NSStringFromClass(cls));
        }
        return NO;
    }

    const char *typeEncoding = method_getTypeEncoding(existing);
    IMP existingIMP = method_getImplementation(existing);
    if (existingIMP == replacement) {
        return *originalSlot != NULL;
    }

    BOOL methodDefinedOnClass = NO;
    unsigned int methodCount = 0;
    Method *methods = class_copyMethodList(cls, &methodCount);
    for (unsigned int i = 0; i < methodCount; i++) {
        if (method_getName(methods[i]) == selector) {
            methodDefinedOnClass = YES;
            break;
        }
    }
    free(methods);

    if (!methodDefinedOnClass) {
        IMP superIMP = existingIMP;
        if (!class_addMethod(cls, selector, replacement, typeEncoding)) {
            if (required) {
                NSLog(@"[DYYY][RuntimeHook][HideMessageAndMinePage] %@ class_addMethod 失败：%@",
                      logLabel,
                      NSStringFromClass(cls));
            }
            return NO;
        }
        *originalSlot = (DYYYBoolIMP)superIMP;
        return YES;
    }

    IMP previous = method_setImplementation(existing, replacement);
    if (!previous || previous == replacement) {
        NSLog(@"[DYYY][RuntimeHook][HideMessageAndMinePage] %@ 无法保存原 IMP：%@",
              logLabel,
              NSStringFromClass(cls));
        return NO;
    }
    *originalSlot = (DYYYBoolIMP)previous;
    return YES;
}

static BOOL DYYYInstallClassBOOLHook(Class cls,
                                     SEL selector,
                                     IMP replacement,
                                     DYYYBoolContextIMP *originalSlot,
                                     BOOL required,
                                     const char *logLabel) {
    if (!cls || !replacement || !originalSlot) {
        return NO;
    }

    Method existing = class_getClassMethod(cls, selector);
    if (!existing) {
        if (required) {
            NSLog(@"[DYYY][RuntimeHook][HideMessageAndMinePage] %@ 缺少类方法 %@：%@",
                  logLabel,
                  NSStringFromSelector(selector),
                  NSStringFromClass(cls));
        }
        return NO;
    }

    const char *typeEncoding = method_getTypeEncoding(existing);
    IMP existingIMP = method_getImplementation(existing);
    if (existingIMP == replacement) {
        return *originalSlot != NULL;
    }

    IMP previous = method_setImplementation(existing, replacement);
    if (!previous || previous == replacement) {
        NSLog(@"[DYYY][RuntimeHook][HideMessageAndMinePage] %@ 无法保存原类方法 IMP：%@",
              logLabel,
              NSStringFromClass(cls));
        return NO;
    }
    *originalSlot = (DYYYBoolContextIMP)previous;
    return YES;
}

static BOOL DYYYInstallInstanceSizeHook(Class cls,
                                          SEL selector,
                                          IMP replacement,
                                          DYYYSizeIMP *originalSlot,
                                          BOOL required,
                                          const char *logLabel) {
    if (!cls || !replacement || !originalSlot) {
        return NO;
    }

    Method existing = class_getInstanceMethod(cls, selector);
    if (!existing) {
        if (required) {
            NSLog(@"[DYYY][RuntimeHook][HideMessageAndMinePage] %@ 缺少 %@：%@",
                  logLabel,
                  NSStringFromSelector(selector),
                  NSStringFromClass(cls));
        }
        return NO;
    }

    const char *typeEncoding = method_getTypeEncoding(existing);
    IMP existingIMP = method_getImplementation(existing);
    if (existingIMP == replacement) {
        return *originalSlot != NULL;
    }

    BOOL methodDefinedOnClass = NO;
    unsigned int methodCount = 0;
    Method *methods = class_copyMethodList(cls, &methodCount);
    for (unsigned int i = 0; i < methodCount; i++) {
        if (method_getName(methods[i]) == selector) {
            methodDefinedOnClass = YES;
            break;
        }
    }
    free(methods);

    if (!methodDefinedOnClass) {
        IMP superIMP = existingIMP;
        if (!class_addMethod(cls, selector, replacement, typeEncoding)) {
            if (required) {
                NSLog(@"[DYYY][RuntimeHook][HideMessageAndMinePage] %@ class_addMethod 失败：%@",
                      logLabel,
                      NSStringFromClass(cls));
            }
            return NO;
        }
        *originalSlot = (DYYYSizeIMP)superIMP;
        return YES;
    }

    IMP previous = method_setImplementation(existing, replacement);
    if (!previous || previous == replacement) {
        NSLog(@"[DYYY][RuntimeHook][HideMessageAndMinePage] %@ 无法保存原 IMP：%@",
              logLabel,
              NSStringFromClass(cls));
        return NO;
    }
    *originalSlot = (DYYYSizeIMP)previous;
    return YES;
}

static BOOL DYYYInstallInstanceVoidUpdateUIHook(Class cls,
                                                SEL selector,
                                                IMP replacement,
                                                DYYYVoidUpdateUIIMP *originalSlot,
                                                BOOL required,
                                                const char *logLabel) {
    if (!cls || !replacement || !originalSlot) {
        return NO;
    }

    Method existing = class_getInstanceMethod(cls, selector);
    if (!existing) {
        if (required) {
            NSLog(@"[DYYY][RuntimeHook][HideMessageAndMinePage] %@ 缺少 %@：%@",
                  logLabel,
                  NSStringFromSelector(selector),
                  NSStringFromClass(cls));
        }
        return NO;
    }

    const char *typeEncoding = method_getTypeEncoding(existing);
    IMP existingIMP = method_getImplementation(existing);
    if (existingIMP == replacement) {
        return *originalSlot != NULL;
    }

    BOOL methodDefinedOnClass = NO;
    unsigned int methodCount = 0;
    Method *methods = class_copyMethodList(cls, &methodCount);
    for (unsigned int i = 0; i < methodCount; i++) {
        if (method_getName(methods[i]) == selector) {
            methodDefinedOnClass = YES;
            break;
        }
    }
    free(methods);

    if (!methodDefinedOnClass) {
        IMP superIMP = existingIMP;
        if (!class_addMethod(cls, selector, replacement, typeEncoding)) {
            if (required) {
                NSLog(@"[DYYY][RuntimeHook][HideMessageAndMinePage] %@ class_addMethod 失败：%@",
                      logLabel,
                      NSStringFromClass(cls));
            }
            return NO;
        }
        *originalSlot = (DYYYVoidUpdateUIIMP)superIMP;
        return YES;
    }

    IMP previous = method_setImplementation(existing, replacement);
    if (!previous || previous == replacement) {
        NSLog(@"[DYYY][RuntimeHook][HideMessageAndMinePage] %@ 无法保存原 IMP：%@",
              logLabel,
              NSStringFromClass(cls));
        return NO;
    }
    *originalSlot = (DYYYVoidUpdateUIIMP)previous;
    return YES;
}

static BOOL DYYYInstallInstanceIMPHook(Class cls,
                                       SEL selector,
                                       IMP replacement,
                                       IMP *originalSlot,
                                       BOOL required,
                                       const char *logLabel) {
    if (!cls || !replacement || !originalSlot) {
        return NO;
    }

    Method existing = class_getInstanceMethod(cls, selector);
    if (!existing) {
        if (required) {
            NSLog(@"[DYYY][RuntimeHook][HideMessageAndMinePage] %@ 缺少 %@：%@",
                  logLabel,
                  NSStringFromSelector(selector),
                  NSStringFromClass(cls));
        }
        return NO;
    }

    const char *typeEncoding = method_getTypeEncoding(existing);
    IMP existingIMP = method_getImplementation(existing);
    if (existingIMP == replacement) {
        return *originalSlot != NULL;
    }

    BOOL methodDefinedOnClass = NO;
    unsigned int methodCount = 0;
    Method *methods = class_copyMethodList(cls, &methodCount);
    for (unsigned int i = 0; i < methodCount; i++) {
        if (method_getName(methods[i]) == selector) {
            methodDefinedOnClass = YES;
            break;
        }
    }
    free(methods);

    if (!methodDefinedOnClass) {
        IMP superIMP = existingIMP;
        if (!class_addMethod(cls, selector, replacement, typeEncoding)) {
            if (required) {
                NSLog(@"[DYYY][RuntimeHook][HideMessageAndMinePage] %@ class_addMethod 失败：%@",
                      logLabel,
                      NSStringFromClass(cls));
            }
            return NO;
        }
        *originalSlot = superIMP;
        return YES;
    }

    IMP previous = method_setImplementation(existing, replacement);
    if (!previous || previous == replacement) {
        NSLog(@"[DYYY][RuntimeHook][HideMessageAndMinePage] %@ 无法保存原 IMP：%@",
              logLabel,
              NSStringFromClass(cls));
        return NO;
    }
    *originalSlot = previous;
    return YES;
}

static BOOL DYYYInstallLayoutSubviewsHook(Class cls,
                                          DYYYVoidLayoutIMP replacement,
                                          DYYYVoidLayoutIMP *originalSlot,
                                          BOOL required,
                                          const char *logLabel) {
    if (!cls || !replacement || !originalSlot) {
        return NO;
    }

    SEL selector = @selector(layoutSubviews);
    Method existing = class_getInstanceMethod(cls, selector);
    if (!existing) {
        if (required) {
            NSLog(@"[DYYY][RuntimeHook][HideMessageAndMinePage] %@ 缺少 layoutSubviews：%@",
                  logLabel,
                  NSStringFromClass(cls));
        }
        return NO;
    }

    const char *typeEncoding = method_getTypeEncoding(existing);
    IMP existingIMP = method_getImplementation(existing);
    if (existingIMP == (IMP)replacement) {
        return *originalSlot != NULL;
    }

    BOOL methodDefinedOnClass = NO;
    unsigned int methodCount = 0;
    Method *methods = class_copyMethodList(cls, &methodCount);
    for (unsigned int i = 0; i < methodCount; i++) {
        if (method_getName(methods[i]) == selector) {
            methodDefinedOnClass = YES;
            break;
        }
    }
    free(methods);

    if (!methodDefinedOnClass) {
        IMP superIMP = existingIMP;
        if (!class_addMethod(cls, selector, (IMP)replacement, typeEncoding)) {
            if (required) {
                NSLog(@"[DYYY][RuntimeHook][HideMessageAndMinePage] %@ class_addMethod 失败：%@",
                      logLabel,
                      NSStringFromClass(cls));
            }
            return NO;
        }
        *originalSlot = (DYYYVoidLayoutIMP)superIMP;
        return YES;
    }

    IMP previous = method_setImplementation(existing, (IMP)replacement);
    if (!previous || previous == (IMP)replacement) {
        NSLog(@"[DYYY][RuntimeHook][HideMessageAndMinePage] %@ 无法保存原 IMP：%@",
              logLabel,
              NSStringFromClass(cls));
        return NO;
    }
    *originalSlot = (DYYYVoidLayoutIMP)previous;
    return YES;
}

void DYYYStartHideMessageAndMinePageHooks(void) {
    bool expected = false;
    if (!atomic_compare_exchange_strong(&gDYYYHideMessageAndMinePageHooksStarted, &expected, true)) {
        return;
    }

    NSUInteger installed = 0;

    Class resourceSlotClass = objc_getClass("AWEIMMessageTabNavBarResourceSlotComponent");
    if (resourceSlotClass &&
        DYYYInstallInstanceBOOLHook(resourceSlotClass,
                                    @selector(canShowInNaviBar),
                                    (IMP)DYYYMessageTabResourceSlotCanShowInNaviBar,
                                    &gOrigMessageTabResourceSlotCanShow,
                                    NO,
                                    "MessageTabStarMall")) {
        installed += 1;
    }

    Class resourceSlotV2Class = objc_getClass("AWEIMMessageTabNavBarResourceSlotComponentV2");
    if (resourceSlotV2Class &&
        DYYYInstallInstanceBOOLHook(resourceSlotV2Class,
                                    @selector(canShowInNaviBar),
                                    (IMP)DYYYMessageTabResourceSlotV2CanShowInNaviBar,
                                    &gOrigMessageTabResourceSlotV2CanShow,
                                    YES,
                                    "MessageTabStarMall")) {
        installed += 1;
    }

    Class storyPublishClass = objc_getClass("AWEProfileAvatarStoryPublishController");
    if (storyPublishClass) {
        if (DYYYInstallInstanceBOOLHook(storyPublishClass,
                                        @selector(canShow),
                                        (IMP)DYYYProfileStoryPublishCanShow,
                                        &gOrigProfileStoryPublishCanShow,
                                        YES,
                                        "MineAvatarPlus")) {
            installed += 1;
        }
        if (DYYYInstallInstanceVoidUpdateUIHook(storyPublishClass,
                                                @selector(updateUIWithContainerView:anchorView:),
                                                (IMP)DYYYProfileStoryPublishUpdateUI,
                                                &gOrigProfileStoryPublishUpdateUI,
                                                NO,
                                                "MineAvatarPlus")) {
            installed += 1;
        }
    }

    Class genericOperationClass = objc_getClass("AWEProfileHeaderGenericOperationComponent");
    if (genericOperationClass) {
        if (DYYYInstallInstanceIMPHook(genericOperationClass,
                                       @selector(buildVirtualView:),
                                       (IMP)DYYYGenericOperationBuildVirtualView,
                                       (IMP *)&gOrigGenericOperationBuildVirtualView,
                                       YES,
                                       "MineAICreation")) {
            installed += 1;
        }
        if (DYYYInstallInstanceIMPHook(genericOperationClass,
                                       @selector(updateComponentData:),
                                       (IMP)DYYYGenericOperationUpdateComponentData,
                                       (IMP *)&gOrigGenericOperationUpdateComponentData,
                                       NO,
                                       "MineAICreation")) {
            installed += 1;
        }
    }

    NSLog(@"[DYYY][RuntimeHook][HideMessageAndMinePage] 安装完成，成功 %lu 个目标", (unsigned long)installed);
}
