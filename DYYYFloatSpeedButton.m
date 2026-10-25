#import "AwemeHeaders.h"
#import "DYYYConstants.h"
#import "DYYYFloatClearButton.h"
#import "DYYYFloatSpeedButton.h"
#import "DYYYUtils.h"
#import <UIKit/UIKit.h>
#import <float.h>
#import <math.h>
#import <objc/runtime.h>

@class AWEFeedCellViewController;

FloatingSpeedButton *speedButton = nil;
BOOL showSpeedX = NO;
CGFloat speedButtonSize = 32.0;
BOOL isFloatSpeedButtonEnabled = NO;
static NSString *const kDYYYDefaultSpeedSettingsString = @"0.75,1.0,1.25,1.5,2.0,2.5,3.0";

static NSString *DYYYFormatSpeedOption(double speed) {
    NSString *speedString = [NSString stringWithFormat:@"%.2f", speed];
    while ([speedString containsString:@"."] && [speedString hasSuffix:@"0"]) {
        speedString = [speedString substringToIndex:speedString.length - 1];
    }
    if ([speedString hasSuffix:@"."]) {
        speedString = [speedString substringToIndex:speedString.length - 1];
    }
    return speedString;
}

static BOOL DYYYSpeedValuesMatch(double lhs, double rhs) {
    return fabs(lhs - rhs) <= 0.001;
}

NSString *DYYYDefaultSpeedSettingsString(void) {
    return kDYYYDefaultSpeedSettingsString;
}

static NSString *DYYYSpeedSettingsStringFromValue(id value) {
    if ([value isKindOfClass:[NSString class]]) {
        return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
    if ([value respondsToSelector:@selector(stringValue)]) {
        return [[value stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
    return nil;
}

static NSArray<NSString *> *DYYYParsedSpeedOptionsFromString(NSString *speedConfig) {
    NSMutableArray<NSString *> *validSpeeds = [NSMutableArray array];
    NSCharacterSet *whitespace = [NSCharacterSet whitespaceAndNewlineCharacterSet];

    for (NSString *component in [speedConfig componentsSeparatedByString:@","]) {
        NSString *trimmedValue = [component stringByTrimmingCharactersInSet:whitespace];
        if (trimmedValue.length == 0) {
            continue;
        }

        NSScanner *scanner = [NSScanner scannerWithString:trimmedValue];
        double speed = 0.0;
        if ([scanner scanDouble:&speed] && scanner.isAtEnd && isfinite(speed) && speed > 0.0) {
            [validSpeeds addObject:DYYYFormatSpeedOption(speed)];
        }
    }
    return validSpeeds;
}

static double DYYYSpeedPreferenceValue(NSString *key, double fallback) {
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    double speed = [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : fallback;
    if (!isfinite(speed) || speed <= 0.0) {
        return fallback;
    }
    return speed;
}

static BOOL DYYYSpeedOptionsContainSpeed(NSArray<NSString *> *speedOptions, double speed) {
    if (!isfinite(speed) || speed <= 0.0) {
        return YES;
    }

    for (NSString *speedString in speedOptions) {
        if (DYYYSpeedValuesMatch([speedString doubleValue], speed)) {
            return YES;
        }
    }
    return NO;
}

static BOOL DYYYSpeedOptionsCoverRequiredPlaybackSpeeds(NSArray<NSString *> *speedOptions) {
    double defaultSpeed = DYYYSpeedPreferenceValue(@"DYYYDefaultSpeed", 1.0);
    double longPressSpeed = DYYYSpeedPreferenceValue(@"DYYYLongPressSpeed", 2.0);
    return DYYYSpeedOptionsContainSpeed(speedOptions, defaultSpeed) &&
           DYYYSpeedOptionsContainSpeed(speedOptions, longPressSpeed);
}

BOOL DYYYNormalizeSpeedSettingsForRequiredSpeeds(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *speedConfig = DYYYSpeedSettingsStringFromValue([defaults objectForKey:@"DYYYSpeedSettings"]);
    NSArray<NSString *> *validSpeeds = DYYYParsedSpeedOptionsFromString(speedConfig ?: @"");
    BOOL shouldUseDefaultSettings = speedConfig.length == 0 ||
                                    validSpeeds.count == 0 ||
                                    !DYYYSpeedOptionsCoverRequiredPlaybackSpeeds(validSpeeds);

    if (!shouldUseDefaultSettings) {
        return NO;
    }

    if (![speedConfig isEqualToString:kDYYYDefaultSpeedSettingsString]) {
        [defaults setObject:kDYYYDefaultSpeedSettingsString forKey:@"DYYYSpeedSettings"];
        return YES;
    }
    return NO;
}

NSArray *getSpeedOptions() {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    DYYYNormalizeSpeedSettingsForRequiredSpeeds();

    NSString *speedConfig = DYYYSpeedSettingsStringFromValue([defaults objectForKey:@"DYYYSpeedSettings"]) ?: kDYYYDefaultSpeedSettingsString;
    NSArray<NSString *> *validSpeeds = DYYYParsedSpeedOptionsFromString(speedConfig);
    if (validSpeeds.count == 0) {
        [defaults setObject:kDYYYDefaultSpeedSettingsString forKey:@"DYYYSpeedSettings"];
        validSpeeds = DYYYParsedSpeedOptionsFromString(kDYYYDefaultSpeedSettingsString);
    }

    return validSpeeds;
}

NSInteger getCurrentSpeedIndex() {
    NSInteger index = [[NSUserDefaults standardUserDefaults] integerForKey:@"DYYYCurrentSpeedIndex"];
    NSArray *speeds = getSpeedOptions();

    if (index >= speeds.count || index < 0) {
        index = 0;
        [[NSUserDefaults standardUserDefaults] setInteger:index forKey:@"DYYYCurrentSpeedIndex"];
    }

    return index;
}

float getCurrentSpeed() {
    NSArray *speeds = getSpeedOptions();
    NSInteger index = getCurrentSpeedIndex();

    if (speeds.count == 0)
        return 1.0;
    float speed = [speeds[index] floatValue];
    return speed > 0 ? speed : 1.0;
}

void setCurrentSpeedIndex(NSInteger index) {
    NSArray *speeds = getSpeedOptions();

    if (speeds.count == 0)
        return;
    index = index % speeds.count;
    if (index < 0) {
        index += speeds.count;
    }

    [[NSUserDefaults standardUserDefaults] setInteger:index forKey:@"DYYYCurrentSpeedIndex"];
}

BOOL setCurrentSpeedValue(float speed) {
    if (!isfinite(speed) || speed <= 0.0f) {
        return NO;
    }

    NSArray *speeds = getSpeedOptions();
    for (NSInteger index = 0; index < speeds.count; index++) {
        if (DYYYSpeedValuesMatch([speeds[index] floatValue], speed)) {
            setCurrentSpeedIndex(index);
            return YES;
        }
    }
    return NO;
}

void updateSpeedButtonUI() {
    if (!speedButton)
        return;

    float currentSpeed = getCurrentSpeed();

    NSString *formattedSpeed;
    if (fmodf(currentSpeed, 1.0) == 0) {
        // 整数值 (1.0, 2.0) -> "1", "2"
        formattedSpeed = [NSString stringWithFormat:@"%.0f", currentSpeed];
    } else if (fmodf(currentSpeed * 10, 1.0) == 0) {
        // 一位小数 (1.5) -> "1.5"
        formattedSpeed = [NSString stringWithFormat:@"%.1f", currentSpeed];
    } else {
        // 两位小数 (1.25) -> "1.25"
        formattedSpeed = [NSString stringWithFormat:@"%.2f", currentSpeed];
    }

    if (showSpeedX) {
        formattedSpeed = [formattedSpeed stringByAppendingString:@"x"];
    }

    if ([NSThread isMainThread]) {
        [speedButton setTitle:formattedSpeed forState:UIControlStateNormal];
    } else {
        __weak FloatingSpeedButton *weakButton = speedButton;
        dispatch_async(dispatch_get_main_queue(), ^{
          FloatingSpeedButton *strongButton = weakButton;
          if (!strongButton) {
              return;
          }
          [strongButton setTitle:formattedSpeed forState:UIControlStateNormal];
        });
    }
}

FloatingSpeedButton *getSpeedButton(void) { return speedButton; }

NSArray *findViewControllersInHierarchy(UIViewController *rootViewController) {
    if (!rootViewController) {
        return @[];
    }

    NSMutableArray *viewControllers = [NSMutableArray array];
    [viewControllers addObject:rootViewController];

    for (UIViewController *childVC in rootViewController.childViewControllers) {
        [viewControllers addObjectsFromArray:findViewControllersInHierarchy(childVC)];
    }

    return viewControllers;
}

static const CGFloat kDYYYSpeedButtonEdgeInset = 10.0;
static const CGFloat kDYYYSpeedButtonDefaultYFromBottomPercent = 0.65;
static const CGFloat kDYYYSpeedButtonPressedScale = 0.75;

typedef NS_ENUM(NSInteger, DYYYSpeedButtonEdge) {
    DYYYSpeedButtonEdgeLeft = 0,
    DYYYSpeedButtonEdgeRight,
    DYYYSpeedButtonEdgeTop,
    DYYYSpeedButtonEdgeBottom,
};

static BOOL DYYYSpeedButtonStickToEdgeEnabled(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:DYYY_SPEED_BUTTON_STICK_TO_EDGE_KEY];
}

static BOOL DYYYAutoHideSpeedButtonEnabled(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYAutoHideSpeedButton"] && DYYYSpeedButtonStickToEdgeEnabled();
}

static NSTimeInterval DYYYAutoHideSpeedButtonInterval(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:@"DYYYAutoHideSpeedButtonTime"] == nil) {
        return 30.0;
    }
    double interval = [defaults doubleForKey:@"DYYYAutoHideSpeedButtonTime"];
    return interval > 0.0 ? interval : 30.0;
}


static const CGFloat kDYYYSpeedButtonEdgeSwitchHysteresis = 12.0;

@interface FloatingSpeedButton ()
@property(nonatomic, assign) DYYYSpeedButtonEdge dyyyActiveDragEdge;
@property(nonatomic, assign) BOOL dyyyHasCenterBeforeEdgeHidden;
@property(nonatomic, assign) CGPoint dyyyCenterBeforeEdgeHidden;
@end

@implementation FloatingSpeedButton

+ (void)reloadConfiguration {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self reloadConfiguration]; });
        return;
    }
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    BOOL enabled = [defaults boolForKey:@"DYYYEnableFloatSpeedButton"];
    BOOL showX = [defaults boolForKey:@"DYYYSpeedButtonShowX"];
    CGFloat configuredSize = [defaults floatForKey:@"DYYYSpeedButtonSize"];
    CGFloat size = MIN(MAX(configuredSize > 0 ? configuredSize : 32.0, 20.0), 60.0);
    BOOL changed = enabled != isFloatSpeedButtonEnabled || showX != showSpeedX || fabs(size - speedButtonSize) > FLT_EPSILON;
    isFloatSpeedButtonEnabled = enabled;
    showSpeedX = showX;
    speedButtonSize = size;
    if (speedButton) {
        if (speedButton.isEdgeHidden && !DYYYAutoHideSpeedButtonEnabled()) [speedButton dyyy_restoreFromEdgeHidden];
        [speedButton loadSavedPosition];
        [speedButton resetFadeTimer];
    }
    if (!changed) return;
    if (speedButton && fabs(speedButton.bounds.size.width - size) > FLT_EPSILON) {
        speedButton.bounds = CGRectMake(0, 0, size, size);
        speedButton.layer.cornerRadius = size / 2.0;
        [speedButton loadSavedPosition];
    }
    updateSpeedButtonUI();
}

+ (void)attachToWindow:(UIWindow *)window interactionController:(UIViewController *)controller {
    if (!speedButton) {
        CGFloat size = speedButtonSize;
        CGRect frame = CGRectMake((window.bounds.size.width - size) / 2.0, (window.bounds.size.height - size) / 2.0, size, size);
        speedButton = [[self alloc] initWithFrame:frame];
        // 新控件先隐藏，是否显示由协调器决定。
        speedButton.hidden = YES;
        updateSpeedButtonUI();
    }
    if (speedButton.interactionController != controller) {
        speedButton.interactionController = controller;
        [speedButton resetButtonState];
    }
    if (speedButton.window != window) {
        [window addSubview:speedButton];
        [speedButton loadSavedPosition];
        [speedButton resetFadeTimer];
    }
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.accessibilityLabel = @"DYYYSpeedSwitchButton";
        self.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.1];
        self.layer.cornerRadius = frame.size.width / 2;
        self.layer.masksToBounds = YES;
        self.layer.borderWidth = 1.0;
        self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.2].CGColor;

        [self setTitleColor:[UIColor colorWithWhite:1.0 alpha:0.3] forState:UIControlStateNormal];
        self.titleLabel.font = [UIFont boldSystemFontOfSize:15];

        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOffset = CGSizeMake(0, 2);
        self.layer.shadowOpacity = 0.2;

        self.userInteractionEnabled = YES;
        self.isResponding = YES;

        self.originalAlpha = 1.0;
        self.alpha = 0.5;

        [self resetFadeTimer];
        [self ensureStatusCheckTimerRunning];

        [self setupGestureRecognizers];

        [self loadSavedPosition];

        self.justToggledLock = NO;
    }
    return self;
}
- (void)setupGestureRecognizers {
    for (UIGestureRecognizer *recognizer in [self.gestureRecognizers copy]) {
        [self removeGestureRecognizer:recognizer];
    }
    [self removeTarget:self action:@selector(handleTouchUpInside:) forControlEvents:UIControlEventTouchUpInside];
    [self removeTarget:self action:@selector(handleTouchDown:) forControlEvents:UIControlEventTouchDown];
    [self removeTarget:self action:@selector(handleTouchUpOutside:) forControlEvents:UIControlEventTouchUpOutside];

    UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [self addGestureRecognizer:panGesture];

    UILongPressGestureRecognizer *longPressGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPressGesture.minimumPressDuration = 0.5;
    [self addGestureRecognizer:longPressGesture];

    [self addTarget:self action:@selector(handleTouchUpInside:) forControlEvents:UIControlEventTouchUpInside];
    [self addTarget:self action:@selector(handleTouchDown:) forControlEvents:UIControlEventTouchDown];
    [self addTarget:self action:@selector(handleTouchUpOutside:) forControlEvents:UIControlEventTouchUpOutside];

    panGesture.delegate = (id<UIGestureRecognizerDelegate>)self;
    longPressGesture.delegate = (id<UIGestureRecognizerDelegate>)self;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    if ([gestureRecognizer isKindOfClass:[UIPanGestureRecognizer class]]) {
        return YES;
    }
    return NO;
}

- (void)handleTouchDown:(UIButton *)sender {
    if (self.isEdgeHidden) { [self dyyy_restoreFromEdgeHidden]; self.dyyyJustRestoredFromEdgeHidden = YES; return; }
    self.isResponding = YES;
    [self resetFadeTimer];
}

- (void)handleTouchUpInside:(UIButton *)sender {
    if (self.dyyyJustRestoredFromEdgeHidden) { self.dyyyJustRestoredFromEdgeHidden = NO; return; }
    if (self.justToggledLock) {
        self.justToggledLock = NO;
        return;
    }

    [self resetFadeTimer];

    [UIView animateWithDuration:0.08
        animations:^{
          self.transform = CGAffineTransformMakeScale(1.15, 1.15);
        }
        completion:^(BOOL finished) {
          [UIView animateWithDuration:0.08
                           animations:^{
                             self.transform = CGAffineTransformIdentity;
                           }];
        }];

    id currentController = DYYYCurrentSpeedInteractionController();
    if (currentController) {
        self.interactionController = currentController;
    }

    if (self.interactionController) {
        @try {
            [self.interactionController speedButtonTapped:self];
        } @catch (NSException *exception) {
            self.isResponding = NO;
        }
    } else {
        self.isResponding = NO;
    }
}

- (void)handleTouchUpOutside:(UIButton *)sender {
    self.justToggledLock = NO;
    [self resetFadeTimer];
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    self.isResponding = YES;

    if (gesture.state == UIGestureRecognizerStateBegan) {
        [self resetFadeTimer];

        self.originalLockState = self.isLocked;

        [self toggleLockState];
    }
}

- (void)toggleLockState {
    self.isLocked = !self.isLocked;
    self.justToggledLock = YES;

    NSString *toastMessage = self.isLocked ? @"按钮已锁定" : @"按钮已解锁";
    [DYYYUtils showToast:toastMessage];

    if (self.isLocked) {
        [self saveButtonPosition];
    }

    if (@available(iOS 10.0, *)) {
        UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [generator prepare];
        [generator impactOccurred];
    }

    __weak __typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      __strong __typeof(weakSelf) strongSelf = weakSelf;
      if (!strongSelf) {
          return;
      }
      strongSelf.justToggledLock = NO;
    });
}

- (void)resetToggleLockFlag {
    __weak __typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
      __strong __typeof(weakSelf) strongSelf = weakSelf;
      if (!strongSelf) {
          return;
      }
      strongSelf.justToggledLock = NO;
    });
}

- (void)resetButtonState {
    BOOL preserveEdgeHidden = self.isEdgeHidden &&
                              (DYYYAutoHideSpeedButtonEnabled() || self.dyyyEdgeHiddenByClearMode);
    self.justToggledLock = NO;
    self.dyyyJustRestoredFromEdgeHidden = NO;
    self.isResponding = YES;
    self.userInteractionEnabled = YES;
    self.transform = CGAffineTransformIdentity;

    if (preserveEdgeHidden) {
        self.isEdgeHidden = YES;
        self.alpha = 0.02;
        [self dyyy_showEdgeIndicator];
    } else {
        self.isEdgeHidden = NO;
        [self dyyy_hideEdgeIndicator];
        self.alpha = self.originalAlpha;
        [self dyyy_schedulePresentationTimersIfNeeded];
    }

    [self setupGestureRecognizers];
}

- (void)resetFadeTimer {
    [self dyyy_cancelAutoHideTimer];
    if (self.fadeTimer) {
        [self.fadeTimer invalidate];
        self.fadeTimer = nil;
    }
    if (self.isEdgeHidden) {
        return;
    }

    if (self.alpha != self.originalAlpha) {
        [UIView animateWithDuration:0.2
                         animations:^{
                           self.alpha = self.originalAlpha;
                         }];
    }

    __weak __typeof(self) weakSelf = self;
    if (!DYYYAutoHideSpeedButtonEnabled()) {
        NSTimer *fadeTimer = [NSTimer scheduledTimerWithTimeInterval:3.0
                                                             repeats:NO
                                                               block:^(NSTimer *timer) {
                                                                 __strong __typeof(weakSelf) strongSelf = weakSelf;
                                                                 if (!strongSelf || strongSelf.isEdgeHidden) {
                                                                     return;
                                                                 }
                                                                 [UIView animateWithDuration:0.3
                                                                                  animations:^{
                                                                                    strongSelf.alpha = 0.5;
                                                                                  }];
                                                                 strongSelf.fadeTimer = nil;
                                                               }];
        self.fadeTimer = fadeTimer;
        [[NSRunLoop mainRunLoop] addTimer:fadeTimer forMode:NSRunLoopCommonModes];
        return;
    }

    NSTimeInterval interval = DYYYAutoHideSpeedButtonInterval();
    NSTimer *autoHideTimer = [NSTimer scheduledTimerWithTimeInterval:interval
                                                             repeats:NO
                                                               block:^(NSTimer *timer) {
                                                                 __strong __typeof(weakSelf) strongSelf = weakSelf;
                                                                 if (!strongSelf) {
                                                                     return;
                                                                 }
                                                                 [strongSelf dyyy_applyEdgeHiddenState];
                                                                 strongSelf.autoHideTimer = nil;
                                                               }];
    self.autoHideTimer = autoHideTimer;
    [[NSRunLoop mainRunLoop] addTimer:autoHideTimer forMode:NSRunLoopCommonModes];
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    if (self.isLocked)
        return;

    self.justToggledLock = NO;
    self.dyyyJustRestoredFromEdgeHidden = NO;
    if (self.isEdgeHidden) [self dyyy_restoreFromEdgeHidden];
    [self resetFadeTimer];

    if (pan.state == UIGestureRecognizerStateBegan) {
        self.transform = CGAffineTransformIdentity;
        if (DYYYSpeedButtonStickToEdgeEnabled()) {
            self.dyyyActiveDragEdge = [self dyyyEdgeForCenter:self.center];
            self.center = [self dyyyCenterOnEdge:self.dyyyActiveDragEdge forPoint:self.center];
        }
    } else if (pan.state == UIGestureRecognizerStateChanged) {
        CGPoint touchPoint = [pan locationInView:self.superview];
        if (DYYYSpeedButtonStickToEdgeEnabled()) {
            DYYYSpeedButtonEdge nearestEdge = [self dyyyNearestEdgeForPoint:touchPoint];
            if (nearestEdge != self.dyyyActiveDragEdge) {
                CGFloat currentDist = [self dyyyDistanceFromPoint:touchPoint toEdge:self.dyyyActiveDragEdge];
                CGFloat nearestDist = [self dyyyDistanceFromPoint:touchPoint toEdge:nearestEdge];
                if (nearestDist + kDYYYSpeedButtonEdgeSwitchHysteresis < currentDist) {
                    self.dyyyActiveDragEdge = nearestEdge;
                }
            }
            self.center = [self dyyyCenterOnEdge:self.dyyyActiveDragEdge forPoint:touchPoint];
        } else {
            self.center = [self dyyyClampedCenterForProposedCenter:touchPoint];
        }
        self.alpha = self.originalAlpha;
    } else if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        self.center = [self dyyyConstrainedCenterForProposedCenter:self.center];
        self.alpha = self.originalAlpha;
        [self saveButtonPosition];
        if (self.isEdgeHidden) {
            [self dyyy_showEdgeIndicator];
        }
    }
}

- (void)saveButtonPosition {
    if (self.superview) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults setFloat:self.center.x / self.superview.bounds.size.width forKey:@"DYYYSpeedButtonCenterXPercent"];
        [defaults setFloat:self.center.y / self.superview.bounds.size.height forKey:@"DYYYSpeedButtonCenterYPercent"];
        [defaults setBool:self.isLocked forKey:@"DYYYSpeedButtonLocked"];
    }
}

- (void)loadSavedPosition {
    if (!self.superview) {
        return;
    }

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    self.isLocked = [defaults boolForKey:@"DYYYSpeedButtonLocked"];

    CGPoint targetCenter;
    if ([self dyyyHasSavedPosition]) {
        float centerXPercent = [defaults floatForKey:@"DYYYSpeedButtonCenterXPercent"];
        float centerYPercent = [defaults floatForKey:@"DYYYSpeedButtonCenterYPercent"];
        targetCenter = CGPointMake(centerXPercent * self.superview.bounds.size.width,
                                   centerYPercent * self.superview.bounds.size.height);
    } else {
        targetCenter = [self dyyyDefaultCenter];
    }

    self.center = [self dyyyConstrainedCenterForProposedCenter:targetCenter];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.window) {
        [self stopTimers];
        [self dyyy_hideEdgeIndicator];
        return;
    }
    [self ensureStatusCheckTimerRunning];
    [self resetFadeTimer];
}

- (void)ensureStatusCheckTimerRunning {
    if (self.statusCheckTimer && [self.statusCheckTimer isValid]) {
        return;
    }
    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:60.0 target:self selector:@selector(checkAndRecoverButtonStatus) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    self.statusCheckTimer = timer;
}

- (void)stopTimers {
    [self dyyy_cancelAutoHideTimer];
    if (self.statusCheckTimer) {
        [self.statusCheckTimer invalidate];
        self.statusCheckTimer = nil;
    }
    if (self.fadeTimer) {
        [self.fadeTimer invalidate];
        self.fadeTimer = nil;
    }
}

- (void)checkAndRecoverButtonStatus {
    if (!self.isResponding) {
        [self resetButtonState];
        self.isResponding = YES;
    }

    if (!self.interactionController) {
        self.interactionController = DYYYCurrentSpeedInteractionController();
    }
}

- (void)dealloc {
    [self.edgeIndicatorView removeFromSuperview];
    [self stopTimers];
}
- (void)resetToDefaultPosition {
    if (!self.superview) {
        return;
    }

    self.dyyyHasCenterBeforeEdgeHidden = NO;
    if (self.isEdgeHidden && !self.dyyyEdgeHiddenByClearMode) {
        [self dyyy_restoreFromEdgeHidden];
    }

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObjectForKey:@"DYYYSpeedButtonCenterXPercent"];
    [defaults removeObjectForKey:@"DYYYSpeedButtonCenterYPercent"];
    self.center = [self dyyyDefaultCenter];
    [self resetFadeTimer];
}

- (void)dyyy_cancelAutoHideTimer {
    if (self.autoHideTimer) {
        [self.autoHideTimer invalidate];
        self.autoHideTimer = nil;
    }
}

- (void)dyyy_rememberCenterBeforeEdgeHidden {
    if (self.dyyyHasCenterBeforeEdgeHidden) {
        return;
    }
    self.dyyyCenterBeforeEdgeHidden = self.center;
    self.dyyyHasCenterBeforeEdgeHidden = YES;
}

- (void)dyyy_moveToNearestEdgeForHiddenState {
    [self dyyy_rememberCenterBeforeEdgeHidden];
    self.center = [self dyyySnappedCenterForProposedCenter:self.center];
}

- (void)dyyy_restoreCenterBeforeEdgeHiddenIfNeeded {
    if (!self.dyyyHasCenterBeforeEdgeHidden) {
        return;
    }
    self.center = [self dyyyConstrainedCenterForProposedCenter:self.dyyyCenterBeforeEdgeHidden];
    self.dyyyHasCenterBeforeEdgeHidden = NO;
}

- (void)dyyy_applyEdgeHiddenState {
    // 位置锁定只限制拖动，不能阻止自动隐藏计时器收边。
    if (self.hidden || !self.window || self.isEdgeHidden || self.dyyyEdgeHiddenByClearMode || !DYYYAutoHideSpeedButtonEnabled()) {
        return;
    }

    [self dyyy_cancelAutoHideTimer];
    [self dyyy_moveToNearestEdgeForHiddenState];
    self.dyyyEdgeHiddenByClearMode = NO;
    self.isEdgeHidden = YES;
    self.alpha = 0.02;
    [self dyyy_showEdgeIndicator];
}

- (void)dyyy_restoreFromEdgeHidden {
    if (!self.isEdgeHidden || self.dyyyEdgeHiddenByClearMode) {
        return;
    }

    self.isEdgeHidden = NO;
    [self dyyy_restoreCenterBeforeEdgeHiddenIfNeeded];
    self.alpha = self.originalAlpha;
    [self dyyy_hideEdgeIndicator];
    [self resetFadeTimer];
}

- (void)dyyy_schedulePresentationTimersIfNeeded {
    if (self.isEdgeHidden || self.dyyyEdgeHiddenByClearMode) {
        self.alpha = 0.02;
        [self dyyy_showEdgeIndicator];
        return;
    }

    if (DYYYAutoHideSpeedButtonEnabled() && self.autoHideTimer && [self.autoHideTimer isValid]) {
        return;
    }

    [self resetFadeTimer];
}

- (void)dyyy_showEdgeIndicator {
    if (!self.superview || !self.isEdgeHidden) {
        return;
    }

    // 自动隐藏产生的边缘条只能依附于当前播放页；清屏边缘态由清屏流程单独管理。
    if (!self.dyyyEdgeHiddenByClearMode && self.hidden) {
        [self dyyy_hideEdgeIndicator];
        return;
    }

    DYYYSpeedButtonEdge edge = [self dyyyEdgeForCenter:self.center];
    CGFloat indicatorThickness = 2.0;
    CGSize superSize = self.superview.bounds.size;
    CGFloat centerX = self.center.x;
    CGFloat centerY = self.center.y;

    if (!self.edgeIndicatorView) {
        self.edgeIndicatorView = [[UIView alloc] init];
        self.edgeIndicatorView.backgroundColor = [UIColor systemGrayColor];
        self.edgeIndicatorView.userInteractionEnabled = NO;
        self.edgeIndicatorView.layer.masksToBounds = YES;
    }

    CGRect frame = CGRectZero;
    CACornerMask maskedCorners = 0;
    switch (edge) {
        case DYYYSpeedButtonEdgeLeft:
            frame = CGRectMake(0.0,
                               centerY - CGRectGetHeight(self.bounds) * 0.5,
                               indicatorThickness,
                               CGRectGetHeight(self.bounds));
            maskedCorners = kCALayerMaxXMinYCorner | kCALayerMaxXMaxYCorner;
            break;
        case DYYYSpeedButtonEdgeRight:
            frame = CGRectMake(superSize.width - indicatorThickness,
                               centerY - CGRectGetHeight(self.bounds) * 0.5,
                               indicatorThickness,
                               CGRectGetHeight(self.bounds));
            maskedCorners = kCALayerMinXMinYCorner | kCALayerMinXMaxYCorner;
            break;
        case DYYYSpeedButtonEdgeTop:
            frame = CGRectMake(centerX - CGRectGetWidth(self.bounds) * 0.5,
                               0.0,
                               CGRectGetWidth(self.bounds),
                               indicatorThickness);
            maskedCorners = kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
            break;
        case DYYYSpeedButtonEdgeBottom:
            frame = CGRectMake(centerX - CGRectGetWidth(self.bounds) * 0.5,
                               superSize.height - indicatorThickness,
                               CGRectGetWidth(self.bounds),
                               indicatorThickness);
            maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
            break;
    }

    self.edgeIndicatorView.frame = frame;
    self.edgeIndicatorView.layer.cornerRadius = indicatorThickness;
    self.edgeIndicatorView.layer.maskedCorners = maskedCorners;
    self.edgeIndicatorView.alpha = 1.0;
    self.edgeIndicatorView.hidden = NO;

    if (![self.edgeIndicatorView isDescendantOfView:self.superview]) {
        [self.superview addSubview:self.edgeIndicatorView];
    }
    [self.superview bringSubviewToFront:self.edgeIndicatorView];
}

- (void)dyyy_hideEdgeIndicator {
    if (self.edgeIndicatorView) {
        self.edgeIndicatorView.hidden = YES;
    }
}

- (void)dyyyEdgeGeometryForSuperviewSize:(CGSize)size
                               halfWidth:(CGFloat)hw
                              halfHeight:(CGFloat)hh
                             leftCenterX:(CGFloat *)leftCenterX
                            rightCenterX:(CGFloat *)rightCenterX
                               topCenterY:(CGFloat *)topCenterY
                            bottomCenterY:(CGFloat *)bottomCenterY
                          minAlongEdgeX:(CGFloat *)minAlongEdgeX
                          maxAlongEdgeX:(CGFloat *)maxAlongEdgeX
                          minAlongEdgeY:(CGFloat *)minAlongEdgeY
                          maxAlongEdgeY:(CGFloat *)maxAlongEdgeY {
    CGFloat inset = kDYYYSpeedButtonEdgeInset;
    *leftCenterX = hw + inset;
    *rightCenterX = size.width - hw - inset;
    *topCenterY = hh + inset;
    *bottomCenterY = size.height - hh - inset;
    *minAlongEdgeX = hw + inset;
    *maxAlongEdgeX = size.width - hw - inset;
    *minAlongEdgeY = hh + inset;
    *maxAlongEdgeY = size.height - hh - inset;
}

- (BOOL)dyyyEdgeMetricsWithLeftX:(CGFloat *)leftX
                          rightX:(CGFloat *)rightX
                            topY:(CGFloat *)topY
                         bottomY:(CGFloat *)bottomY
                            minX:(CGFloat *)minX
                            maxX:(CGFloat *)maxX
                            minY:(CGFloat *)minY
                            maxY:(CGFloat *)maxY {
    if (!self.superview) {
        return NO;
    }

    CGSize size = self.superview.bounds.size;
    CGFloat hw = CGRectGetWidth(self.bounds) * 0.5;
    CGFloat hh = CGRectGetHeight(self.bounds) * 0.5;
    [self dyyyEdgeGeometryForSuperviewSize:size
                                 halfWidth:hw
                                halfHeight:hh
                               leftCenterX:leftX
                              rightCenterX:rightX
                                 topCenterY:topY
                              bottomCenterY:bottomY
                            minAlongEdgeX:minX
                            maxAlongEdgeX:maxX
                            minAlongEdgeY:minY
                            maxAlongEdgeY:maxY];
    return YES;
}

- (CGFloat)dyyyDistanceFromPoint:(CGPoint)point toEdge:(DYYYSpeedButtonEdge)edge {
    CGFloat leftX, rightX, topY, bottomY, minX, maxX, minY, maxY;
    if (![self dyyyEdgeMetricsWithLeftX:&leftX rightX:&rightX topY:&topY bottomY:&bottomY minX:&minX maxX:&maxX minY:&minY maxY:&maxY]) {
        return CGFLOAT_MAX;
    }

    switch (edge) {
        case DYYYSpeedButtonEdgeLeft:
            return fabs(point.x - leftX);
        case DYYYSpeedButtonEdgeRight:
            return fabs(point.x - rightX);
        case DYYYSpeedButtonEdgeTop:
            return fabs(point.y - topY);
        case DYYYSpeedButtonEdgeBottom:
            return fabs(point.y - bottomY);
    }
}

- (DYYYSpeedButtonEdge)dyyyNearestEdgeForPoint:(CGPoint)point {
    DYYYSpeedButtonEdge edge = DYYYSpeedButtonEdgeLeft;
    CGFloat minDist = [self dyyyDistanceFromPoint:point toEdge:edge];

    for (DYYYSpeedButtonEdge candidate = DYYYSpeedButtonEdgeRight; candidate <= DYYYSpeedButtonEdgeBottom; candidate++) {
        CGFloat dist = [self dyyyDistanceFromPoint:point toEdge:candidate];
        if (dist < minDist) {
            minDist = dist;
            edge = candidate;
        }
    }
    return edge;
}

- (DYYYSpeedButtonEdge)dyyyEdgeForCenter:(CGPoint)center {
    return [self dyyyNearestEdgeForPoint:center];
}

- (CGPoint)dyyyCenterOnEdge:(DYYYSpeedButtonEdge)edge forPoint:(CGPoint)point {
    CGFloat leftX, rightX, topY, bottomY, minX, maxX, minY, maxY;
    if (![self dyyyEdgeMetricsWithLeftX:&leftX rightX:&rightX topY:&topY bottomY:&bottomY minX:&minX maxX:&maxX minY:&minY maxY:&maxY]) {
        return point;
    }

    switch (edge) {
        case DYYYSpeedButtonEdgeLeft:
            return CGPointMake(leftX, MIN(MAX(point.y, minY), maxY));
        case DYYYSpeedButtonEdgeRight:
            return CGPointMake(rightX, MIN(MAX(point.y, minY), maxY));
        case DYYYSpeedButtonEdgeTop:
            return CGPointMake(MIN(MAX(point.x, minX), maxX), topY);
        case DYYYSpeedButtonEdgeBottom:
            return CGPointMake(MIN(MAX(point.x, minX), maxX), bottomY);
    }
}

- (CGPoint)dyyySnappedCenterForProposedCenter:(CGPoint)proposed {
    DYYYSpeedButtonEdge edge = [self dyyyNearestEdgeForPoint:proposed];
    return [self dyyyCenterOnEdge:edge forPoint:proposed];
}

- (CGPoint)dyyyClampedCenterForProposedCenter:(CGPoint)proposed {
    CGFloat minX, maxX, minY, maxY;
    CGFloat unusedLeft, unusedRight, unusedTop, unusedBottom;
    if (![self dyyyEdgeMetricsWithLeftX:&unusedLeft rightX:&unusedRight topY:&unusedTop bottomY:&unusedBottom minX:&minX maxX:&maxX minY:&minY maxY:&maxY]) {
        return proposed;
    }
    return CGPointMake(MIN(MAX(proposed.x, minX), maxX), MIN(MAX(proposed.y, minY), maxY));
}

- (CGPoint)dyyyConstrainedCenterForProposedCenter:(CGPoint)proposed {
    if (DYYYSpeedButtonStickToEdgeEnabled()) {
        return [self dyyySnappedCenterForProposedCenter:proposed];
    }
    return [self dyyyClampedCenterForProposedCenter:proposed];
}

- (CGPoint)dyyyDefaultCenter {
    if (!self.superview) {
        return self.center;
    }

    CGSize size = self.superview.bounds.size;
    CGFloat hw = CGRectGetWidth(self.bounds) * 0.5;
    CGFloat hh = CGRectGetHeight(self.bounds) * 0.5;
    CGFloat leftX, rightX, topY, bottomY, minX, maxX, minY, maxY;
    [self dyyyEdgeGeometryForSuperviewSize:size
                                 halfWidth:hw
                                halfHeight:hh
                               leftCenterX:&leftX
                              rightCenterX:&rightX
                                 topCenterY:&topY
                              bottomCenterY:&bottomY
                            minAlongEdgeX:&minX
                            maxAlongEdgeX:&maxX
                            minAlongEdgeY:&minY
                            maxAlongEdgeY:&maxY];

    CGFloat defaultY = size.height * (1.0 - kDYYYSpeedButtonDefaultYFromBottomPercent);
    defaultY = MIN(MAX(defaultY, minY), maxY);
    return CGPointMake(rightX, defaultY);
}

- (BOOL)dyyyHasSavedPosition {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    return [defaults objectForKey:@"DYYYSpeedButtonCenterXPercent"] != nil &&
           [defaults objectForKey:@"DYYYSpeedButtonCenterYPercent"] != nil;
}

@end
