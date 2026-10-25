#import <UIKit/UIKit.h>

@interface FloatingSpeedButton : UIButton
@property(nonatomic, assign) CGPoint lastLocation;
@property(nonatomic, weak) id interactionController;
@property(nonatomic, assign) BOOL isLocked;
@property(nonatomic, assign) BOOL justToggledLock;
@property(nonatomic, assign) BOOL originalLockState;
@property(nonatomic, assign) BOOL isResponding;
@property(nonatomic, strong) NSTimer *statusCheckTimer;
@property(nonatomic, strong) NSTimer *fadeTimer;
@property(nonatomic, assign) CGFloat originalAlpha;
+ (void)reloadConfiguration;
+ (void)attachToWindow:(UIWindow *)window interactionController:(UIViewController *)controller;
- (void)saveButtonPosition;
- (void)loadSavedPosition;
- (void)resetButtonState;
- (void)toggleLockState;
- (void)resetFadeTimer;
@property(nonatomic, strong) NSTimer *autoHideTimer;
@property(nonatomic, strong) UIView *edgeIndicatorView;
@property(nonatomic, assign) BOOL isEdgeHidden;
@property(nonatomic, assign) BOOL dyyyEdgeHiddenByClearMode;
@property(nonatomic, assign) BOOL dyyyJustRestoredFromEdgeHidden;
- (void)resetToDefaultPosition;
- (void)dyyy_schedulePresentationTimersIfNeeded;
- (void)dyyy_restoreFromEdgeHidden;
- (void)dyyy_hideEdgeIndicator;
- (void)dyyy_showEdgeIndicator;
@end

#ifdef __cplusplus
extern "C" {
#endif

extern FloatingSpeedButton *speedButton;
extern BOOL isFloatSpeedButtonEnabled;
extern BOOL showSpeedX;
extern CGFloat speedButtonSize;

extern NSArray *getSpeedOptions(void);
extern NSString *DYYYDefaultSpeedSettingsString(void);
extern BOOL DYYYNormalizeSpeedSettingsForRequiredSpeeds(void);

extern FloatingSpeedButton *getSpeedButton(void);
extern NSArray *findViewControllersInHierarchy(UIViewController *rootViewController);
extern float getCurrentSpeed(void);
extern NSInteger getCurrentSpeedIndex(void);
extern void setCurrentSpeedIndex(NSInteger index);
extern BOOL setCurrentSpeedValue(float speed);
extern void updateSpeedButtonUI(void);
extern id DYYYCurrentSpeedInteractionController(void);

#ifdef __cplusplus
}
#endif
