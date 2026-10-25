#import "AwemeHeaders.h"
#import "DYYYPrivacyRecordUploadGuard.h"

// 抖音 39.1.0 访问他人主页时会由详情组件直接上传访客记录
%hook AWEProfileUserDetailComponent

- (void)reportUserDetailVisitIfNeeded:(id)user {
    if ([DYYYPrivacyRecordUploadGuard isProfileVisitRecordUploadDisabled]) {
        return;
    }

    %orig;
}

%end

// 兼容旧版访客记录上传路径
%hook AWEProfileRecordHelper

+ (void)postProfileRecordWithParams:(id)params {
    if ([DYYYPrivacyRecordUploadGuard isProfileVisitRecordUploadDisabled]) {
        return;
    }

    %orig;
}

+ (void)postProfileRecordWithParams:(id)params completionBlock:(id)completionBlock {
    if ([DYYYPrivacyRecordUploadGuard isProfileVisitRecordUploadDisabled]) {
        return;
    }

    %orig;
}

+ (void)postProfileRecordWithKey:(id)key valueDic:(id)valueDic {
    if ([DYYYPrivacyRecordUploadGuard isProfileVisitRecordUploadDisabled]) {
        return;
    }

    %orig;
}

+ (void)postProfileRecordWithKey:(id)key valueDic:(id)valueDic completionBlock:(id)completionBlock {
    if ([DYYYPrivacyRecordUploadGuard isProfileVisitRecordUploadDisabled]) {
        return;
    }

    %orig;
}

%end

// 抖音 39.7.0：作品浏览记录由 AFDPlayerAndInteractionService 上报至
// /aweme/v1/familiar/video/stats/（scene 常见值 FeedVideoViewedDedicatedStats）
%hook AFDPlayerAndInteractionService

- (void)statisticsVideoViewedWithID:(NSString *)itemID scene:(NSString *)scene {
    if ([DYYYPrivacyRecordUploadGuard isAwemeViewRecordUploadDisabled]) {
        return;
    }

    %orig;
}

- (void)statisticsVideoViewedWithID:(NSString *)itemID
                           authorID:(NSString *)authorID
                       followStatus:(long long)followStatus
                     followerStatus:(long long)followerStatus
                            isStory:(BOOL)isStory
                  isRequestDirectly:(BOOL)isRequestDirectly
                              scene:(NSString *)scene {
    if ([DYYYPrivacyRecordUploadGuard isAwemeViewRecordUploadDisabled]) {
        return;
    }

    %orig;
}

%end

static BOOL DYYYTryBlockPrivacyNetworkRequest(NSString *URLString, id completion) {
    if (![DYYYPrivacyRecordUploadGuard shouldBlockURLString:URLString]) {
        return NO;
    }

    [DYYYPrivacyRecordUploadGuard invokeCancelledCompletionIfPossible:completion];
    return YES;
}

%hook AWENetworkService

+ (id)postWithURLString:(NSString *)URLString params:(id)params completion:(id)completion {
    if (DYYYTryBlockPrivacyNetworkRequest(URLString, completion)) {
        return nil;
    }
    return %orig;
}

+ (id)getWithURLString:(NSString *)URLString params:(id)params completion:(id)completion {
    if (DYYYTryBlockPrivacyNetworkRequest(URLString, completion)) {
        return nil;
    }
    return %orig;
}

+ (id)requestWithURLString:(NSString *)URLString params:(id)params method:(id)method completion:(id)completion {
    if (DYYYTryBlockPrivacyNetworkRequest(URLString, completion)) {
        return nil;
    }
    return %orig;
}

+ (id)postWithURLString:(NSString *)URLString params:(id)params headerField:(id)headerField completion:(id)completion {
    if (DYYYTryBlockPrivacyNetworkRequest(URLString, completion)) {
        return nil;
    }
    return %orig;
}

+ (id)getWithURLString:(NSString *)URLString params:(id)params headerField:(id)headerField completion:(id)completion {
    if (DYYYTryBlockPrivacyNetworkRequest(URLString, completion)) {
        return nil;
    }
    return %orig;
}

%end

%hook TTNetworkManager

- (id)requestForJSONWithURL:(NSString *)url
                     params:(id)params
                     method:(NSString *)method
           needCommonParams:(BOOL)needCommonParams
                headerField:(id)headerField
          requestSerializer:(Class)requestSerializerClass
         responseSerializer:(Class)responseSerializerClass
                 autoResume:(BOOL)autoResume
                   callback:(id)callback {
    if (DYYYTryBlockPrivacyNetworkRequest(url, callback)) {
        return nil;
    }
    return %orig;
}

- (id)requestForJSONWithResponse:(NSString *)url
                          params:(id)params
                          method:(NSString *)method
                needCommonParams:(BOOL)needCommonParams
                     headerField:(id)headerField
               requestSerializer:(Class)requestSerializerClass
              responseSerializer:(Class)responseSerializerClass
                      autoResume:(BOOL)autoResume
                        callback:(id)callback {
    if (DYYYTryBlockPrivacyNetworkRequest(url, callback)) {
        return nil;
    }
    return %orig;
}

- (id)requestForBinaryWithResponse:(NSString *)url
                            params:(id)params
                            method:(NSString *)method
                  needCommonParams:(BOOL)needCommonParams
                       headerField:(id)headerField
                          callback:(id)callback {
    if (DYYYTryBlockPrivacyNetworkRequest(url, callback)) {
        return nil;
    }
    return %orig;
}

%end

static BOOL DYYYShouldSkipPrivacyRecordTaskStart(id task) {
    BOOL shouldBlock = [DYYYPrivacyRecordUploadGuard isTaskMarkedForBlocking:task] ||
                       [DYYYPrivacyRecordUploadGuard shouldBlockRequestObject:task];
    if (!shouldBlock) {
        return NO;
    }

    // 即使任务对象不支持 cancel，也必须阻止原始启动，避免隐私请求继续发出。
    (void)[DYYYPrivacyRecordUploadGuard cancelTaskIfPossible:task];
    return YES;
}

%hook TTHttpTask

- (void)resume {
    if (DYYYShouldSkipPrivacyRecordTaskStart(self)) {
        return;
    }

    %orig;
}

%end

%hook TTHttpTaskChromium

- (void)runRequestFiltersAndStart {
    if (DYYYShouldSkipPrivacyRecordTaskStart(self)) {
        return;
    }

    %orig;
}

- (void)resume {
    if (DYYYShouldSkipPrivacyRecordTaskStart(self)) {
        return;
    }

    %orig;
}

%end

%hook TTConcurrentHttpTask

- (void)resume {
    if (DYYYShouldSkipPrivacyRecordTaskStart(self)) {
        return;
    }

    %orig;
}

%end

%hook NSURLSessionTask

- (void)resume {
    if (DYYYShouldSkipPrivacyRecordTaskStart(self)) {
        return;
    }

    %orig;
}

%end

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url {
    NSURLSessionDataTask *task = %orig;
    [DYYYPrivacyRecordUploadGuard markTaskForBlockingIfNeeded:task requestObject:url];
    return task;
}

- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    NSURLSessionDataTask *task = %orig;
    [DYYYPrivacyRecordUploadGuard markTaskForBlockingIfNeeded:task requestObject:url];
    return task;
}

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    NSURLSessionDataTask *task = %orig;
    [DYYYPrivacyRecordUploadGuard markTaskForBlockingIfNeeded:task requestObject:request];
    return task;
}

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    NSURLSessionDataTask *task = %orig;
    [DYYYPrivacyRecordUploadGuard markTaskForBlockingIfNeeded:task requestObject:request];
    return task;
}

- (NSURLSessionDownloadTask *)downloadTaskWithURL:(NSURL *)url {
    NSURLSessionDownloadTask *task = %orig;
    [DYYYPrivacyRecordUploadGuard markTaskForBlockingIfNeeded:task requestObject:url];
    return task;
}

- (NSURLSessionDownloadTask *)downloadTaskWithURL:(NSURL *)url completionHandler:(void (^)(NSURL *location, NSURLResponse *response, NSError *error))completionHandler {
    NSURLSessionDownloadTask *task = %orig;
    [DYYYPrivacyRecordUploadGuard markTaskForBlockingIfNeeded:task requestObject:url];
    return task;
}

- (NSURLSessionDownloadTask *)downloadTaskWithRequest:(NSURLRequest *)request {
    NSURLSessionDownloadTask *task = %orig;
    [DYYYPrivacyRecordUploadGuard markTaskForBlockingIfNeeded:task requestObject:request];
    return task;
}

- (NSURLSessionDownloadTask *)downloadTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURL *location, NSURLResponse *response, NSError *error))completionHandler {
    NSURLSessionDownloadTask *task = %orig;
    [DYYYPrivacyRecordUploadGuard markTaskForBlockingIfNeeded:task requestObject:request];
    return task;
}

- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request fromData:(NSData *)bodyData {
    NSURLSessionUploadTask *task = %orig;
    [DYYYPrivacyRecordUploadGuard markTaskForBlockingIfNeeded:task requestObject:request];
    return task;
}

- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request fromData:(NSData *)bodyData completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    NSURLSessionUploadTask *task = %orig;
    [DYYYPrivacyRecordUploadGuard markTaskForBlockingIfNeeded:task requestObject:request];
    return task;
}

- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request fromFile:(NSURL *)fileURL {
    NSURLSessionUploadTask *task = %orig;
    [DYYYPrivacyRecordUploadGuard markTaskForBlockingIfNeeded:task requestObject:request];
    return task;
}

- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request fromFile:(NSURL *)fileURL completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    NSURLSessionUploadTask *task = %orig;
    [DYYYPrivacyRecordUploadGuard markTaskForBlockingIfNeeded:task requestObject:request];
    return task;
}

- (NSURLSessionUploadTask *)uploadTaskWithStreamedRequest:(NSURLRequest *)request {
    NSURLSessionUploadTask *task = %orig;
    [DYYYPrivacyRecordUploadGuard markTaskForBlockingIfNeeded:task requestObject:request];
    return task;
}

%end

