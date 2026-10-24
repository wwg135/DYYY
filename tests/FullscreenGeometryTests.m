#import "DYYYFullscreenGeometry.h"
#import <assert.h>
#import <math.h>

int main(void) {
    @autoreleasepool {
        CGRect viewport = CGRectMake(0, 0, 414, 896);
        CGRect info = [DYYYFullscreenGeometry unoccludedViewport:viewport top:0 panel:CGRectMake(0,827,414,69) gap:0];
        assert(fabs(info.size.height - 827) < 0.0001);
        // 滚动中的 Feed 页也保持同一互动层高度，不随窗口平移缩放。
        for (NSNumber *offset in @[@(-896), @(-300), @0, @300, @896]) {
            CGFloat pageY = offset.doubleValue;
            CGRect moving = CGRectOffset(viewport, 0, pageY);
            CGRect normalized = CGRectOffset(moving, 0, -pageY);
            CGRect clipped = [DYYYFullscreenGeometry unoccludedViewport:normalized top:0 panel:CGRectMake(0,827,414,69) gap:0];
            CGRect local = CGRectOffset(CGRectOffset(clipped, 0, pageY), 0, -pageY);
            assert(CGRectEqualToRect(local, info));
        }
        assert(CGRectEqualToRect(viewport, [DYYYFullscreenGeometry unoccludedViewport:viewport top:0 panel:CGRectNull gap:0]));
        // 真机回归：预加载阶段 y=881.5，切为当前页后开评论不得沿用旧窗口 y。
        for (NSNumber *offset in @[@(-896), @(-300), @0, @300, @881.5, @896]) {
            CGRect previous = CGRectOffset(viewport, 0, offset.doubleValue);
            assert(CGRectEqualToRect(viewport, [DYYYFullscreenGeometry translateRect:previous fromReference:previous toReference:viewport]));
            CGRect landscape = CGRectMake(0, offset.doubleValue + 267, 414, 232.875);
            CGRect translated = [DYYYFullscreenGeometry translateRect:landscape fromReference:previous toReference:viewport];
            assert(CGRectEqualToRect(translated, CGRectMake(0, 267, 414, 232.875)));
        }
        assert(CGRectIsNull([DYYYFullscreenGeometry translateRect:viewport fromReference:CGRectNull toReference:viewport]));
        CGRect panel = CGRectMake(0, 286.72, 414, 609.28);
        CGRect free = [DYYYFullscreenGeometry unoccludedViewport:viewport top:88 panel:panel gap:8];
        CGRect media = [DYYYFullscreenGeometry aspectFit:CGSizeMake(1920,1080) inRect:free];
        assert(CGRectGetMinY(media) >= 88);
        assert(CGRectGetMaxY(media) <= 278.72 + 0.0001);
        assert(fabs(media.size.width / media.size.height - 16.0 / 9.0) < 0.00001);
        // 重复计算、不同父坐标系及评论拖动不累积位移。
        for (int i = 0; i < 100; i++) assert(CGRectEqualToRect(media, [DYYYFullscreenGeometry aspectFit:CGSizeMake(1920,1080) inRect:free]));
        for (double top = 180; top < 850; top += 17) {
            CGRect dragged = CGRectMake(0,top,414,896-top);
            CGRect available = [DYYYFullscreenGeometry unoccludedViewport:viewport top:88 panel:dragged gap:8];
            CGRect fitted = [DYYYFullscreenGeometry aspectFit:CGSizeMake(1920,1080) inRect:available];
            assert(CGRectGetMaxY(fitted) <= top - 8 + 0.0001);
        }
        CGRect portrait = [DYYYFullscreenGeometry aspectFit:CGSizeMake(1080,1920) inRect:free];
        assert(CGRectContainsRect(free, portrait));
        // 真机铺满竖屏视频：渲染比例 414:896，和视频源的 9:16 不同。
        CGRect filledPortrait = [DYYYFullscreenGeometry aspectFit:CGSizeMake(414,896) inRect:free];
        assert(CGRectContainsRect(free, filledPortrait));
        assert(fabs(filledPortrait.size.width / filledPortrait.size.height - 414.0 / 896.0) < 0.00001);
        assert(CGRectIsNull([DYYYFullscreenGeometry aspectFit:CGSizeZero inRect:free]));
        assert(CGRectIsNull([DYYYFullscreenGeometry unoccludedViewport:viewport top:300 panel:panel gap:8]));
        CGRect full = [DYYYFullscreenGeometry unoccludedViewport:viewport top:0 panel:CGRectNull gap:8];
        assert(CGRectEqualToRect(full, viewport));
        puts("Fullscreen geometry: fit, page-cache translation, panel drag, idempotence and invalid input passed");
    }
}
