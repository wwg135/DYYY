#import "DYYYFullscreenGeometry.h"
#import <math.h>

@implementation DYYYFullscreenGeometry
+ (CGRect)translateRect:(CGRect)rect fromReference:(CGRect)previous toReference:(CGRect)current {
    if (CGRectIsNull(rect) || CGRectIsInfinite(rect) || CGRectIsEmpty(previous) || CGRectIsInfinite(previous) ||
        CGRectIsEmpty(current) || CGRectIsInfinite(current) ||
        fabs(previous.size.width - current.size.width) > 0.5 || fabs(previous.size.height - current.size.height) > 0.5) return CGRectNull;
    // 基准来自稳定的 Feed cell，只抵消翻页位移，不继承评论内部宿主的缩放。
    return CGRectOffset(rect, current.origin.x - previous.origin.x, current.origin.y - previous.origin.y);
}
+ (CGRect)aspectFit:(CGSize)media inRect:(CGRect)viewport {
    if (!isfinite(media.width) || !isfinite(media.height) || media.width <= 0 || media.height <= 0 ||
        CGRectIsEmpty(viewport) || CGRectIsNull(viewport)) return CGRectNull;
    CGFloat scale = MIN(viewport.size.width / media.width, viewport.size.height / media.height);
    CGSize size = CGSizeMake(media.width * scale, media.height * scale);
    return CGRectMake(CGRectGetMidX(viewport) - size.width / 2, CGRectGetMidY(viewport) - size.height / 2, size.width, size.height);
}
+ (CGAffineTransform)aspectFitTransformForBounds:(CGRect)bounds contentRect:(CGRect)content center:(CGPoint)center inRect:(CGRect)viewport {
    CGRect fit = [self aspectFit:content.size inRect:viewport];
    if (CGRectIsNull(fit)) return CGAffineTransformIdentity;
    CGFloat scale = fit.size.width / content.size.width;
    return CGAffineTransformMake(scale, 0, 0, scale,
                                 CGRectGetMidX(fit) - center.x - (CGRectGetMidX(content) - CGRectGetMidX(bounds)) * scale,
                                 CGRectGetMidY(fit) - center.y - (CGRectGetMidY(content) - CGRectGetMidY(bounds)) * scale);
}
+ (CGRect)unoccludedViewport:(CGRect)viewport top:(CGFloat)top panel:(CGRect)panel gap:(CGFloat)gap {
    CGFloat bottom = CGRectGetMaxY(viewport);
    top = MAX(top, CGRectGetMinY(viewport));
    if (!CGRectIsNull(panel) && CGRectIntersectsRect(viewport, panel)) bottom = MIN(bottom, CGRectGetMinY(panel) - gap);
    if (bottom <= top) return CGRectNull;
    return CGRectMake(viewport.origin.x, top, viewport.size.width, bottom - top);
}

@end
