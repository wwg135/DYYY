#import "DYYYDownloadScheduler.h"

@interface DYYYDownloadScheduler ()
@property(nonatomic, assign) NSUInteger maximum;
@property(nonatomic, strong) NSMutableArray<NSURLSessionTask *> *pendingTasks;
@property(nonatomic, strong) NSMutableSet<NSURLSessionTask *> *activeTasks;
@end

@implementation DYYYDownloadScheduler

#pragma mark - 下载调度

- (instancetype)initWithMaximumConcurrentDownloads:(NSUInteger)maximum {
    self = [super init];
    if (self) {
        _maximum = MAX(1, maximum);
        _pendingTasks = [NSMutableArray array];
        _activeTasks = [NSMutableSet set];
    }
    return self;
}

- (void)startPendingTasksLocked {
    while (self.activeTasks.count < self.maximum && self.pendingTasks.count > 0) {
        NSURLSessionTask *task = self.pendingTasks.firstObject;
        [self.pendingTasks removeObjectAtIndex:0];
        if (task.state == NSURLSessionTaskStateCanceling || task.state == NSURLSessionTaskStateCompleted) continue;
        [self.activeTasks addObject:task];
        [task resume];
    }
}

- (void)enqueueTask:(NSURLSessionTask *)task {
    if (!task) return;
    @synchronized(self) {
        if ([self.activeTasks containsObject:task] || [self.pendingTasks containsObject:task]) return;
        [self.pendingTasks addObject:task];
        [self startPendingTasksLocked];
    }
}

- (void)completeTask:(NSURLSessionTask *)task {
    if (!task) return;
    @synchronized(self) {
        [self.pendingTasks removeObject:task];
        [self.activeTasks removeObject:task];
        [self startPendingTasksLocked];
    }
}

- (void)cancelAllTasks {
    @synchronized(self) {
        NSArray<NSURLSessionTask *> *tasks = [self.activeTasks.allObjects arrayByAddingObjectsFromArray:self.pendingTasks];
        // 活跃任务收到终止回调后才释放名额，避免取消期间又超额启动下载。
        [self.pendingTasks removeAllObjects];
        for (NSURLSessionTask *task in tasks) [task cancel];
    }
}

@end
