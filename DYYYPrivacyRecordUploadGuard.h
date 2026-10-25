#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface DYYYPrivacyRecordUploadGuard : NSObject

+ (BOOL)isProfileVisitRecordUploadDisabled;
+ (BOOL)isAwemeViewRecordUploadDisabled;
+ (BOOL)shouldBlockURLString:(nullable NSString *)URLString;
+ (BOOL)shouldBlockRequestObject:(nullable id)requestObject;
+ (BOOL)shouldBlockAwemeViewRecordURLString:(nullable NSString *)URLString;
+ (BOOL)markTaskForBlockingIfNeeded:(nullable id)task requestObject:(nullable id)requestObject;
+ (BOOL)isTaskMarkedForBlocking:(nullable id)task;
+ (BOOL)cancelTaskIfPossible:(nullable id)task;
+ (void)invokeCancelledCompletionIfPossible:(nullable id)completion;

@end

NS_ASSUME_NONNULL_END
