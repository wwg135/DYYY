#import "DYYYExactInteractionCountHooks.h"

#import "DYYYConstants.h"
#import "DYYYRuntimeHookInstaller.h"
#import "AwemeHeaders.h"

#import <objc/message.h>
#import <objc/runtime.h>
#import <stdatomic.h>
#import <string.h>

static const char *const kDYYYObjectNumberEncodings[] = {"@24@0:8@16"};
static const char *const kDYYYVoidNoArgumentEncodings[] = {"v16@0:8"};
static const char *const kDYYYVoidObjectEncodings[] = {"v24@0:8@16"};

typedef id (*DYYYExactCountFormatterIMP)(id self, SEL _cmd, NSNumber *number);
typedef void (*DYYYLikeUpdateDiggCountIMP)(id self, SEL _cmd);
typedef void (*DYYYSetLabelStringIMP)(id self, SEL _cmd, NSString *labelString);

static DYYYExactCountFormatterIMP gDYYYOriginalCommentShowString;
static DYYYExactCountFormatterIMP gDYYYOriginalStandardCommentShowString;
static DYYYExactCountFormatterIMP gDYYYOriginalFavoriteShowString;
static DYYYExactCountFormatterIMP gDYYYOriginalShareShowString;
static DYYYLikeUpdateDiggCountIMP gDYYYOriginalLikeUpdateDiggCount;
static atomic_bool gDYYYExactInteractionCountHooksStarted = false;

static BOOL DYYYExactInteractionCountsEnabled(void) {
    return DYYYGetBool(DYYY_SHOW_EXACT_INTERACTION_COUNTS_KEY);
}

static NSString *DYYYExactInteractionIntegerString(NSNumber *rawValue) {
    if (![rawValue isKindOfClass:[NSNumber class]]) {
        return nil;
    }

    long long count = rawValue.longLongValue;
    if (count < 10000) {
        return nil;
    }
    return [NSString stringWithFormat:@"%lld", count];
}

static id DYYYExactCountFormatterResult(DYYYExactCountFormatterIMP original,
                                        id self,
                                        SEL _cmd,
                                        NSNumber *number) {
    id hostResult = original ? original(self, _cmd, number) : nil;
    if (!DYYYExactInteractionCountsEnabled()) {
        return hostResult;
    }

    NSString *exactString = DYYYExactInteractionIntegerString(number);
    return exactString ?: hostResult;
}

static id DYYYCommentShowStringFromNumber(id self, SEL _cmd, NSNumber *number) {
    return DYYYExactCountFormatterResult(gDYYYOriginalCommentShowString, self, _cmd, number);
}

static id DYYYStandardCommentShowStringFromNumber(id self, SEL _cmd, NSNumber *number) {
    return DYYYExactCountFormatterResult(gDYYYOriginalStandardCommentShowString, self, _cmd, number);
}

static id DYYYFavoriteShowStringFromNumber(id self, SEL _cmd, NSNumber *number) {
    return DYYYExactCountFormatterResult(gDYYYOriginalFavoriteShowString, self, _cmd, number);
}

static id DYYYShareShowStringFromNumber(id self, SEL _cmd, NSNumber *number) {
    return DYYYExactCountFormatterResult(gDYYYOriginalShareShowString, self, _cmd, number);
}

static AWEAwemeModel *DYYYLikeElementModel(id self) {
    if (!self || ![self respondsToSelector:@selector(model)]) {
        return nil;
    }
    return ((AWEAwemeModel *(*)(id, SEL))objc_msgSend)(self, @selector(model));
}

static AWEFeedVideoButton *DYYYLikeElementButton(id self) {
    if (!self) {
        return nil;
    }

    AWEFeedVideoButton *button = nil;
    if ([self respondsToSelector:@selector(likeButton)]) {
        button = ((AWEFeedVideoButton *(*)(id, SEL))objc_msgSend)(self, @selector(likeButton));
    }
    if (!button && [self respondsToSelector:@selector(button)]) {
        button = ((AWEFeedVideoButton *(*)(id, SEL))objc_msgSend)(self, @selector(button));
    }
    return button;
}

static void DYYYLikeUpdateDiggCount(id self, SEL _cmd) {
    if (gDYYYOriginalLikeUpdateDiggCount) {
        gDYYYOriginalLikeUpdateDiggCount(self, _cmd);
    }
    if (!DYYYExactInteractionCountsEnabled()) {
        return;
    }

    AWEAwemeModel *model = DYYYLikeElementModel(self);
    NSNumber *diggCount = model.statistics.diggCount;
    NSString *exactString = DYYYExactInteractionIntegerString(diggCount);
    if (exactString.length == 0) {
        return;
    }

    AWEFeedVideoButton *button = DYYYLikeElementButton(self);
    if (!button || ![button respondsToSelector:@selector(setLabelString:)]) {
        return;
    }

    Method setter = class_getInstanceMethod([button class], @selector(setLabelString:));
    const char *setterEncoding = setter ? method_getTypeEncoding(setter) : NULL;
    if (!setterEncoding || strcmp(setterEncoding, kDYYYVoidObjectEncodings[0]) != 0) {
        return;
    }

    ((DYYYSetLabelStringIMP)objc_msgSend)(button, @selector(setLabelString:), exactString);
}

static void DYYYInstallExactInteractionHook(const char *identifier,
                                             NSString *className,
                                             SEL selector,
                                             IMP replacement,
                                             IMP *original,
                                             const char *const *allowedEncodings,
                                             NSUInteger allowedEncodingCount) {
    Class targetClass = objc_lookUpClass(className.UTF8String);
    DYYYRuntimeHookInstallResult result = DYYYInstallRuntimeHook((DYYYRuntimeHookRequest){
        .identifier = identifier,
        .targetClass = targetClass,
        .selector = selector,
        .classMethod = NO,
        .replacement = replacement,
        .allowedTypeEncodings = allowedEncodings,
        .allowedTypeEncodingCount = allowedEncodingCount,
        .originalImplementation = original,
    });

    if (result.status != DYYYRuntimeHookInstallStatusInstalled &&
        result.status != DYYYRuntimeHookInstallStatusAlreadyInstalled) {
        NSLog(@"[DYYY][RuntimeHook][ExactInteractionCounts] skip=%s class=%@ selector=%@ status=%@ encoding=%s",
              identifier,
              className,
              NSStringFromSelector(selector),
              DYYYRuntimeHookInstallStatusName(result.status),
              result.actualTypeEncoding ?: "(null)");
    }
}

void DYYYStartExactInteractionCountHooks(void) {
    bool expected = false;
    if (!atomic_compare_exchange_strong_explicit(&gDYYYExactInteractionCountHooksStarted,
                                                  &expected,
                                                  true,
                                                  memory_order_acq_rel,
                                                  memory_order_acquire)) {
        return;
    }

    SEL formatterSelector = @selector(showStringFromNumber:);
    DYYYInstallExactInteractionHook("interaction-counts.comment",
                                    @"AWEPlayInteractionCommentElement",
                                    formatterSelector,
                                    (IMP)DYYYCommentShowStringFromNumber,
                                    (IMP *)&gDYYYOriginalCommentShowString,
                                    kDYYYObjectNumberEncodings,
                                    sizeof(kDYYYObjectNumberEncodings) / sizeof(kDYYYObjectNumberEncodings[0]));
    DYYYInstallExactInteractionHook("interaction-counts.standard-comment",
                                    @"AWEPlayInteractionStandardCommentElement",
                                    formatterSelector,
                                    (IMP)DYYYStandardCommentShowStringFromNumber,
                                    (IMP *)&gDYYYOriginalStandardCommentShowString,
                                    kDYYYObjectNumberEncodings,
                                    sizeof(kDYYYObjectNumberEncodings) / sizeof(kDYYYObjectNumberEncodings[0]));
    DYYYInstallExactInteractionHook("interaction-counts.favorite",
                                    @"AWEPlayInteractionFavoriteElement",
                                    formatterSelector,
                                    (IMP)DYYYFavoriteShowStringFromNumber,
                                    (IMP *)&gDYYYOriginalFavoriteShowString,
                                    kDYYYObjectNumberEncodings,
                                    sizeof(kDYYYObjectNumberEncodings) / sizeof(kDYYYObjectNumberEncodings[0]));
    DYYYInstallExactInteractionHook("interaction-counts.share",
                                    @"AWEPlayInteractionShareElement",
                                    formatterSelector,
                                    (IMP)DYYYShareShowStringFromNumber,
                                    (IMP *)&gDYYYOriginalShareShowString,
                                    kDYYYObjectNumberEncodings,
                                    sizeof(kDYYYObjectNumberEncodings) / sizeof(kDYYYObjectNumberEncodings[0]));
    DYYYInstallExactInteractionHook("interaction-counts.like-update",
                                    @"AWEPlayInteractionLikeViewSubElement",
                                    @selector(updateDiggCount),
                                    (IMP)DYYYLikeUpdateDiggCount,
                                    (IMP *)&gDYYYOriginalLikeUpdateDiggCount,
                                    kDYYYVoidNoArgumentEncodings,
                                    sizeof(kDYYYVoidNoArgumentEncodings) / sizeof(kDYYYVoidNoArgumentEncodings[0]));
}
