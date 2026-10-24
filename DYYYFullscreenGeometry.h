#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

/// 无 UIKit 状态的几何计算，可在宿主机直接验证。
@interface DYYYFullscreenGeometry : NSObject
+ (CGRect)translateRect:(CGRect)rect fromReference:(CGRect)previous toReference:(CGRect)current;
+ (CGRect)aspectFit:(CGSize)media inRect:(CGRect)viewport;
+ (CGRect)unoccludedViewport:(CGRect)viewport top:(CGFloat)top panel:(CGRect)panel gap:(CGFloat)gap;
@end
