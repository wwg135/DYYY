#import "AWMSafeDispatchTimer.h"
#import "DYYYDownloadScheduler.h"
#import <assert.h>

@interface DYYYTestDownloadTask : NSObject
@property(nonatomic, assign) NSURLSessionTaskState state;
@property(nonatomic, assign) NSUInteger resumes;
@property(nonatomic, assign) NSUInteger cancels;
- (void)resume;
- (void)cancel;
@end

@implementation DYYYTestDownloadTask
- (instancetype)init {
    if ((self = [super init])) _state = NSURLSessionTaskStateSuspended;
    return self;
}
- (void)resume { self.resumes++; self.state = NSURLSessionTaskStateRunning; }
- (void)cancel { self.cancels++; self.state = NSURLSessionTaskStateCanceling; }
@end

@interface DYYYCancellationProbe : NSObject <NSURLSessionTaskDelegate>
@property(nonatomic, strong) NSMutableArray<NSError *> *errors;
@end
@implementation DYYYCancellationProbe
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    @synchronized(self) { [self.errors addObject:error ?: [NSError errorWithDomain:@"UnexpectedSuccess" code:0 userInfo:nil]]; }
}
@end

int main(void) {
    @autoreleasepool {
        // 未启动、运行中、取消后的析构都不能再次异步访问已释放对象。
        for (NSUInteger index = 0; index < 100; index++) {
            __weak AWMSafeDispatchTimer *released;
            @autoreleasepool {
                AWMSafeDispatchTimer *timer = [[AWMSafeDispatchTimer alloc] init];
                released = timer;
                if (index % 3) {
                    [timer startWithInterval:10 leeway:0.1 queue:dispatch_get_main_queue() repeats:YES handler:^{ assert(!"已释放定时器不能触发回调"); }];
                    assert(timer.running);
                }
                if (index % 3 == 2) { [timer cancel]; assert(!timer.running); }
            }
            assert(released == nil);
        }
        __block NSUInteger ticks = 0;
        AWMSafeDispatchTimer *timer = [[AWMSafeDispatchTimer alloc] init];
        [timer startWithInterval:0.01 leeway:0.001 queue:dispatch_get_main_queue() repeats:YES handler:^{ ticks++; }];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
        while (ticks < 2 && deadline.timeIntervalSinceNow > 0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        assert(ticks >= 2);
        [timer cancel];
        assert(!timer.running);
        NSUInteger stoppedAt = ticks;
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.03]];
        assert(ticks == stoppedAt);

        DYYYDownloadScheduler *scheduler = [[DYYYDownloadScheduler alloc] initWithMaximumConcurrentDownloads:3];
        NSMutableArray<DYYYTestDownloadTask *> *tasks = [NSMutableArray array];
        for (NSUInteger index = 0; index < 12; index++) {
            DYYYTestDownloadTask *task = [DYYYTestDownloadTask new];
            [tasks addObject:task];
            [scheduler enqueueTask:(NSURLSessionTask *)task];
            assert(task.resumes == (index < 3 ? 1 : 0));
        }
        [scheduler enqueueTask:(NSURLSessionTask *)tasks[0]];
        assert(tasks[0].resumes == 1);
        tasks[1].state = NSURLSessionTaskStateCompleted;
        [scheduler completeTask:(NSURLSessionTask *)tasks[1]];
        assert(tasks[3].resumes == 1 && tasks[4].resumes == 0);
        [scheduler completeTask:(NSURLSessionTask *)tasks[1]];
        assert(tasks[4].resumes == 0); // 重复终止不能多释放并发名额。
        [scheduler cancelAllTasks];
        for (DYYYTestDownloadTask *task in tasks) assert(task.cancels == (task == tasks[1] ? 0 : 1));
        DYYYTestDownloadTask *next = [DYYYTestDownloadTask new];
        [scheduler enqueueTask:(NSURLSessionTask *)next];
        assert(next.resumes == 0); // 活跃的取消任务尚未终止，名额不能提前复用。
        [scheduler completeTask:(NSURLSessionTask *)tasks[0]];
        assert(next.resumes == 1);
        [scheduler completeTask:(NSURLSessionTask *)tasks[0]];
        assert(next.resumes == 1);
        for (NSUInteger index = 4; index < tasks.count; index++) assert(tasks[index].resumes == 0);
        [scheduler cancelAllTasks];

        // 真实 NSURLSession 的等待任务在 resume 前取消，也必须给出终止回调。
        DYYYCancellationProbe *probe = [DYYYCancellationProbe new];
        probe.errors = [NSMutableArray array];
        NSURLSession *session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.ephemeralSessionConfiguration delegate:probe delegateQueue:nil];
        for (NSUInteger index = 0; index < 5; index++) {
            NSURLSessionDownloadTask *task = [session downloadTaskWithURL:[NSURL URLWithString:@"http://127.0.0.1:1/never-started"]];
            [task cancel];
        }
        deadline = [NSDate dateWithTimeIntervalSinceNow:3];
        while (deadline.timeIntervalSinceNow > 0) {
            @synchronized(probe) { if (probe.errors.count == 5) break; }
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }
        @synchronized(probe) {
            assert(probe.errors.count == 5);
            for (NSError *error in probe.errors) assert(error.code == NSURLErrorCancelled);
        }
        [session finishTasksAndInvalidate];
        puts("Async resources: timer lifetime/cancel, download limit/FIFO/cancel, queued NSURLSession cancellation passed");
    }
    return 0;
}
