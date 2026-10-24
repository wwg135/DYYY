// macOS 回归夹具：只实现显示协调器需要的 UIKit 接口，不模拟真实布局或动画。
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@class UIWindow, UIImage, UIPanGestureRecognizer, UILongPressGestureRecognizer;

@interface UIView : NSObject
@property(nonatomic, assign) BOOL hidden;
@property(nonatomic, assign) CGFloat alpha;
@property(nonatomic, assign) CGRect frame;
@property(nonatomic, assign) CGRect bounds;
@property(nonatomic, weak) UIView *superview;
@property(nonatomic, readonly) UIWindow *window;
@property(nonatomic, readonly) NSArray<UIView *> *subviews;
- (void)addSubview:(UIView *)view;
- (void)removeFromSuperview;
- (void)bringSubviewToFront:(UIView *)view;
- (CGRect)convertRect:(CGRect)rect toView:(UIView *)view;
@end

@interface UIWindow : UIView
@end
@interface UIButton : UIView
@property(nonatomic, assign) BOOL selected;
@end
@interface UIViewController : NSObject
@property(nonatomic, strong) UIView *viewIfLoaded;
@property(nonatomic, weak) UIViewController *parentViewController;
@property(nonatomic, strong) UIViewController *presentedViewController;
@property(nonatomic, assign, getter=isBeingDismissed) BOOL beingDismissed;
@end
@interface UINavigationController : UIViewController
@property(nonatomic, strong) UIViewController *topViewController;
@end
@interface UITabBarController : UIViewController
@property(nonatomic, strong) UIViewController *selectedViewController;
@end
typedef NS_ENUM(NSInteger, UIApplicationState) { UIApplicationStateActive, UIApplicationStateInactive };
@interface UIApplication : NSObject
@property(nonatomic, assign) UIApplicationState applicationState;
+ (instancetype)sharedApplication;
@end
