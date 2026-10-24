#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 按任务真正完成的时机释放并发名额，不为异步下载阻塞工作线程。
@interface DYYYDownloadScheduler : NSObject
- (instancetype)initWithMaximumConcurrentDownloads:(NSUInteger)maximum;
- (void)enqueueTask:(NSURLSessionTask *)task;
- (void)completeTask:(NSURLSessionTask *)task;
- (void)cancelAllTasks;
@end

NS_ASSUME_NONNULL_END
