#import "DYYYManager.h"
#import <CoreAudioTypes/CoreAudioTypes.h>
#import <CoreMedia/CMMetadata.h>
#import <ImageIO/ImageIO.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <MobileCoreServices/UTCoreTypes.h>
#import <Photos/Photos.h>
#import <objc/runtime.h>

#import "DYYYToast.h"
#import "DYYYUtils.h"
#import "DYYYDownloadScheduler.h"
#import "DYYYConstants.h"


@interface DYYYManager () <NSURLSessionDownloadDelegate>
@property(nonatomic, copy) NSString *pendingAlbumDescription;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *albumDescriptionMap;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSURLSessionDownloadTask *> *downloadTasks;
@property(nonatomic, strong) NSMutableDictionary<NSString *, DYYYToast *> *progressViews;
@property(nonatomic, strong) DYYYDownloadScheduler *downloadScheduler;
@property(nonatomic, strong) NSURLSession *downloadSession;
@property(nonatomic, strong) NSOperationQueue *downloadDelegateQueue;
@property(nonatomic, strong) dispatch_queue_t mediaProcessingQueue;
@property(nonatomic, strong) NSMutableArray<void (^)(dispatch_block_t)> *mediaJobs;
@property(nonatomic, assign) BOOL mediaJobActive;
@property(nonatomic, strong) NSMutableDictionary<NSString *, void (^)(BOOL, NSURL *)> *transferCompletionBlocks;
@property(nonatomic, strong) NSMutableDictionary<NSString *, void (^)(float)> *transferProgressBlocks;
@property(nonatomic, strong) NSMutableDictionary<NSString *, dispatch_block_t> *cancellationHandlers;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *taskProgressMap;
@property(nonatomic, strong) NSMutableDictionary<NSString *, void (^)(BOOL success, NSURL *fileURL)> *completionBlocks;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *mediaTypeMap;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *filePathToDownloadID;

// 批量下载相关属性
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *downloadToBatchMap;                                                 // 下载ID到批量ID的映射
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *batchCompletedCountMap;                                             // 批量ID到已完成数量的映射
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *batchSuccessCountMap;                                               // 批量ID到成功数量的映射
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *batchTotalCountMap;                                                 // 批量ID到总数量的映射
@property(nonatomic, strong) NSMutableDictionary<NSString *, void (^)(NSInteger current, NSInteger total)> *batchProgressBlocks;              // 批量进度回调
@property(nonatomic, strong) NSMutableDictionary<NSString *, void (^)(NSInteger successCount, NSInteger totalCount)> *batchCompletionBlocks;  // 批量完成回调
@end

@implementation DYYYManager
+ (void)saveMedia:(NSURL *)mediaURL mediaType:(MediaType)mediaType albumDescription:(NSString *)albumDescription completion:(void (^)(BOOL success))completion {
    if (mediaType == MediaTypeAudio) {
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
              completion(NO);
            });
        }
        return;
    }

    [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
      if (status != PHAuthorizationStatusAuthorized) {
          dispatch_async(dispatch_get_main_queue(), ^{
            [DYYYUtils showToast:@"请允许访问相册权限后重试"];
            [[NSFileManager defaultManager] removeItemAtPath:mediaURL.path error:nil];
            [[DYYYManager shared] finalizeDownloadWithFileURL:mediaURL success:NO];
            if (completion) {
                completion(NO);
            }
          });
          return;
      }

      void (^reportResult)(BOOL) = ^(BOOL success) {
          dispatch_async(dispatch_get_main_queue(), ^{
            [[DYYYManager shared] finalizeDownloadWithFileURL:mediaURL success:success];
            if (completion) {
                completion(success);
            }
          });
      };

      if (mediaType == MediaTypeHeic) {
          NSString *actualFormat = [DYYYUtils detectFileFormat:mediaURL];

          if ([actualFormat isEqualToString:@"webp"]) {
              [DYYYUtils convertWebpToGifSafely:mediaURL
                                     completion:^(NSURL *gifURL, BOOL success) {
                                  if (success && gifURL) {
                                      [DYYYUtils saveGifToPhotoLibrary:gifURL
                                                            completion:^(BOOL gifSuccess) {
                                                         [[NSFileManager defaultManager] removeItemAtPath:mediaURL.path error:nil];
                                                         reportResult(gifSuccess);
                                                       }];
                                  } else {
                                      dispatch_async(dispatch_get_main_queue(), ^{
                                        [DYYYUtils showToast:@"转换失败"];
                                        [[NSFileManager defaultManager] removeItemAtPath:mediaURL.path error:nil];
                                        reportResult(NO);
                                      });
                                  }
                                }];
              return;
          }

          if ([actualFormat isEqualToString:@"heic"] || [actualFormat isEqualToString:@"heif"]) {
              [DYYYUtils convertHeicToGif:mediaURL
                               completion:^(NSURL *gifURL, BOOL success) {
                            if (success && gifURL) {
                                [DYYYUtils saveGifToPhotoLibrary:gifURL
                                                      completion:^(BOOL gifSuccess) {
                                                   [[NSFileManager defaultManager] removeItemAtPath:mediaURL.path error:nil];
                                                   reportResult(gifSuccess);
                                                 }];
                            } else {
                                dispatch_async(dispatch_get_main_queue(), ^{
                                  [DYYYUtils showToast:@"转换失败"];
                                  [[NSFileManager defaultManager] removeItemAtPath:mediaURL.path error:nil];
                                  reportResult(NO);
                                });
                            }
                          }];
              return;
          }

          if ([actualFormat isEqualToString:@"gif"]) {
              [DYYYUtils saveGifToPhotoLibrary:mediaURL
                                    completion:^(BOOL gifSuccess) {
                                 reportResult(gifSuccess);
                               }];
              return;
          }

          [[PHPhotoLibrary sharedPhotoLibrary]
              performChanges:^{
                UIImage *image = [UIImage imageWithContentsOfFile:mediaURL.path];
                if (image) {
                    [PHAssetChangeRequest creationRequestForAssetFromImage:image];
                }
              }
              completionHandler:^(BOOL success, NSError *_Nullable error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                  if (!success) {
                      [DYYYUtils showToast:@"保存失败"];
                  }
                  [[NSFileManager defaultManager] removeItemAtPath:mediaURL.path error:nil];
                  reportResult(success);
                });
              }];
          return;
      }

      if (albumDescription.length == 0) {
          [self createAssetAtURL:mediaURL mediaType:mediaType originalURL:mediaURL temporaryURL:nil reportResult:reportResult];
          return;
      }

      // 相册里能显示的说明只能来自文件自身的元数据，PhotoKit 没有建完资产再补说明的接口，
      // 所以先写一份带说明的副本，用副本建资产。写不成就用原件，宁可没说明也要存进相册。
      if (mediaType == MediaTypeVideo) {
          [DYYYUtils writeDescription:albumDescription
                    toVideoAtURL:mediaURL
                      completion:^(NSURL *decoratedURL) {
                        NSURL *assetURL = decoratedURL ?: mediaURL;
                        [self createAssetAtURL:assetURL mediaType:mediaType originalURL:mediaURL temporaryURL:decoratedURL reportResult:reportResult];
                      }];
          return;
      }

      NSURL *decoratedURL = [DYYYUtils temporaryImageURLByEmbeddingDescription:albumDescription intoImageAtURL:mediaURL];
      NSURL *assetURL = decoratedURL ?: mediaURL;
      [self createAssetAtURL:assetURL mediaType:mediaType originalURL:mediaURL temporaryURL:decoratedURL reportResult:reportResult];
    }];
}

+ (void)createAssetAtURL:(NSURL *)assetURL
               mediaType:(MediaType)mediaType
             originalURL:(NSURL *)originalURL
            temporaryURL:(NSURL *)temporaryURL
            reportResult:(void (^)(BOOL success))reportResult {
    [[PHPhotoLibrary sharedPhotoLibrary]
        performChanges:^{
          // 按文件原样入库，文件里嵌好的说明才能留住；从 UIImage 建资产会重新编码并丢掉元数据。
          PHAssetCreationRequest *request = [PHAssetCreationRequest creationRequestForAsset];
          PHAssetResourceType resourceType = (mediaType == MediaTypeVideo) ? PHAssetResourceTypeVideo : PHAssetResourceTypePhoto;
          [request addResourceWithType:resourceType fileURL:assetURL options:nil];
        }
        completionHandler:^(BOOL success, NSError *_Nullable error) {
          if (!success && mediaType != MediaTypeVideo) {
              // 少数图片的实际编码与扩展名不符，按文件入库会被 PhotoKit 拒；退回解码后再存。
              UIImage *image = [UIImage imageWithContentsOfFile:assetURL.path];
              if (image) {
                  [[PHPhotoLibrary sharedPhotoLibrary]
                      performChanges:^{
                        [PHAssetChangeRequest creationRequestForAssetFromImage:image];
                      }
                      completionHandler:^(BOOL retrySuccess, NSError *_Nullable retryError) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                          if (!retrySuccess) {
                              [DYYYUtils showToast:@"保存失败"];
                          }
                          if (temporaryURL) {
                              [[NSFileManager defaultManager] removeItemAtPath:temporaryURL.path error:nil];
                          }
                          [[NSFileManager defaultManager] removeItemAtPath:originalURL.path error:nil];
                          reportResult(retrySuccess);
                        });
                      }];
                  return;
              }
          }

          dispatch_async(dispatch_get_main_queue(), ^{
            if (!success) {
                [DYYYUtils showToast:@"保存失败"];
            }
            if (temporaryURL) {
                [[NSFileManager defaultManager] removeItemAtPath:temporaryURL.path error:nil];
            }
            [[NSFileManager defaultManager] removeItemAtPath:originalURL.path error:nil];
            reportResult(success);
          });
        }];
}


+ (NSString *)albumDescriptionForAwemeModel:(AWEAwemeModel *)model {
    if (!model) return nil;
    return [DYYYUtils albumDescriptionForAwemeModel:model authorProfileURL:[DYYYUtils authorProfileURL:model.author] workURL:[DYYYUtils compactAlbumURL:model.shareURL]];
}

+ (void)setAlbumDescriptionContextWithAwemeModel:(AWEAwemeModel *)model {
    DYYYManager *manager = self.shared;
    NSString *description = DYYYGetBool(DYYY_ALBUM_MEDIA_DESCRIPTION_KEY) ? [self albumDescriptionForAwemeModel:model] : nil;
    @synchronized (manager) { manager.pendingAlbumDescription = description; }
}

+ (NSString *)currentAlbumDescription {
    if (!DYYYGetBool(DYYY_ALBUM_MEDIA_DESCRIPTION_KEY)) return nil;
    DYYYManager *manager = self.shared;
    @synchronized (manager) { return manager.pendingAlbumDescription; }
}



+ (instancetype)shared {
    static DYYYManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _fileLinks = [NSMutableDictionary dictionary];
        _albumDescriptionMap = [NSMutableDictionary dictionary];
        _downloadTasks = [NSMutableDictionary dictionary];
        _progressViews = [NSMutableDictionary dictionary];
        _downloadScheduler = [[DYYYDownloadScheduler alloc] initWithMaximumConcurrentDownloads:3];
        _downloadDelegateQueue = [[NSOperationQueue alloc] init];
        _downloadDelegateQueue.maxConcurrentOperationCount = 1;
        _downloadDelegateQueue.qualityOfService = NSQualityOfServiceUtility;
        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
        configuration.HTTPMaximumConnectionsPerHost = 3;
        configuration.timeoutIntervalForRequest = 60;
        configuration.timeoutIntervalForResource = 300;
        _downloadSession = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:_downloadDelegateQueue];
        _mediaProcessingQueue = dispatch_queue_create("com.dyyy.media.processing", DISPATCH_QUEUE_SERIAL);
        _mediaJobs = [NSMutableArray array];
        _transferCompletionBlocks = [NSMutableDictionary dictionary];
        _transferProgressBlocks = [NSMutableDictionary dictionary];
        _cancellationHandlers = [NSMutableDictionary dictionary];
        _taskProgressMap = [NSMutableDictionary dictionary];
        _completionBlocks = [NSMutableDictionary dictionary];
        _mediaTypeMap = [NSMutableDictionary dictionary];
        _filePathToDownloadID = [NSMutableDictionary dictionary];

        // 初始化批量下载相关字典
        _downloadToBatchMap = [NSMutableDictionary dictionary];
        _batchCompletedCountMap = [NSMutableDictionary dictionary];
        _batchSuccessCountMap = [NSMutableDictionary dictionary];
        _batchTotalCountMap = [NSMutableDictionary dictionary];
        _batchProgressBlocks = [NSMutableDictionary dictionary];
        _batchCompletionBlocks = [NSMutableDictionary dictionary];
    }
    return self;
}

+ (void)saveMedia:(NSURL *)mediaURL mediaType:(MediaType)mediaType completion:(void (^)(BOOL success))completion {
    DYYYManager *manager = self.shared;
    NSString *downloadID = [manager downloadIDForFileURL:mediaURL];
    NSString *description = downloadID ? manager.albumDescriptionMap[downloadID] : [self currentAlbumDescription];
    [self saveMedia:mediaURL mediaType:mediaType albumDescription:description completion:completion];
}

#pragma mark - 单张实况照片

+ (void)downloadLivePhoto:(NSURL *)imageURL videoURL:(NSURL *)videoURL completion:(void (^)(void))completion {
    NSString *albumDescription = [self currentAlbumDescription];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!imageURL || !videoURL) {
            if (completion) completion();
            return;
        }
        DYYYManager *manager = self.shared;
        NSString *identifier = NSUUID.UUID.UUIDString;
        NSURL *imageFile = [DYYYUtils uniqueTemporaryFileURLWithFileName:@"livephoto.heic"];
        NSURL *videoFile = [DYYYUtils uniqueTemporaryFileURLWithFileName:@"livephoto.mp4"];
        NSProgress *cancellation = [NSProgress progressWithTotalUnitCount:1];
        [cancellation setUserInfoObject:albumDescription ?: @"" forKey:@"DYYYAlbumDescription"];
        DYYYToast *view = [[DYYYToast alloc] initWithFrame:UIScreen.mainScreen.bounds];
        manager.progressViews[identifier] = view;
        [view show];
        view.cancelBlock = ^{ [self cancelAllDownloads]; };
        manager.cancellationHandlers[identifier] = ^{ [cancellation cancel]; };
        void (^finish)(BOOL) = ^(BOOL success) {
            [manager.cancellationHandlers removeObjectForKey:identifier];
            [manager.progressViews removeObjectForKey:identifier];
            view.cancelBlock = nil;
            view.allowSuccessAnimation = success && !cancellation.cancelled;
            [view dismiss];
            if (!success && !cancellation.cancelled) [DYYYUtils showToast:@"保存实况照片失败"];
            if (completion) completion();
        };
        dispatch_group_t downloads = dispatch_group_create();
        __block BOOL imageReady = NO, videoReady = NO;
        __block float imageProgress = 0, videoProgress = 0;
        dispatch_group_enter(downloads);
        [manager enqueueDownloadURL:imageURL destinationURL:imageFile progress:^(float value) {
            imageProgress = value;
            if (!cancellation.cancelled) [view setProgress:(imageProgress + videoProgress) / 2];
        } completion:^(BOOL success, NSURL *fileURL) {
            imageReady = success;
            dispatch_group_leave(downloads);
        }];
        dispatch_group_enter(downloads);
        [manager enqueueDownloadURL:videoURL destinationURL:videoFile progress:^(float value) {
            videoProgress = value;
            if (!cancellation.cancelled) [view setProgress:(imageProgress + videoProgress) / 2];
        } completion:^(BOOL success, NSURL *fileURL) {
            videoReady = success;
            dispatch_group_leave(downloads);
        }];
        dispatch_group_notify(downloads, dispatch_get_main_queue(), ^{
            if (cancellation.cancelled || !imageReady || !videoReady) {
                [manager removeTemporaryFiles:@[imageFile, videoFile]];
                finish(NO);
                return;
            }
            [manager saveLivePhotoImage:imageFile video:videoFile cancellation:cancellation completion:finish];
        });
    });
}

+ (void)downloadMedia:(NSURL *)url mediaType:(MediaType)mediaType audio:(NSURL *)audioURL completion:(void (^)(BOOL success))completion {
    [self downloadMediaWithProgress:url
                          mediaType:mediaType
                              audio:audioURL
                           progress:nil
                         completion:^(BOOL success, NSURL *fileURL) {
                           void (^notifyCompletion)(BOOL) = ^(BOOL result) {
                               if (completion) {
                                   completion(result);
                               }
                           };

                           if (success) {
                               if (mediaType == MediaTypeAudio) {
                                   dispatch_async(dispatch_get_main_queue(), ^{
                                     [[DYYYManager shared] finalizeDownloadWithFileURL:fileURL success:YES];
                                     UIActivityViewController *activityVC = [[UIActivityViewController alloc] initWithActivityItems:@[ fileURL ] applicationActivities:nil];

                                     [activityVC setCompletionWithItemsHandler:^(UIActivityType _Nullable activityType, BOOL completed, NSArray *_Nullable returnedItems, NSError *_Nullable error) {
                                       dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                                         [[NSFileManager defaultManager] removeItemAtURL:fileURL error:nil];
                                       });
                                     }];
                                     UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
                                     [rootVC presentViewController:activityVC animated:YES completion:nil];
                                     notifyCompletion(YES);
                                   });
                               } else {
                                   if (mediaType == MediaTypeVideo && audioURL) {
                                       if (![DYYYUtils videoHasAudio:fileURL]) {
                                           [DYYYUtils downloadAudioAndMergeWithVideo:fileURL
                                                                            audioURL:audioURL
                                                                          completion:^(BOOL mergeSuccess, NSURL *mergedURL) {
                                                                       if (mergeSuccess) {
                                                                           [[DYYYManager shared] replaceFileURL:fileURL withFileURL:mergedURL];
                                                                           [[NSFileManager defaultManager] removeItemAtURL:fileURL error:nil];
                                                                           [self saveMedia:mergedURL
                                                                                 mediaType:mediaType
                                                                                completion:^(BOOL saveSuccess) {
                                                                                  notifyCompletion(saveSuccess);
                                                                                }];
                                                                       } else {
                                                                           [self saveMedia:fileURL
                                                                                 mediaType:mediaType
                                                                                completion:^(BOOL saveSuccess) {
                                                                                  notifyCompletion(saveSuccess);
                                                                                }];
                                                                       }
                                                                     }];
                                           return;
                                       }
                                   }
                                   [self saveMedia:fileURL
                                         mediaType:mediaType
                                        completion:^(BOOL saveSuccess) {
                                          notifyCompletion(saveSuccess);
                                        }];
                               }
                           } else {
                               notifyCompletion(NO);
                               if (fileURL) {
                                   [[DYYYManager shared] finalizeDownloadWithFileURL:fileURL success:NO];
                               }
                           }
                         }];
}

#pragma mark - 普通媒体与批量图片

+ (void)downloadMediaWithProgress:(NSURL *)url
                        mediaType:(MediaType)mediaType
                            audio:(NSURL *)audioURL
                         progress:(void (^)(float progress))progressBlock
                       completion:(void (^)(BOOL success, NSURL *fileURL))completion {
    NSString *albumDescription = [self currentAlbumDescription];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!url) {
            if (completion) completion(NO, nil);
            return;
        }
        DYYYManager *manager = self.shared;
        DYYYToast *view = [[DYYYToast alloc] initWithFrame:UIScreen.mainScreen.bounds];
        [view show];
        view.cancelBlock = ^{ [self cancelAllDownloads]; };
        NSString *fileName = url.lastPathComponent;
        if (!fileName.pathExtension.length) {
            NSString *extension = mediaType == MediaTypeVideo ? @"mp4" : mediaType == MediaTypeAudio ? @"mp3" : mediaType == MediaTypeHeic ? @"heic" : @"jpg";
            fileName = [(fileName.length ? fileName : @"media") stringByAppendingPathExtension:extension];
        }
        NSURL *destination = [DYYYUtils uniqueTemporaryFileURLWithFileName:fileName];
        __block NSString *downloadID;
        downloadID = [manager enqueueDownloadURL:url destinationURL:destination progress:^(float value) {
            if (!view.isCancelled) [view setProgress:value];
            if (progressBlock) progressBlock(value);
        } completion:^(BOOL success, NSURL *fileURL) {
            if (success && !view.isCancelled) {
                [manager associateFileURL:fileURL withDownloadID:downloadID];
                if (completion) completion(YES, fileURL);
                else [manager finalizeDownloadWithID:downloadID success:YES fileURL:fileURL];
            } else {
                if (fileURL) [manager removeTemporaryFiles:@[fileURL]];
                if (!view.isCancelled) [DYYYUtils showToast:@"下载失败"];
                if (completion) completion(NO, nil);
                [manager finalizeDownloadWithID:downloadID success:NO fileURL:nil];
            }
        }];
        manager.progressViews[downloadID] = view;
        [manager setCompletionBlock:completion forDownloadID:downloadID];
        [manager setMediaType:mediaType forDownloadID:downloadID];
        manager.albumDescriptionMap[downloadID] = albumDescription ?: @"";
    });
}

+ (void)cancelAllDownloads {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self cancelAllDownloads]; });
        return;
    }
    DYYYManager *manager = self.shared;
    NSArray<dispatch_block_t> *handlers = manager.cancellationHandlers.allValues;
    [manager.cancellationHandlers removeAllObjects];
    for (DYYYToast *view in manager.progressViews.allValues) {
        view.isCancelled = YES;
        [view dismiss];
    }
    // 保留任务映射到终止回调，避免取消丢失 completion 和清理机会。
    [manager.downloadScheduler cancelAllTasks];
    for (dispatch_block_t handler in handlers) handler();
}

+ (void)downloadAllImages:(NSMutableArray *)imageURLs {
    [self downloadAllImagesWithProgress:imageURLs progress:nil completion:nil];
}

+ (void)downloadAllImagesWithProgress:(NSMutableArray *)imageURLs
                             progress:(void (^)(NSInteger current, NSInteger total))progressBlock
                           completion:(void (^)(NSInteger successCount, NSInteger totalCount))completion {
    NSString *albumDescription = [self currentAlbumDescription];
    NSArray *urls = [imageURLs copy];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (urls.count == 0) {
            if (completion) completion(0, 0);
            return;
        }
        DYYYManager *manager = self.shared;
        NSString *batchID = NSUUID.UUID.UUIDString;
        DYYYToast *view = [[DYYYToast alloc] initWithFrame:UIScreen.mainScreen.bounds];
        manager.progressViews[batchID] = view;
        [view show];
        view.cancelBlock = ^{ [self cancelAllDownloads]; };
        [manager setBatchInfo:batchID totalCount:urls.count progressBlock:progressBlock completionBlock:completion];
        manager.cancellationHandlers[batchID] = ^{ [manager finishBatch:batchID cancelled:YES]; };
        for (id value in urls) {
            NSURL *url = [value isKindOfClass:NSString.class] ? [NSURL URLWithString:value] : nil;
            if (!url) {
                [manager incrementCompletedAndUpdateProgressForBatch:batchID success:NO];
                continue;
            }
            NSURL *destination = [DYYYUtils uniqueTemporaryFileURLWithFileName:url.lastPathComponent.length ? url.lastPathComponent : @"image.jpg"];
            __block NSString *downloadID;
            downloadID = [manager enqueueDownloadURL:url destinationURL:destination progress:nil completion:^(BOOL success, NSURL *fileURL) {
                if (!manager.batchTotalCountMap[batchID]) {
                    if (fileURL) dispatch_async(manager.mediaProcessingQueue, ^{ [NSFileManager.defaultManager removeItemAtURL:fileURL error:nil]; });
                    [manager finalizeDownloadWithID:downloadID success:NO fileURL:fileURL];
                    return;
                }
                if (success) {
                    [manager associateFileURL:fileURL withDownloadID:downloadID];
                    [self saveMedia:fileURL mediaType:MediaTypeImage completion:^(BOOL saved) {
                        [manager incrementCompletedAndUpdateProgressForBatch:batchID success:saved];
                    }];
                } else {
                    [manager finalizeDownloadWithID:downloadID success:NO fileURL:nil];
                    [manager incrementCompletedAndUpdateProgressForBatch:batchID success:NO];
                }
            }];
            [manager associateDownload:downloadID withBatchID:batchID];
            manager.albumDescriptionMap[downloadID] = albumDescription ?: @"";
        }
    });
}

// 设置批量下载信息
- (void)setBatchInfo:(NSString *)batchID
          totalCount:(NSInteger)totalCount
       progressBlock:(void (^)(NSInteger current, NSInteger total))progressBlock
     completionBlock:(void (^)(NSInteger successCount, NSInteger totalCount))completionBlock {
    [self.batchTotalCountMap setObject:@(totalCount) forKey:batchID];
    [self.batchCompletedCountMap setObject:@(0) forKey:batchID];
    [self.batchSuccessCountMap setObject:@(0) forKey:batchID];

    if (progressBlock) {
        [self.batchProgressBlocks setObject:[progressBlock copy] forKey:batchID];
    }

    if (completionBlock) {
        [self.batchCompletionBlocks setObject:[completionBlock copy] forKey:batchID];
    }
}

// 关联单个下载到批量下载
- (void)associateDownload:(NSString *)downloadID withBatchID:(NSString *)batchID {
    [self.downloadToBatchMap setObject:batchID forKey:downloadID];
}

// 批量下载完成计数并更新进度
- (void)incrementCompletedAndUpdateProgressForBatch:(NSString *)batchID success:(BOOL)success {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self incrementCompletedAndUpdateProgressForBatch:batchID success:success]; });
        return;
    }
    NSNumber *total = self.batchTotalCountMap[batchID];
    if (!total) return; // 取消或完成后的迟到回调不能重新创建批次。
    NSInteger completed = [self.batchCompletedCountMap[batchID] integerValue] + 1;
    self.batchCompletedCountMap[batchID] = @(completed);
    if (success) self.batchSuccessCountMap[batchID] = @([self.batchSuccessCountMap[batchID] integerValue] + 1);
    [self.progressViews[batchID] setProgress:(float)completed / MAX(1, total.integerValue)];
    void (^progress)(NSInteger, NSInteger) = self.batchProgressBlocks[batchID];
    if (progress) progress(completed, total.integerValue);
    if (completed >= total.integerValue) [self finishBatch:batchID cancelled:NO];
}

- (void)finishBatch:(NSString *)batchID cancelled:(BOOL)cancelled {
    NSNumber *total = self.batchTotalCountMap[batchID];
    if (!total) return;
    NSInteger successes = [self.batchSuccessCountMap[batchID] integerValue];
    void (^completion)(NSInteger, NSInteger) = self.batchCompletionBlocks[batchID];
    DYYYToast *view = self.progressViews[batchID];
    // 先删除完成入口，再调用业务回调，允许回调重入或启动下一批。
    [self.batchTotalCountMap removeObjectForKey:batchID];
    [self.batchCompletedCountMap removeObjectForKey:batchID];
    [self.batchSuccessCountMap removeObjectForKey:batchID];
    [self.batchProgressBlocks removeObjectForKey:batchID];
    [self.batchCompletionBlocks removeObjectForKey:batchID];
    [self.cancellationHandlers removeObjectForKey:batchID];
    [self.progressViews removeObjectForKey:batchID];
    for (NSString *downloadID in [self.downloadToBatchMap allKeysForObject:batchID]) [self.downloadToBatchMap removeObjectForKey:downloadID];
    view.cancelBlock = nil;
    view.allowSuccessAnimation = !cancelled && successes == total.integerValue;
    [view dismiss];
    if (completion) completion(successes, total.integerValue);
}

// 保存完成回调
- (void)setCompletionBlock:(void (^)(BOOL success, NSURL *fileURL))completion forDownloadID:(NSString *)downloadID {
    if (completion) {
        [self.completionBlocks setObject:[completion copy] forKey:downloadID];
    }
}

// 保存媒体类型
- (void)setMediaType:(MediaType)mediaType forDownloadID:(NSString *)downloadID {
    [self.mediaTypeMap setObject:@(mediaType) forKey:downloadID];
}

- (void)associateFileURL:(NSURL *)fileURL withDownloadID:(NSString *)downloadID {
    if (!fileURL || downloadID.length == 0) {
        return;
    }
    NSString *filePath = fileURL.path;
    if (filePath.length == 0) {
        return;
    }
    @synchronized(self.filePathToDownloadID) {
        self.filePathToDownloadID[filePath] = downloadID;
    }
}

- (NSString *)downloadIDForFileURL:(NSURL *)fileURL {
    if (!fileURL) {
        return nil;
    }
    NSString *filePath = fileURL.path;
    if (filePath.length == 0) {
        return nil;
    }
    @synchronized(self.filePathToDownloadID) {
        return self.filePathToDownloadID[filePath];
    }
}

- (void)replaceFileURL:(NSURL *)oldURL withFileURL:(NSURL *)newURL {
    if (!newURL) {
        return;
    }
    NSString *downloadID = [self downloadIDForFileURL:oldURL];
    if (downloadID.length == 0) {
        return;
    }
    NSString *newPath = newURL.path;
    if (newPath.length == 0) {
        return;
    }
    @synchronized(self.filePathToDownloadID) {
        if (oldURL.path.length > 0) {
            [self.filePathToDownloadID removeObjectForKey:oldURL.path];
        }
        self.filePathToDownloadID[newPath] = downloadID;
    }
}

- (void)removeMappingsForDownloadID:(NSString *)downloadID {
    if (downloadID.length == 0) {
        return;
    }
    @synchronized(self.filePathToDownloadID) {
        NSArray *keys = [self.filePathToDownloadID allKeysForObject:downloadID];
        for (NSString *key in keys) {
            [self.filePathToDownloadID removeObjectForKey:key];
        }
    }
}

- (void)finalizeDownloadWithFileURL:(NSURL *)fileURL success:(BOOL)success {
    NSString *downloadID = [self downloadIDForFileURL:fileURL];
    if (downloadID.length == 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
          if (!success) {
              [DYYYUtils showToast:@"保存失败"];
          }
        });
        return;
    }
    [self finalizeDownloadWithID:downloadID success:success fileURL:fileURL];
}

- (void)finalizeDownloadWithID:(NSString *)downloadID success:(BOOL)success fileURL:(NSURL *_Nullable)fileURL {
    if (downloadID.length == 0) {
        return;
    }

    [self removeMappingsForDownloadID:downloadID];

    dispatch_async(dispatch_get_main_queue(), ^{
      DYYYToast *progressView = self.progressViews[downloadID];
      if (progressView) {
          progressView.cancelBlock = nil;
          progressView.allowSuccessAnimation = success && !progressView.isCancelled;
          if (success) {
              [progressView setProgress:1.0f];
          }
          [progressView dismiss];
          [self.progressViews removeObjectForKey:downloadID];
      }

      [self.taskProgressMap removeObjectForKey:downloadID];
      [self.completionBlocks removeObjectForKey:downloadID];
      [self.mediaTypeMap removeObjectForKey:downloadID];
      [self.albumDescriptionMap removeObjectForKey:downloadID];
      [self.downloadTasks removeObjectForKey:downloadID];
      [self.downloadToBatchMap removeObjectForKey:downloadID];
    });

    if (fileURL) {
        NSString *filePath = fileURL.path;
        if (filePath.length > 0) {
            @synchronized(self.filePathToDownloadID) {
                [self.filePathToDownloadID removeObjectForKey:filePath];
            }
        }
    }
}

#pragma mark - 统一下载调度

- (NSURL *)destinationURLForTask:(NSURLSessionTask *)task {
    return objc_getAssociatedObject(task, @selector(destinationURLForTask:));
}

- (NSString *)enqueueDownloadURL:(NSURL *)url
                 destinationURL:(NSURL *)destinationURL
                       progress:(void (^)(float))progress
                     completion:(void (^)(BOOL, NSURL *))completion {
    NSAssert(NSThread.isMainThread, @"下载状态必须在主线程更新");
    NSString *downloadID = NSUUID.UUID.UUIDString;
    NSURLSessionDownloadTask *task = [self.downloadSession downloadTaskWithURL:url];
    task.taskDescription = downloadID;
    objc_setAssociatedObject(task, @selector(destinationURLForTask:), destinationURL, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    self.downloadTasks[downloadID] = task;
    self.albumDescriptionMap[downloadID] = [DYYYManager currentAlbumDescription] ?: @"";
    self.taskProgressMap[downloadID] = @0;
    if (progress) self.transferProgressBlocks[downloadID] = [progress copy];
    if (completion) self.transferCompletionBlocks[downloadID] = [completion copy];
    [self.downloadScheduler enqueueTask:task];
    return downloadID;
}

- (void)finishTransfer:(NSURLSessionTask *)task fileURL:(NSURL *)fileURL error:(NSError *)error {
    NSAssert(NSThread.isMainThread, @"下载收尾必须在主线程更新");
    NSString *downloadID = task.taskDescription;
    if (self.downloadTasks[downloadID] != task) return;
    void (^completion)(BOOL, NSURL *) = self.transferCompletionBlocks[downloadID];
    [self.downloadTasks removeObjectForKey:downloadID];
    [self.transferCompletionBlocks removeObjectForKey:downloadID];
    [self.transferProgressBlocks removeObjectForKey:downloadID];
    [self.taskProgressMap removeObjectForKey:downloadID];
    [self.downloadScheduler completeTask:task];
    if (completion) completion(fileURL != nil && error == nil, fileURL);
}

#pragma mark - NSURLSessionDownloadDelegate

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)task
      didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)written totalBytesExpectedToWrite:(int64_t)expected {
    if (expected <= 0) return;
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    SEL progressKey = @selector(URLSession:downloadTask:didWriteData:totalBytesWritten:totalBytesExpectedToWrite:);
    NSNumber *lastUpdate = objc_getAssociatedObject(task, progressKey);
    if (written < expected && lastUpdate && now - lastUpdate.doubleValue < 0.1) return;
    objc_setAssociatedObject(task, progressKey, @(now), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    float progress = MIN(1.0, (double)written / expected);
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *downloadID = task.taskDescription;
        if (self.downloadTasks[downloadID] != task) return;
        self.taskProgressMap[downloadID] = @(progress);
        void (^callback)(float) = self.transferProgressBlocks[downloadID];
        if (callback) callback(progress);
    });
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)task didFinishDownloadingToURL:(NSURL *)location {
    // delegate 队列处理文件；临时 location 仅在本回调内有效。
    NSURL *destination = [self destinationURLForTask:task];
    NSError *error = nil;
    NSInteger status = [(NSHTTPURLResponse *)task.response isKindOfClass:NSHTTPURLResponse.class] ? [(NSHTTPURLResponse *)task.response statusCode] : 200;
    if (status >= 400 || !destination) {
        error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorBadServerResponse userInfo:nil];
    } else if (task.state == NSURLSessionTaskStateCanceling) {
        error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil];
    } else {
        NSFileManager *files = NSFileManager.defaultManager;
        [files createDirectoryAtURL:destination.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:&error];
        if (!error) [files moveItemAtURL:location toURL:destination error:&error];
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [self finishTransfer:task fileURL:error ? nil : destination error:error];
    });
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (!error) return;
    dispatch_async(dispatch_get_main_queue(), ^{ [self finishTransfer:task fileURL:nil error:error]; });
}

#pragma mark - 实况照片保存

// 编码器也按完整生命周期串行调度，避免多张图片/实况同时占满编码资源。
- (void)enqueueMediaJob:(void (^)(dispatch_block_t))job {
    dispatch_async(self.mediaProcessingQueue, ^{
        [self.mediaJobs addObject:[job copy]];
        [self startNextMediaJob];
    });
}

- (void)startNextMediaJob {
    if (self.mediaJobActive || self.mediaJobs.count == 0) return;
    self.mediaJobActive = YES;
    void (^job)(dispatch_block_t) = self.mediaJobs.firstObject;
    [self.mediaJobs removeObjectAtIndex:0];
    __block BOOL finished = NO;
    job(^{
        dispatch_async(self.mediaProcessingQueue, ^{
            if (finished) return;
            finished = YES;
            self.mediaJobActive = NO;
            [self startNextMediaJob];
        });
    });
}

- (void)removeTemporaryFiles:(NSArray<NSURL *> *)files {
    dispatch_async(self.mediaProcessingQueue, ^{
        for (NSURL *url in files) [NSFileManager.defaultManager removeItemAtURL:url error:nil];
    });
}

- (void)saveLivePhoto:(NSString *)imageSourcePath videoUrl:(NSString *)videoSourcePath {
    [self saveLivePhotoImage:[NSURL fileURLWithPath:imageSourcePath]
                      video:[NSURL fileURLWithPath:videoSourcePath]
               cancellation:[NSProgress progressWithTotalUnitCount:1]
                 completion:^(BOOL success) {
        if (!success) [DYYYUtils showToast:@"保存实况照片失败"];
    }];
}

- (void)saveLivePhotoImage:(NSURL *)image video:(NSURL *)video cancellation:(NSProgress *)cancellation completion:(void (^)(BOOL))completion {
    if (@available(iOS 15.0, *)) {
        [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
            if ((status != PHAuthorizationStatusAuthorized && status != PHAuthorizationStatusLimited) || cancellation.cancelled) {
                [self removeTemporaryFiles:@[image, video]];
                dispatch_async(dispatch_get_main_queue(), ^{ completion(NO); });
                return;
            }
            [self useAssetWriter:image video:video identifier:NSUUID.UUID.UUIDString albumDescription:cancellation.userInfo[@"DYYYAlbumDescription"] ?: [DYYYManager currentAlbumDescription] complete:^(BOOL success, NSString *photoFile, NSString *videoFile, NSError *error) {
                NSMutableArray<NSURL *> *files = [NSMutableArray arrayWithObjects:image, video, nil];
                if (photoFile) [files addObject:[NSURL fileURLWithPath:photoFile]];
                if (videoFile) [files addObject:[NSURL fileURLWithPath:videoFile]];
                if (!success || cancellation.cancelled) {
                    [self removeTemporaryFiles:files];
                    completion(NO);
                    return;
                }
                [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                    PHAssetCreationRequest *request = [PHAssetCreationRequest creationRequestForAsset];
                    [request addResourceWithType:PHAssetResourceTypePhoto fileURL:[NSURL fileURLWithPath:photoFile] options:nil];
                    [request addResourceWithType:PHAssetResourceTypePairedVideo fileURL:[NSURL fileURLWithPath:videoFile] options:nil];
                } completionHandler:^(BOOL saved, NSError *saveError) {
                    if (saveError) NSLog(@"[DYYY] 保存实况照片失败: %@", saveError);
                    [self removeTemporaryFiles:files];
                    dispatch_async(dispatch_get_main_queue(), ^{ completion(saved && !cancellation.cancelled); });
                }];
            }];
        }];
    } else {
        [self removeTemporaryFiles:@[image, video]];
        dispatch_async(dispatch_get_main_queue(), ^{
            [DYYYUtils showToast:@"当前iOS版本不支持实况照片"];
            completion(NO);
        });
    }
}

#pragma mark - 每个实况任务独立的元数据处理

- (NSError *)mediaErrorWithDescription:(NSString *)description {
    return [NSError errorWithDomain:@"DYYYMedia" code:1 userInfo:@{NSLocalizedDescriptionKey:description}];
}

- (void)useAssetWriter:(NSURL *)photoURL video:(NSURL *)videoURL identifier:(NSString *)identifier albumDescription:(NSString *)albumDescription complete:(void (^)(BOOL, NSString *, NSString *, NSError *))complete {
    [self enqueueMediaJob:^(dispatch_block_t jobDone) {
        @autoreleasepool {
            NSURL *photoFile = [DYYYUtils uniqueTemporaryFileURLWithFileName:@"livephoto.jpg"];
            NSURL *videoFile = [DYYYUtils uniqueTemporaryFileURLWithFileName:@"livephoto.mov"];
            if (![self addMetadataToPhoto:photoURL outputFile:photoFile.path identifier:identifier albumDescription:albumDescription]) {
                [self removeTemporaryFiles:@[photoFile, videoFile]];
                jobDone();
                dispatch_async(dispatch_get_main_queue(), ^{ complete(NO, nil, nil, [self mediaErrorWithDescription:@"图片元数据写入失败"]); });
                return;
            }
            [self writeLivePhotoMetadataToVideo:videoURL outputFile:videoFile identifier:identifier albumDescription:albumDescription completion:^(BOOL success, NSError *error) {
                if (!success) {
                    NSLog(@"[DYYY] 实况照片转码失败: %@", error);
                    [self removeTemporaryFiles:@[photoFile, videoFile]];
                }
                jobDone();
                complete(success, success ? photoFile.path : nil, success ? videoFile.path : nil, error);
            }];
        }
    }];
}

- (BOOL)addMetadataToPhoto:(NSURL *)photoURL outputFile:(NSString *)outputFile identifier:(NSString *)identifier albumDescription:(NSString *)albumDescription {
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)photoURL, NULL);
    if (!source) return NO;
    if (CGImageSourceGetCount(source) == 0) { CFRelease(source); return NO; }
    CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
    if (!image) { CFRelease(source); return NO; }
    NSMutableDictionary *metadata = [CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL)) mutableCopy] ?: [NSMutableDictionary dictionary];
    NSString *makerKey = (__bridge NSString *)kCGImagePropertyMakerAppleDictionary;
    NSMutableDictionary *maker = [metadata[makerKey] mutableCopy] ?: [NSMutableDictionary dictionary];
    maker[@"17"] = identifier;
    metadata[makerKey] = maker;
    if (albumDescription.length) {
        NSMutableDictionary *tiff = [metadata[(NSString *)kCGImagePropertyTIFFDictionary] mutableCopy] ?: [NSMutableDictionary dictionary];
        tiff[(NSString *)kCGImagePropertyTIFFImageDescription] = albumDescription;
        metadata[(NSString *)kCGImagePropertyTIFFDictionary] = tiff;
        NSMutableDictionary *iptc = [metadata[(NSString *)kCGImagePropertyIPTCDictionary] mutableCopy] ?: [NSMutableDictionary dictionary];
        iptc[(NSString *)kCGImagePropertyIPTCCaptionAbstract] = albumDescription;
        metadata[(NSString *)kCGImagePropertyIPTCDictionary] = iptc;
    }
    NSURL *destinationURL = [NSURL fileURLWithPath:outputFile];
    CGImageDestinationRef destination = CGImageDestinationCreateWithURL((__bridge CFURLRef)destinationURL, kUTTypeJPEG, 1, NULL);
    BOOL success = NO;
    if (destination) {
        CGImageDestinationAddImage(destination, image, (__bridge CFDictionaryRef)metadata);
        success = CGImageDestinationFinalize(destination);
        CFRelease(destination);
    }
    CGImageRelease(image);
    CFRelease(source);
    return success;
}

- (void)writeLivePhotoMetadataToVideo:(NSURL *)videoURL outputFile:(NSURL *)outputFile identifier:(NSString *)identifier albumDescription:(NSString *)albumDescription completion:(void (^)(BOOL, NSError *))complete {
    NSError *error = nil;
    AVAsset *asset = [AVAsset assetWithURL:videoURL];
    AVAssetReader *reader = [AVAssetReader assetReaderWithAsset:asset error:&error];
    AVAssetWriter *writer = reader ? [AVAssetWriter assetWriterWithURL:outputFile fileType:AVFileTypeQuickTimeMovie error:&error] : nil;
    if (!reader || !writer) {
        dispatch_async(dispatch_get_main_queue(), ^{ complete(NO, error ?: [self mediaErrorWithDescription:@"无法创建实况视频读写器"]); });
        return;
    }
    NSMutableArray *metadata = [asset.metadata mutableCopy] ?: [NSMutableArray array];
    [metadata addObject:[self createContentIdentifierMetadataItem:identifier]];
    writer.metadata = [DYYYUtils metadataItemsByAppendingDescription:albumDescription toItems:metadata];
    NSMutableArray<AVAssetReaderTrackOutput *> *outputs = [NSMutableArray array];
    NSMutableArray<AVAssetWriterInput *> *inputs = [NSMutableArray array];
    BOOL hasVideo = NO;
    for (AVAssetTrack *track in asset.tracks) {
        BOOL audio = [track.mediaType isEqualToString:AVMediaTypeAudio];
        if (!audio && ![track.mediaType isEqualToString:AVMediaTypeVideo]) continue;
        NSDictionary *readSettings = audio ? @{AVFormatIDKey:@(kAudioFormatLinearPCM)} : nil;
        NSDictionary *writeSettings = audio ? @{AVFormatIDKey:@(kAudioFormatMPEG4AAC), AVSampleRateKey:@44100, AVNumberOfChannelsKey:@2, AVEncoderBitRateKey:@128000} : nil;
        AVAssetReaderTrackOutput *output = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track outputSettings:readSettings];
        CMFormatDescriptionRef hint = audio ? NULL : (__bridge CMFormatDescriptionRef)track.formatDescriptions.firstObject;
        AVAssetWriterInput *input = [AVAssetWriterInput assetWriterInputWithMediaType:track.mediaType outputSettings:writeSettings sourceFormatHint:hint];
        if (![reader canAddOutput:output] || ![writer canAddInput:input]) continue;
        output.alwaysCopiesSampleData = NO;
        if (!audio) { input.transform = track.preferredTransform; hasVideo = YES; }
        [reader addOutput:output];
        [writer addInput:input];
        [outputs addObject:output];
        [inputs addObject:input];
    }
    AVAssetWriterInput *metadataInput = [self createStillImageTimeAssetWriterInput];
    if (!hasVideo || !metadataInput || ![writer canAddInput:metadataInput]) {
        dispatch_async(dispatch_get_main_queue(), ^{ complete(NO, [self mediaErrorWithDescription:@"实况视频轨道不可用"]); });
        return;
    }
    [writer addInput:metadataInput];
    AVAssetWriterInputMetadataAdaptor *adaptor = [AVAssetWriterInputMetadataAdaptor assetWriterInputMetadataAdaptorWithAssetWriterInput:metadataInput];
    if (![writer startWriting]) {
        dispatch_async(dispatch_get_main_queue(), ^{ complete(NO, writer.error); });
        return;
    }
    [writer startSessionAtSourceTime:kCMTimeZero];
    if (![reader startReading] || ![adaptor appendTimedMetadataGroup:[[AVTimedMetadataGroup alloc] initWithItems:@[[self createStillImageTimeMetadataItem]] timeRange:CMTimeRangeMake(kCMTimeZero, CMTimeMake(1, 100))]]) {
        [reader cancelReading];
        [writer cancelWriting];
        dispatch_async(dispatch_get_main_queue(), ^{ complete(NO, reader.error ?: writer.error ?: [self mediaErrorWithDescription:@"实况元数据写入失败"]); });
        return;
    }
    [metadataInput markAsFinished];
    dispatch_queue_t trackQueue = dispatch_queue_create("com.dyyy.livephoto.tracks", DISPATCH_QUEUE_SERIAL);
    __block BOOL finishing = NO;
    __block NSUInteger finishedTracks = 0;
    __block NSTimeInterval lastProgress = NSProcessInfo.processInfo.systemUptime;
    __block dispatch_source_t watchdog = nil;
    void (^finish)(BOOL, NSError *) = ^(BOOL success, NSError *failure) {
        if (finishing) return;
        finishing = YES;
        dispatch_source_t timer = watchdog;
        watchdog = nil;
        if (timer) {
            dispatch_source_set_event_handler(timer, ^{});
            dispatch_source_cancel(timer);
        }
        if (reader.status == AVAssetReaderStatusReading) [reader cancelReading];
        if (success && writer.status == AVAssetWriterStatusWriting) {
            [writer finishWritingWithCompletionHandler:^{
                dispatch_async(dispatch_get_main_queue(), ^{ complete(writer.status == AVAssetWriterStatusCompleted, writer.error); });
            }];
        } else {
            if (writer.status == AVAssetWriterStatusWriting) [writer cancelWriting];
            NSError *result = failure ?: writer.error ?: reader.error ?: [self mediaErrorWithDescription:@"实况视频写入失败"];
            dispatch_async(dispatch_get_main_queue(), ^{ complete(NO, result); });
        }
    };
    watchdog = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, trackQueue);
    dispatch_source_set_timer(watchdog, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), NSEC_PER_SEC, NSEC_PER_SEC / 10);
    dispatch_source_set_event_handler(watchdog, ^{
        if (writer.status == AVAssetWriterStatusFailed || writer.status == AVAssetWriterStatusCancelled || reader.status == AVAssetReaderStatusFailed || NSProcessInfo.processInfo.systemUptime - lastProgress > 30) {
            finish(NO, writer.error ?: reader.error ?: [self mediaErrorWithDescription:@"实况视频写入超时"]);
        }
    });
    dispatch_resume(watchdog);
    for (NSUInteger index = 0; index < inputs.count; index++) {
        AVAssetReaderTrackOutput *output = outputs[index];
        AVAssetWriterInput *input = inputs[index];
        __block BOOL trackFinished = NO;
        [input requestMediaDataWhenReadyOnQueue:trackQueue usingBlock:^{
            if (finishing || trackFinished) return;
            while (input.readyForMoreMediaData && !finishing) {
                CMSampleBufferRef sample = [output copyNextSampleBuffer];
                if (!sample) {
                    trackFinished = YES;
                    [input markAsFinished];
                    finishedTracks++;
                    if (reader.status == AVAssetReaderStatusFailed) finish(NO, reader.error);
                    else if (finishedTracks == inputs.count) finish(YES, nil);
                    return;
                }
                BOOL appended = [input appendSampleBuffer:sample];
                CFRelease(sample);
                lastProgress = NSProcessInfo.processInfo.systemUptime;
                if (!appended) { finish(NO, writer.error); return; }
            }
        }];
    }
}

- (AVMetadataItem *)createContentIdentifierMetadataItem:(NSString *)identifier {
    AVMutableMetadataItem *item = [AVMutableMetadataItem metadataItem];
    item.keySpace = AVMetadataKeySpaceQuickTimeMetadata;
    item.key = AVMetadataQuickTimeMetadataKeyContentIdentifier;
    item.value = identifier;
    return item;
}

- (AVAssetWriterInput *)createStillImageTimeAssetWriterInput {
    NSArray *spec = @[ @{
        (NSString *)kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier : @"mdta/com.apple.quicktime.still-image-time",
        (NSString *)kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType : (NSString *)kCMMetadataBaseDataType_SInt8
    } ];
    CMFormatDescriptionRef desc = NULL;
    CMMetadataFormatDescriptionCreateWithMetadataSpecifications(kCFAllocatorDefault, kCMMetadataFormatType_Boxed, (__bridge CFArrayRef)spec, &desc);
    if (!desc) return nil;
    AVAssetWriterInput *input = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeMetadata outputSettings:nil sourceFormatHint:desc];
    CFRelease(desc);
    return input;
}

- (AVMetadataItem *)createStillImageTimeMetadataItem {
    AVMutableMetadataItem *item = [AVMutableMetadataItem metadataItem];
    item.keySpace = AVMetadataKeySpaceQuickTimeMetadata;
    item.key = @"com.apple.quicktime.still-image-time";
    item.value = @(-1);
    item.dataType = (NSString *)kCMMetadataBaseDataType_SInt8;
    return item;
}
#pragma mark - 评论区图片保存

+ (void)saveCommentImages:(NSArray *)imageModels
             currentIndex:(NSInteger)currentIndex
               completion:(void (^)(NSInteger successCount, NSInteger livePhotoCount, NSInteger failedCount))completion {
    if (!imageModels || imageModels.count == 0) {
        if (completion) completion(0, 0, 0);
        return;
    }
    
    // 确定要保存的图片
    NSArray *imagesToSave = nil;
    if (currentIndex >= 0 && currentIndex < (NSInteger)imageModels.count) {
        imagesToSave = @[imageModels[currentIndex]];
    } else {
        imagesToSave = imageModels;
    }
    
    // 分离普通图片和实况照片
    NSMutableArray *normalImages = [NSMutableArray array];
    NSMutableArray *livePhotos = [NSMutableArray array];
    
    for (id imageModel in imagesToSave) {
        @try {
            // 获取图片 URL - originUrl 和 mediumUrl 都是 AWEURLModel 类型
            NSString *imageUrlStr = nil;
            
            // 首先尝试 originUrl
            AWEURLModel *originUrlModel = [imageModel valueForKey:@"originUrl"];
            if (originUrlModel) {
                NSArray *urlList = [originUrlModel originURLList];
                if (urlList && urlList.count > 0) {
                    imageUrlStr = urlList.firstObject;
                }
            }
            
            // 如果 originUrl 没有获取到，尝试 mediumUrl
            if (!imageUrlStr) {
                AWEURLModel *mediumUrlModel = [imageModel valueForKey:@"mediumUrl"];
                if (mediumUrlModel) {
                    NSArray *urlList = [mediumUrlModel originURLList];
                    if (urlList && urlList.count > 0) {
                        imageUrlStr = urlList.firstObject;
                    }
                }
            }
            
            NSLog(@"[DYYY] 评论图片URL: %@", imageUrlStr);
            
            if (!imageUrlStr || imageUrlStr.length == 0) {
                NSLog(@"[DYYY] 无法获取图片URL，imageModel: %@", imageModel);
                continue;
            }
            
            // 检查是否是实况照片
            id livePhotoModel = [imageModel valueForKey:@"livePhotoModel"];
            if (livePhotoModel) {
                NSArray *videoUrls = [livePhotoModel valueForKey:@"videoUrl"];
                if (videoUrls && videoUrls.count > 0) {
                    NSString *videoUrlStr = videoUrls.firstObject;
                    if (videoUrlStr && videoUrlStr.length > 0) {
                        // 传入字符串而不是 NSURL，与 downloadAllLivePhotosWithProgress 期望的格式一致
                        [livePhotos addObject:@{
                            @"imageURL": imageUrlStr,
                            @"videoURL": videoUrlStr
                        }];
                        continue;
                    }
                }
            }
            
            // 普通图片 - 存储字符串而不是 NSURL
            [normalImages addObject:imageUrlStr];
        } @catch (NSException *e) {
            NSLog(@"[DYYY] 解析评论图片失败: %@", e);
        }
    }
    
    NSLog(@"[DYYY] 解析完成: 普通图片=%lu, 实况照片=%lu", (unsigned long)normalImages.count, (unsigned long)livePhotos.count);
    
    // 如果都没有解析到有效URL，直接返回失败
    if (normalImages.count == 0 && livePhotos.count == 0) {
        if (completion) completion(0, 0, (NSInteger)imagesToSave.count);
        return;
    }
    
    __block NSInteger successCount = 0;
    __block NSInteger livePhotoCount = 0;
    __block NSInteger failedCount = 0;
    
    dispatch_group_t group = dispatch_group_create();
    
    // 保存普通图片
    if (normalImages.count > 0) {
        dispatch_group_enter(group);
        [self downloadAllImagesWithProgress:[normalImages mutableCopy]
                                   progress:nil
                                 completion:^(NSInteger imgSuccess, NSInteger imgTotal) {
            successCount += imgSuccess;
            failedCount += (imgTotal - imgSuccess);
            dispatch_group_leave(group);
        }];
    }
    
    // 保存实况照片
    if (livePhotos.count > 0) {
        dispatch_group_enter(group);
        [self downloadAllLivePhotosWithProgress:livePhotos
                                       progress:nil
                                     completion:^(NSInteger lpSuccess, NSInteger lpTotal) {
            successCount += lpSuccess;
            livePhotoCount = lpSuccess;
            failedCount += (lpTotal - lpSuccess);
            dispatch_group_leave(group);
        }];
    }
    
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        if (completion) {
            completion(successCount, livePhotoCount, failedCount);
        }
    });
}

#pragma mark - 批量实况照片

+ (void)downloadAllLivePhotos:(NSArray<NSDictionary *> *)livePhotos {
    [self downloadAllLivePhotosWithProgress:livePhotos progress:nil completion:nil];
}

+ (void)downloadAllLivePhotosWithProgress:(NSArray<NSDictionary *> *)livePhotos
                                 progress:(void (^)(NSInteger current, NSInteger total))progressBlock
                               completion:(void (^)(NSInteger successCount, NSInteger totalCount))completion {
    NSString *albumDescription = [self currentAlbumDescription];
    NSArray<NSDictionary *> *items = [livePhotos copy];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (items.count == 0) {
            if (completion) completion(0, 0);
            return;
        }
        DYYYManager *manager = self.shared;
        NSString *batchID = NSUUID.UUID.UUIDString;
        NSProgress *cancellation = [NSProgress progressWithTotalUnitCount:items.count * 10];
        [cancellation setUserInfoObject:albumDescription ?: @"" forKey:@"DYYYAlbumDescription"];
        DYYYToast *view = [[DYYYToast alloc] initWithFrame:UIScreen.mainScreen.bounds];
        manager.progressViews[batchID] = view;
        [view show];
        view.cancelBlock = ^{ [self cancelAllDownloads]; };
        manager.cancellationHandlers[batchID] = ^{ [cancellation cancel]; };
        NSMutableArray<NSDictionary *> *files = [NSMutableArray array];
        NSMutableIndexSet *imagesReady = [NSMutableIndexSet indexSet];
        NSMutableIndexSet *videosReady = [NSMutableIndexSet indexSet];
        dispatch_group_t downloads = dispatch_group_create();
        __block NSInteger completedSteps = 0;
        __block BOOL finished = NO;
        void (^updateProgress)(void) = ^{
            if (cancellation.cancelled || finished) return;
            [view setProgress:(float)completedSteps / (items.count * 10)];
            if (progressBlock) progressBlock(completedSteps, items.count * 10);
        };
        void (^finish)(NSInteger) = ^(NSInteger successes) {
            if (finished) return;
            finished = YES;
            [manager.cancellationHandlers removeObjectForKey:batchID];
            [manager.progressViews removeObjectForKey:batchID];
            view.cancelBlock = nil;
            view.allowSuccessAnimation = !cancellation.cancelled && successes == items.count;
            [view dismiss];
            NSMutableArray *temporaryFiles = [NSMutableArray array];
            for (NSDictionary *pair in files) [temporaryFiles addObjectsFromArray:@[pair[@"image"], pair[@"video"]]];
            [manager removeTemporaryFiles:temporaryFiles];
            if (completion) completion(successes, items.count);
        };
        for (NSUInteger index = 0; index < items.count; index++) {
            NSURL *imageFile = [DYYYUtils uniqueTemporaryFileURLWithFileName:@"livephoto.heic"];
            NSURL *videoFile = [DYYYUtils uniqueTemporaryFileURLWithFileName:@"livephoto.mp4"];
            [files addObject:@{@"image":imageFile, @"video":videoFile}];
            for (NSString *kind in @[@"image", @"video"]) {
                NSString *key = [kind stringByAppendingString:@"URL"];
                NSDictionary *item = [items[index] isKindOfClass:NSDictionary.class] ? items[index] : nil;
                id value = item[key];
                NSURL *url = [value isKindOfClass:NSString.class] ? [NSURL URLWithString:value] : nil;
                if (!url) { completedSteps += 4; continue; }
                dispatch_group_enter(downloads);
                [manager enqueueDownloadURL:url destinationURL:files[index][kind] progress:nil completion:^(BOOL success, NSURL *fileURL) {
                    if (success) [([kind isEqualToString:@"image"] ? imagesReady : videosReady) addIndex:index];
                    completedSteps += 4;
                    updateProgress();
                    dispatch_group_leave(downloads);
                }];
            }
        }
        updateProgress();
        dispatch_group_notify(downloads, dispatch_get_main_queue(), ^{
            if (cancellation.cancelled) { finish(0); return; }
            NSMutableArray *validFiles = [NSMutableArray array];
            for (NSUInteger index = 0; index < files.count; index++) {
                if ([imagesReady containsIndex:index] && [videosReady containsIndex:index]) [validFiles addObject:files[index]];
                else completedSteps += 2;
            }
            updateProgress();
            [manager saveLivePhotoBatch:validFiles index:0 successes:0 cancellation:cancellation progress:^{
                completedSteps += 2;
                updateProgress();
            } completion:finish];
        });
    });
}

- (void)saveLivePhotoBatch:(NSArray<NSDictionary *> *)files
                   index:(NSUInteger)index
               successes:(NSInteger)successes
            cancellation:(NSProgress *)cancellation
                progress:(dispatch_block_t)progress
              completion:(void (^)(NSInteger))completion {
    if (cancellation.cancelled || index >= files.count) {
        completion(successes);
        return;
    }
    NSDictionary *pair = files[index];
    // 逐个完成转码和相册保存，避免一批实况同时创建大量编码器。
    [self saveLivePhotoImage:pair[@"image"] video:pair[@"video"] cancellation:cancellation completion:^(BOOL saved) {
        progress();
        [self saveLivePhotoBatch:files index:index + 1 successes:successes + (saved ? 1 : 0) cancellation:cancellation progress:progress completion:completion];
    }];
}

+ (void)parseAndDownloadVideoWithShareLink:(NSString *)shareLink apiKey:(NSString *)apiKey {
    if (shareLink.length == 0 || apiKey.length == 0) {
        [DYYYUtils showToast:@"分享链接或API密钥无效"];
        return;
    }

    NSString *apiUrl = [NSString stringWithFormat:@"%@%@", apiKey, [shareLink stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];

    NSURL *url = [NSURL URLWithString:apiUrl];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    NSURLSession *session = [NSURLSession sharedSession];

    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request
                                                completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                                                  dispatch_async(dispatch_get_main_queue(), ^{
                                                    if (error) {
                                                        [DYYYUtils showToast:[NSString stringWithFormat:@"接口请求失败: %@", error.localizedDescription]];
                                                        return;
                                                    }

                                                    NSError *jsonError;
                                                    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
                                                    if (jsonError) {
                                                        [DYYYUtils showToast:@"解析接口返回数据失败"];
                                                        return;
                                                    }

                                                    NSInteger code = [json[@"code"] integerValue];
                                                    if (code != 0 && code != 200) {
                                                        [DYYYUtils showToast:[NSString stringWithFormat:@"接口返回错误: %@", json[@"msg"] ?: @"未知错误"]];
                                                        return;
                                                    }

                                                    NSDictionary *dataDict = json[@"data"];
                                                    if (!dataDict) {
                                                        [DYYYUtils showToast:@"接口返回数据为空"];
                                                        return;
                                                    }

                                                    // 交给handleVideoData处理数据
                                                    [self handleVideoData:dataDict];
                                                  });
                                                }];

    [dataTask resume];
}

+ (void)handleVideoData:(NSDictionary *)dataDict {
    // 首先检查videos和images数组
    NSArray *videoList = dataDict[@"video_list"];
    NSArray *videos = dataDict[@"videos"];
    NSArray *images = dataDict[@"images"];
    NSArray *imgArray = dataDict[@"img"];

    // 获取封面URL
    NSString *coverURL = nil;
    if (dataDict[@"cover"] && [dataDict[@"cover"] length] > 0) {
        coverURL = dataDict[@"cover"];
    } else if (dataDict[@"pics"] && [dataDict[@"pics"] length] > 0) {
        coverURL = dataDict[@"pics"];
    }

    // 尝试获取音乐URL（供后续下载视频时合并音频使用）
    NSString *musicURL = nil;
    if (dataDict[@"music"] && [dataDict[@"music"] length] > 0) {
        musicURL = dataDict[@"music"];
    } else if (dataDict[@"music_url"] && [dataDict[@"music_url"] length] > 0) {
        musicURL = dataDict[@"music_url"];
    }

    // 检查是否有视频列表(优先处理)
    BOOL hasVideoList = [videoList isKindOfClass:[NSArray class]] && videoList.count > 0;
    if (hasVideoList) {
        AWEUserActionSheetView *actionSheet = [[NSClassFromString(@"AWEUserActionSheetView") alloc] init];
        NSMutableArray *actions = [NSMutableArray array];

        for (NSDictionary *videoDict in videoList) {
            NSString *url = videoDict[@"url"];
            NSString *level = videoDict[@"level"];
            if (url.length > 0 && level.length > 0) {
                AWEUserSheetAction *qualityAction = [NSClassFromString(@"AWEUserSheetAction") actionWithTitle:level
                                                                                                      imgName:nil
                                                                                                      handler:^{
                                                                                                        NSURL *videoDownloadUrl = [NSURL URLWithString:url];
                                                                                                        NSURL *optionalAudioURL = nil;
                                                                                                        if (musicURL.length > 0) {
                                                                                                            optionalAudioURL = [NSURL URLWithString:musicURL];
                                                                                                        }
                                                                                                        [self downloadMedia:videoDownloadUrl
                                                                                                                  mediaType:MediaTypeVideo
                                                                                                                      audio:optionalAudioURL
                                                                                                                 completion:^(BOOL success) {
                                                                                                                   if (!success) {
                                                                                                                   }
                                                                                                                 }];
                                                                                                      }];
                [actions addObject:qualityAction];
            }
        }

        if (actions.count > 0) {
            [actionSheet setActions:actions];
            [actionSheet show];
            return;
        }
    }

    // 尝试获取视频URL
    NSString *singleVideoURL = nil;
    if (dataDict[@"url"] && [dataDict[@"url"] length] > 0) {
        singleVideoURL = dataDict[@"url"];
    } else if (dataDict[@"video"] && [dataDict[@"video"] length] > 0) {
        singleVideoURL = dataDict[@"video"];
    } else if (dataDict[@"video_url"] && [dataDict[@"video_url"] length] > 0) {
        singleVideoURL = dataDict[@"video_url"];
    }

    // 确保处理空的videos数组
    BOOL hasVideos = [videos isKindOfClass:[NSArray class]] && videos.count > 0;
    BOOL hasImages = [images isKindOfClass:[NSArray class]] && images.count > 0;
    BOOL hasImgArray = [imgArray isKindOfClass:[NSArray class]] && imgArray.count > 0;

    BOOL shouldShowQualityOptions = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYShowAllVideoQuality"];

    // 如果只有图片没有视频，直接处理图片下载
    if (!hasVideos && singleVideoURL == nil && (hasImages || hasImgArray || coverURL != nil)) {
        NSMutableArray *allImages = [NSMutableArray array];
        if (hasImages)
            [allImages addObjectsFromArray:images];
        if (hasImgArray)
            [allImages addObjectsFromArray:imgArray];
        if (coverURL && coverURL.length > 0 && ![allImages containsObject:coverURL]) {
            [allImages addObject:coverURL];
        }

        if (allImages.count > 0) {
            if (allImages.count == 1) {
                // 单张图片直接下载
                NSURL *imageDownloadUrl = [NSURL URLWithString:allImages[0]];
                [self downloadMedia:imageDownloadUrl
                          mediaType:MediaTypeImage
                              audio:nil
                         completion:^(BOOL success) {
                           if (!success) {
                               [DYYYUtils showToast:@"图片下载失败"];
                           }
                         }];
            } else {
                // 多张图片批量下载
                [self downloadAllImages:allImages];
            }
            return;
        }
    }

    // 单个视频情况下的处理
    if (shouldShowQualityOptions && singleVideoURL && singleVideoURL.length > 0) {
        AWEUserActionSheetView *actionSheet = [[NSClassFromString(@"AWEUserActionSheetView") alloc] init];
        NSMutableArray *actions = [NSMutableArray array];

        AWEUserSheetAction *videoAction = [NSClassFromString(@"AWEUserSheetAction") actionWithTitle:@"下载视频"
                                                                                            imgName:nil
                                                                                            handler:^{
                                                                                              NSURL *videoDownloadUrl = [NSURL URLWithString:singleVideoURL];
                                                                                              NSURL *optionalAudioURL = nil;
                                                                                              if (musicURL.length > 0) {
                                                                                                  optionalAudioURL = [NSURL URLWithString:musicURL];
                                                                                              }
                                                                                              [self downloadMedia:videoDownloadUrl
                                                                                                        mediaType:MediaTypeVideo
                                                                                                            audio:optionalAudioURL
                                                                                                       completion:^(BOOL success) {
                                                                                                         if (!success) {
                                                                                                         }
                                                                                                       }];
                                                                                            }];
        [actions addObject:videoAction];

        if (coverURL && coverURL.length > 0) {
            AWEUserSheetAction *coverAction = [NSClassFromString(@"AWEUserSheetAction") actionWithTitle:@"下载封面图"
                                                                                                imgName:nil
                                                                                                handler:^{
                                                                                                  NSURL *imageDownloadUrl = [NSURL URLWithString:coverURL];
                                                                                                  [self downloadMedia:imageDownloadUrl
                                                                                                            mediaType:MediaTypeImage
                                                                                                                audio:nil
                                                                                                           completion:^(BOOL success) {
                                                                                                             if (!success) {
                                                                                                             }
                                                                                                           }];
                                                                                                }];
            [actions addObject:coverAction];
        }

        if (musicURL && musicURL.length > 0) {
            AWEUserSheetAction *musicAction = [NSClassFromString(@"AWEUserSheetAction") actionWithTitle:@"下载背景音乐"
                                                                                                imgName:nil
                                                                                                handler:^{
                                                                                                  NSURL *audioDownloadUrl = [NSURL URLWithString:musicURL];
                                                                                                  [self downloadMedia:audioDownloadUrl
                                                                                                            mediaType:MediaTypeAudio
                                                                                                                audio:nil
                                                                                                           completion:^(BOOL success) {
                                                                                                             if (!success) {
                                                                                                             }
                                                                                                           }];
                                                                                                }];
            [actions addObject:musicAction];
        }

        // 添加批量下载选项
        NSMutableArray *allImages = [NSMutableArray array];
        if (hasImages)
            [allImages addObjectsFromArray:images];
        if (hasImgArray)
            [allImages addObjectsFromArray:imgArray];
        if (coverURL && coverURL.length > 0 && ![allImages containsObject:coverURL]) {
            [allImages addObject:coverURL];
        }

        if (allImages.count > 0 || singleVideoURL.length > 0) {
            AWEUserSheetAction *batchDownloadAction = [NSClassFromString(@"AWEUserSheetAction") actionWithTitle:@"批量下载所有资源"
                                                                                                        imgName:nil
                                                                                                        handler:^{
                                                                                                          NSMutableArray *singleVideoArray = nil;
                                                                                                          if (singleVideoURL.length > 0) {
                                                                                                              singleVideoArray = [NSMutableArray arrayWithObject:@{@"url" : singleVideoURL}];
                                                                                                          }
                                                                                                          [self batchDownloadResources:singleVideoArray images:allImages];
                                                                                                        }];
            [actions addObject:batchDownloadAction];
        }

        if (actions.count > 0) {
            [actionSheet setActions:actions];
            [actionSheet show];
            return;
        }
    }

    if (!shouldShowQualityOptions && singleVideoURL && singleVideoURL.length > 0) {
        NSURL *videoDownloadUrl = [NSURL URLWithString:singleVideoURL];
        NSURL *optionalAudioURL = nil;
        if (musicURL.length > 0) {
            optionalAudioURL = [NSURL URLWithString:musicURL];
        }
        [self downloadMedia:videoDownloadUrl
                  mediaType:MediaTypeVideo
                      audio:optionalAudioURL
                 completion:^(BOOL success) {
                   if (!success) {
                   }
                 }];
        return;
    }

    // 如果前面的条件都不满足，尝试批量下载所有资源
    NSMutableArray *allImages = [NSMutableArray array];
    if (hasImages)
        [allImages addObjectsFromArray:images];
    if (hasImgArray)
        [allImages addObjectsFromArray:imgArray];
    if (coverURL && coverURL.length > 0 && ![allImages containsObject:coverURL]) {
        [allImages addObject:coverURL];
    }

    if (allImages.count > 0 || hasVideos) {
        [self batchDownloadResources:videos images:allImages];
    } else {
        [DYYYUtils showToast:@"没有找到可下载的资源"];
    }
}

#define DYYYLogVideo(format, ...) NSLog((@"[DYYY视频合成] " format), ##__VA_ARGS__)
// 创建视频合成器从多种媒体源
+ (void)createVideoFromMedia:(NSArray<NSString *> *)imageURLs
                  livePhotos:(NSArray<NSDictionary *> *)livePhotos
                      bgmURL:(NSString *)bgmURL
                    progress:(void (^)(NSInteger current, NSInteger total, NSString *status))progressBlock
                  completion:(void (^)(BOOL success, NSString *message))completion {
    DYYYLogVideo(@"开始创建视频 - 图片数量: %lu, 实况照片数量: %lu, 背景音乐: %@", (unsigned long)imageURLs.count, (unsigned long)livePhotos.count, bgmURL.length > 0 ? @"有" : @"无");

    if ((imageURLs.count == 0 && livePhotos.count == 0) || (imageURLs == nil && livePhotos == nil)) {
        DYYYLogVideo(@"错误: 没有提供媒体资源");
        if (completion) {
            completion(NO, @"没有提供媒体资源");
        }
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
      CGRect screenBounds = [UIScreen mainScreen].bounds;
      DYYYToast *progressView = [[DYYYToast alloc] initWithFrame:screenBounds];
      [progressView show];

      progressView.cancelBlock = ^{
        DYYYLogVideo(@"用户取消了视频合成");
        [self cancelAllDownloads];
        if (completion) {
            completion(NO, @"用户取消了操作");
        }
      };

      // 创建临时目录
      NSString *mediaPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"VideoComposition"];
      NSFileManager *fileManager = [NSFileManager defaultManager];
      if ([fileManager fileExistsAtPath:mediaPath]) {
          DYYYLogVideo(@"正在清理旧的临时目录: %@", mediaPath);
          [fileManager removeItemAtPath:mediaPath error:nil];
      }

      NSError *dirError = nil;
      [fileManager createDirectoryAtPath:mediaPath withIntermediateDirectories:YES attributes:nil error:&dirError];
      if (dirError) {
          DYYYLogVideo(@"创建临时目录失败: %@", dirError);
          if (completion) {
              completion(NO, @"创建临时文件夹失败");
          }
          return;
      }
      DYYYLogVideo(@"成功创建临时目录: %@", mediaPath);

      // 计算总共需要下载的文件数和合成步骤
      NSInteger totalImages = imageURLs.count;
      NSInteger totalLivePhotos = livePhotos.count * 2;  // 每个实况照片有2个文件
      NSInteger hasBGM = (bgmURL.length > 0) ? 1 : 0;

      // 总步骤：下载所有媒体 + 合成视频 + 保存视频
      NSInteger totalSteps = totalImages + totalLivePhotos + hasBGM + 2;
      __block NSInteger completedSteps = 0;

      // 储存下载的媒体文件路径
      NSMutableArray *imageFilePaths = [NSMutableArray array];
      NSMutableArray<NSDictionary *> *livePhotoFilePaths = [NSMutableArray array];
      __block NSString *bgmFilePath = nil;

      void (^updateProgress)(NSString *) = ^(NSString *status) {
        float progress = (float)completedSteps / totalSteps;
        dispatch_async(dispatch_get_main_queue(), ^{
          [progressView setProgress:progress];
          DYYYLogVideo(@"进度更新: %.2f%% - %@", progress * 100, status);
          if (progressBlock) {
              progressBlock(completedSteps, totalSteps, status);
          }
        });
      };

      // 第一阶段：下载所有普通图片
      dispatch_group_t imageDownloadGroup = dispatch_group_create();
      updateProgress(@"正在下载图片...");

      for (NSInteger i = 0; i < imageURLs.count; i++) {
          NSString *imageURLString = imageURLs[i];
          NSURL *imageURL = [NSURL URLWithString:imageURLString];

          if (!imageURL) {
              DYYYLogVideo(@"图片URL无效: %@", imageURLString);
              completedSteps++;
              updateProgress(@"图片URL无效");
              continue;
          }

          dispatch_group_enter(imageDownloadGroup);

          // 创建文件路径
          NSString *uniqueID = [NSUUID UUID].UUIDString;
          NSString *imagePath = [mediaPath stringByAppendingPathComponent:[NSString stringWithFormat:@"image_%@.jpg", uniqueID]];
          DYYYLogVideo(@"开始下载图片 %ld/%ld: %@", (long)(i + 1), (long)imageURLs.count, imageURLString);

          // 配置下载会话
          NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
          NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];

          NSURLSessionDataTask *imageTask = [session dataTaskWithURL:imageURL
                                                   completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                                                     if (error) {
                                                         DYYYLogVideo(@"下载图片失败 %ld/%ld: %@", (long)(i + 1), (long)imageURLs.count, error);
                                                     } else if (!data) {
                                                         DYYYLogVideo(@"下载图片数据为空 %ld/%ld", (long)(i + 1), (long)imageURLs.count);
                                                     } else {
                                                         NSInteger dataSize = data.length;
                                                         if ([data writeToFile:imagePath atomically:YES]) {
                                                             DYYYLogVideo(@"成功下载并保存图片 %ld/%ld: %@ (大小: %.2f KB)", (long)(i + 1), (long)imageURLs.count, imagePath, dataSize / 1024.0);
                                                             [imageFilePaths addObject:imagePath];
                                                         } else {
                                                             DYYYLogVideo(@"保存图片文件失败 %ld/%ld: %@", (long)(i + 1), (long)imageURLs.count, imagePath);
                                                         }
                                                     }

                                                     completedSteps++;
                                                     updateProgress([NSString stringWithFormat:@"已下载图片 %ld/%ld", (long)(i + 1), (long)imageURLs.count]);
                                                     dispatch_group_leave(imageDownloadGroup);
                                                   }];

          [imageTask resume];
      }

      // 第二阶段：下载所有实况照片
      dispatch_group_t livePhotoDownloadGroup = dispatch_group_create();

      dispatch_group_notify(imageDownloadGroup, dispatch_get_main_queue(), ^{
        DYYYLogVideo(@"第一阶段完成，已下载 %ld 张图片", (long)imageFilePaths.count);
        updateProgress(@"正在下载实况照片...");
        DYYYLogVideo(@"开始第二阶段: 下载实况照片 (%ld 项)", (long)livePhotos.count);

        for (NSInteger i = 0; i < livePhotos.count; i++) {
            NSDictionary *livePhoto = livePhotos[i];
            NSString *imageURLString = livePhoto[@"imageURL"];
            NSString *videoURLString = livePhoto[@"videoURL"];
            NSURL *imageURL = [NSURL URLWithString:imageURLString];
            NSURL *videoURL = [NSURL URLWithString:videoURLString];

            if (!imageURL || !videoURL) {
                DYYYLogVideo(@"实况照片URL无效: 图片=%@, 视频=%@", imageURLString, videoURLString);
                completedSteps += 2;
                updateProgress(@"实况照片URL无效");
                continue;
            }

            NSString *uniqueID = [NSUUID UUID].UUIDString;
            NSString *imagePath = [mediaPath stringByAppendingPathComponent:[NSString stringWithFormat:@"livephoto_img_%@.jpg", uniqueID]];
            NSString *videoPath = [mediaPath stringByAppendingPathComponent:[NSString stringWithFormat:@"livephoto_vid_%@.mp4", uniqueID]];

            // 下载图片部分
            dispatch_group_enter(livePhotoDownloadGroup);
            NSURLSessionConfiguration *imgConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
            NSURLSession *imgSession = [NSURLSession sessionWithConfiguration:imgConfig];

            DYYYLogVideo(@"开始下载实况照片图片部分 %ld/%ld: %@", (long)(i + 1), (long)livePhotos.count, imageURLString);
            NSURLSessionDataTask *imageTask =
                [imgSession dataTaskWithURL:imageURL
                          completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                            if (error) {
                                DYYYLogVideo(@"下载实况照片图片部分失败 %ld/%ld: %@", (long)(i + 1), (long)livePhotos.count, error);
                            } else if (!data) {
                                DYYYLogVideo(@"下载实况照片图片数据为空 %ld/%ld", (long)(i + 1), (long)livePhotos.count);
                            } else if ([data writeToFile:imagePath atomically:YES]) {
                                DYYYLogVideo(@"成功保存实况照片图片部分 %ld/%ld: %@ (大小: %.2f KB)", (long)(i + 1), (long)livePhotos.count, imagePath, data.length / 1024.0);
                            } else {
                                DYYYLogVideo(@"保存实况照片图片文件失败 %ld/%ld: %@", (long)(i + 1), (long)livePhotos.count, imagePath);
                            }

                            completedSteps++;
                            updateProgress([NSString stringWithFormat:@"已下载实况照片(图片) %ld/%ld", (long)(i + 1), (long)livePhotos.count]);
                            dispatch_group_leave(livePhotoDownloadGroup);
                          }];

            // 下载视频部分
            dispatch_group_enter(livePhotoDownloadGroup);
            NSURLSessionConfiguration *vidConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
            NSURLSession *vidSession = [NSURLSession sessionWithConfiguration:vidConfig];

            DYYYLogVideo(@"开始下载实况照片视频部分 %ld/%ld: %@", (long)(i + 1), (long)livePhotos.count, videoURLString);
            NSURLSessionDataTask *videoTask =
                [vidSession dataTaskWithURL:videoURL
                          completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                            if (error) {
                                DYYYLogVideo(@"下载实况照片视频部分失败 %ld/%ld: %@", (long)(i + 1), (long)livePhotos.count, error);
                            } else if (!data) {
                                DYYYLogVideo(@"下载实况照片视频数据为空 %ld/%ld", (long)(i + 1), (long)livePhotos.count);
                            } else if ([data writeToFile:videoPath atomically:YES]) {
                                DYYYLogVideo(@"成功保存实况照片视频部分 %ld/%ld: %@ (大小: %.2f MB)", (long)(i + 1), (long)livePhotos.count, videoPath, data.length / (1024.0 * 1024.0));
                                @synchronized(livePhotoFilePaths) {
                                    [livePhotoFilePaths addObject:@{@"image" : imagePath, @"video" : videoPath}];
                                    DYYYLogVideo(@"成功记录实况照片对: 图片=%@, 视频=%@", imagePath, videoPath);
                                }
                            } else {
                                DYYYLogVideo(@"保存实况照片视频文件失败 %ld/%ld: %@", (long)(i + 1), (long)livePhotos.count, videoPath);
                            }

                            completedSteps++;
                            updateProgress([NSString stringWithFormat:@"已下载实况照片(视频) %ld/%ld", (long)(i + 1), (long)livePhotos.count]);
                            dispatch_group_leave(livePhotoDownloadGroup);
                          }];

            [imageTask resume];
            [videoTask resume];
        }

        // 第三阶段：下载背景音乐
        dispatch_group_t bgmDownloadGroup = dispatch_group_create();

        dispatch_group_notify(livePhotoDownloadGroup, dispatch_get_main_queue(), ^{
          DYYYLogVideo(@"第二阶段完成，已下载 %ld 组实况照片", (long)livePhotoFilePaths.count);

          if (bgmURL.length > 0) {
              DYYYLogVideo(@"开始第三阶段: 下载背景音乐 %@", bgmURL);
              updateProgress(@"正在下载背景音乐...");
              NSURL *bgmURL_obj = [NSURL URLWithString:bgmURL];

              if (!bgmURL_obj) {
                  DYYYLogVideo(@"背景音乐URL无效: %@", bgmURL);
                  completedSteps++;
                  updateProgress(@"背景音乐URL无效");
              } else {
                  dispatch_group_enter(bgmDownloadGroup);

                  // 创建文件路径
                  NSString *uniqueID = [NSUUID UUID].UUIDString;
                  NSString *audioPath = [mediaPath stringByAppendingPathComponent:[NSString stringWithFormat:@"bgm_%@.mp3", uniqueID]];

                  // 配置下载会话
                  NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
                  NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];

                  NSURLSessionDataTask *audioTask = [session dataTaskWithURL:bgmURL_obj
                                                           completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                                                             if (error) {
                                                                 DYYYLogVideo(@"下载背景音乐失败: %@", error);
                                                             } else if (!data) {
                                                                 DYYYLogVideo(@"下载背景音乐数据为空");
                                                             } else if ([data writeToFile:audioPath atomically:YES]) {
                                                                 DYYYLogVideo(@"成功保存背景音乐: %@ (大小: %.2f MB)", audioPath, data.length / (1024.0 * 1024.0));
                                                                 bgmFilePath = audioPath;
                                                             } else {
                                                                 DYYYLogVideo(@"保存背景音乐文件失败: %@", audioPath);
                                                             }

                                                             completedSteps++;
                                                             updateProgress(@"背景音乐下载完成");
                                                             dispatch_group_leave(bgmDownloadGroup);
                                                           }];

                  [audioTask resume];
              }
          }

          // 第四阶段：合成视频
          dispatch_group_notify(bgmDownloadGroup, dispatch_get_main_queue(), ^{
            DYYYLogVideo(@"第三阶段完成，背景音乐状态: %@", bgmFilePath ? @"已下载" : @"无或下载失败");
            DYYYLogVideo(@"开始第四阶段: 合成视频");
            updateProgress(@"正在合成视频...");

            // 如果没有成功下载任何媒体，则退出
            if (imageFilePaths.count == 0 && livePhotoFilePaths.count == 0) {
                DYYYLogVideo(@"错误: 没有成功下载任何媒体文件，取消合成");
                progressView.allowSuccessAnimation = NO;
                [progressView dismiss];
                if (completion) {
                    completion(NO, @"没有成功下载任何媒体文件");
                }
                [fileManager removeItemAtPath:mediaPath error:nil];
                return;
            }

            DYYYLogVideo(@"媒体文件统计: %ld张图片, %ld组实况照片, 背景音乐: %@", (long)imageFilePaths.count, (long)livePhotoFilePaths.count, bgmFilePath ? @"有" : @"无");

            NSString *outputPath = [mediaPath stringByAppendingPathComponent:[NSString stringWithFormat:@"final_%@.mp4", [NSUUID UUID].UUIDString]];
            DYYYLogVideo(@"视频输出路径: %@", outputPath);

            // 使用AVFoundation合成视频
            [self composeVideo:imageFilePaths
                    livePhotos:livePhotoFilePaths
                       bgmPath:bgmFilePath
                    outputPath:outputPath
                    completion:^(BOOL success) {
                      completedSteps++;
                      if (success) {
                          DYYYLogVideo(@"视频合成成功");
                      } else {
                          DYYYLogVideo(@"视频合成失败");
                      }
                      updateProgress(@"视频合成完成");

                      if (success) {
                          DYYYLogVideo(@"开始保存视频到相册");
                          [[PHPhotoLibrary sharedPhotoLibrary]
                              performChanges:^{
                                [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:[NSURL fileURLWithPath:outputPath]];
                              }
                              completionHandler:^(BOOL success, NSError *_Nullable error) {
                                completedSteps++;

                                dispatch_async(dispatch_get_main_queue(), ^{
                                  progressView.allowSuccessAnimation = success;
                                  [progressView dismiss];

                                  if (success) {
                                      DYYYLogVideo(@"视频已成功保存到相册");
                                      if (completion) {
                                          completion(YES, @"视频已成功保存到相册");
                                      }
                                  } else {
                                      DYYYLogVideo(@"保存视频到相册失败: %@", error);
                                      if (completion) {
                                          completion(NO, [NSString stringWithFormat:@"保存视频到相册失败: %@", error.localizedDescription]);
                                      }
                                  }

                                  DYYYLogVideo(@"清理临时文件: %@", mediaPath);
                                  [fileManager removeItemAtPath:mediaPath error:nil];
                                });
                              }];
                      } else {
                          dispatch_async(dispatch_get_main_queue(), ^{
                            progressView.allowSuccessAnimation = NO;
                            [progressView dismiss];
                            if (completion) {
                                completion(NO, @"视频合成失败");
                            }

                            DYYYLogVideo(@"清理临时文件: %@", mediaPath);
                            [fileManager removeItemAtPath:mediaPath error:nil];
                          });
                      }
                    }];
          });
        });
      });
    });
}

// 视频合成核心方法
+ (void)composeVideo:(NSArray<NSString *> *)imageFiles
          livePhotos:(NSArray<NSDictionary *> *)livePhotoFiles
             bgmPath:(NSString *)bgmPath
          outputPath:(NSString *)outputPath
          completion:(void (^)(BOOL success))completion {
    // 视频尺寸（标准1080p）
    CGSize videoSize = CGSizeMake(1080, 1920);
    DYYYLogVideo(@"开始合成视频 - 目标尺寸: %.0fx%.0f", videoSize.width, videoSize.height);
    DYYYLogVideo(@"媒体源: %ld张图片, %ld组实况照片, 背景音乐: %@", (long)imageFiles.count, (long)livePhotoFiles.count, bgmPath ? @"有" : @"无");

    dispatch_group_t processingGroup = dispatch_group_create();

    // 存储所有媒体片段信息
    NSMutableArray *mediaSegments = [NSMutableArray array];

    // 处理静态图片 - 先将所有图片转换为临时视频片段
    for (NSInteger i = 0; i < imageFiles.count; i++) {
        NSString *imagePath = imageFiles[i];
        if (![[NSFileManager defaultManager] fileExistsAtPath:imagePath]) {
            DYYYLogVideo(@"错误: 图片文件不存在: %@", imagePath);
            continue;
        }

        UIImage *image = [UIImage imageWithContentsOfFile:imagePath];
        if (!image) {
            DYYYLogVideo(@"错误: 无法加载图片: %@", imagePath);
            continue;
        }
        DYYYLogVideo(@"处理图片 %ld/%ld: 尺寸 %.0fx%.0f", (long)(i + 1), (long)imageFiles.count, image.size.width, image.size.height);

        // 创建临时视频文件路径
        NSString *tempVideoPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"temp_img_%@.mp4", [NSUUID UUID].UUIDString]];

        dispatch_group_enter(processingGroup);

        // 使用Core Animation创建静态图片视频
        [self createVideoFromImage:image
                          duration:5.0
                        outputPath:tempVideoPath
                        completion:^(BOOL success) {
                          if (success) {
                              @synchronized(mediaSegments) {
                                  [mediaSegments addObject:@{@"type" : @"image", @"path" : tempVideoPath, @"duration" : @5.0}];
                                  DYYYLogVideo(@"成功创建图片视频片段 %ld/%ld: %@", (long)(i + 1), (long)imageFiles.count, tempVideoPath);
                              }
                          } else {
                              DYYYLogVideo(@"错误: 创建图片视频片段失败 %ld/%ld", (long)(i + 1), (long)imageFiles.count);
                          }
                          dispatch_group_leave(processingGroup);
                        }];
    }

    // 处理实况照片 - 收集所有视频路径信息
    for (NSInteger i = 0; i < livePhotoFiles.count; i++) {
        NSDictionary *livePhoto = livePhotoFiles[i];
        NSString *imagePath = livePhoto[@"image"];
        NSString *videoPath = livePhoto[@"video"];

        DYYYLogVideo(@"处理实况照片 %ld/%ld: 图片=%@, 视频=%@", (long)(i + 1), (long)livePhotoFiles.count, imagePath, videoPath);

        if (![[NSFileManager defaultManager] fileExistsAtPath:videoPath]) {
            DYYYLogVideo(@"错误: 实况照片视频不存在: %@", videoPath);
            continue;
        }

        [mediaSegments addObject:@{@"type" : @"video", @"path" : videoPath}];
        DYYYLogVideo(@"成功添加实况照片视频片段 %ld/%ld", (long)(i + 1), (long)livePhotoFiles.count);
    }

    // 等待所有临时视频处理完成
    dispatch_group_notify(processingGroup, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      DYYYLogVideo(@"所有媒体处理完成，共有 %ld 个可用片段", (long)mediaSegments.count);

      if (mediaSegments.count == 0) {
          DYYYLogVideo(@"错误: 没有有效的媒体片段可以合成");
          if (completion) {
              dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO);
              });
          }
          return;
      }

      // 创建AVMutableComposition作为容器
      DYYYLogVideo(@"开始创建视频合成容器");
      AVMutableComposition *composition = [AVMutableComposition composition];
      AVMutableVideoComposition *videoComposition = [AVMutableVideoComposition videoComposition];
      videoComposition.frameDuration = CMTimeMake(1, 30);  // 30fps
      videoComposition.renderSize = videoSize;

      // 创建视频轨道
      AVMutableCompositionTrack *videoTrack = [composition addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
      if (!videoTrack) {
          DYYYLogVideo(@"错误: 无法创建视频轨道");
          if (completion) {
              dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO);
              });
          }
          return;
      }

      // 创建音频轨道
      AVMutableCompositionTrack *audioTrack = [composition addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];
      if (!audioTrack) {
          DYYYLogVideo(@"错误: 无法创建音频轨道");
          if (completion) {
              dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO);
              });
          }
          return;
      }

      // 添加背景音乐
      __block CMTime currentTime = kCMTimeZero;
      if (bgmPath && [[NSFileManager defaultManager] fileExistsAtPath:bgmPath]) {
          DYYYLogVideo(@"添加背景音乐: %@", bgmPath);
          AVAsset *audioAsset = [AVAsset assetWithURL:[NSURL fileURLWithPath:bgmPath]];
          AVAssetTrack *audioAssetTrack = [[audioAsset tracksWithMediaType:AVMediaTypeAudio] firstObject];

          if (audioAssetTrack) {
              // 先处理所有视频片段以确定总时长
              CMTime totalDuration = kCMTimeZero;
              for (NSDictionary *segment in mediaSegments) {
                  NSString *segmentPath = segment[@"path"];
                  AVAsset *asset = [AVAsset assetWithURL:[NSURL fileURLWithPath:segmentPath]];
                  totalDuration = CMTimeAdd(totalDuration, asset.duration);
              }

              // 循环播放背景音乐直到覆盖整个视频时长
              CMTime audioDuration = audioAsset.duration;
              CMTime currentAudioTime = kCMTimeZero;

              if (CMTimeCompare(audioDuration, totalDuration) < 0) {
                  DYYYLogVideo(@"背景音乐时长(%.2f秒)小于视频时长(%.2f秒)，将循环播放", CMTimeGetSeconds(audioDuration), CMTimeGetSeconds(totalDuration));

                  while (CMTimeCompare(currentAudioTime, totalDuration) < 0) {
                      // 确定当前片段的时长（如果到达视频末尾则截断）
                      CMTime remainingTime = CMTimeSubtract(totalDuration, currentAudioTime);
                      CMTime segmentDuration = audioDuration;

                      if (CMTimeCompare(remainingTime, audioDuration) < 0) {
                          segmentDuration = remainingTime;
                      }

                      // 插入音频片段
                      NSError *audioError = nil;
                      [audioTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, segmentDuration) ofTrack:audioAssetTrack atTime:currentAudioTime error:&audioError];

                      if (audioError) {
                          DYYYLogVideo(@"添加背景音乐循环片段失败: %@", audioError);
                          break;
                      }

                      DYYYLogVideo(@"添加背景音乐循环片段 - 位置: %.2f秒, 时长: %.2f秒", CMTimeGetSeconds(currentAudioTime), CMTimeGetSeconds(segmentDuration));

                      // 更新当前音频时间点
                      currentAudioTime = CMTimeAdd(currentAudioTime, segmentDuration);
                  }

                  DYYYLogVideo(@"成功添加循环背景音乐，总时长: %.2f秒", CMTimeGetSeconds(currentAudioTime));
              } else {
                  // 音乐长度足够，直接添加
                  NSError *audioError = nil;
                  [audioTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, totalDuration) ofTrack:audioAssetTrack atTime:kCMTimeZero error:&audioError];

                  if (audioError) {
                      DYYYLogVideo(@"添加背景音乐失败: %@", audioError);
                  } else {
                      DYYYLogVideo(@"成功添加背景音乐，时长: %.2f秒", CMTimeGetSeconds(totalDuration));
                  }
              }
          } else {
              DYYYLogVideo(@"错误: 背景音乐没有有效的音轨");
          }
      }

      NSMutableArray *instructions = [NSMutableArray array];

      // 处理所有媒体片段（按顺序）
      DYYYLogVideo(@"开始按顺序处理 %ld 个媒体片段", (long)mediaSegments.count);
      for (NSInteger i = 0; i < mediaSegments.count; i++) {
          NSDictionary *segment = mediaSegments[i];
          NSString *segmentType = segment[@"type"];
          NSString *segmentPath = segment[@"path"];

          DYYYLogVideo(@"处理片段 %ld/%ld: 类型=%@, 路径=%@", (long)(i + 1), (long)mediaSegments.count, segmentType, segmentPath);

          AVAsset *asset = [AVAsset assetWithURL:[NSURL fileURLWithPath:segmentPath]];
          NSArray<AVAssetTrack *> *videoTracks = [asset tracksWithMediaType:AVMediaTypeVideo];

          if (videoTracks.count == 0) {
              DYYYLogVideo(@"错误: 媒体片段没有视频轨道: %@", segmentPath);
              continue;
          }

          AVAssetTrack *assetVideoTrack = videoTracks.firstObject;
          CMTime assetDuration = asset.duration;
          DYYYLogVideo(@"片段 %ld/%ld: 时长=%.2f秒, 尺寸=%.0fx%.0f", (long)(i + 1), (long)mediaSegments.count, CMTimeGetSeconds(assetDuration), assetVideoTrack.naturalSize.width,
                       assetVideoTrack.naturalSize.height);

          // 插入视频片段
          NSError *insertError = nil;
          [videoTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, assetDuration) ofTrack:assetVideoTrack atTime:currentTime error:&insertError];

          if (insertError) {
              DYYYLogVideo(@"插入视频片段失败: %@", insertError);
              continue;
          } else {
              DYYYLogVideo(@"成功插入视频片段 %ld/%ld 到位置 %.2f秒", (long)(i + 1), (long)mediaSegments.count, CMTimeGetSeconds(currentTime));
          }

          // 创建视频合成指令
          AVMutableVideoCompositionInstruction *instruction = [AVMutableVideoCompositionInstruction videoCompositionInstruction];
          instruction.timeRange = CMTimeRangeMake(currentTime, assetDuration);

          AVMutableVideoCompositionLayerInstruction *layerInstruction = [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:videoTrack];

          // 计算适当的视频变换
          CGAffineTransform transform = [DYYYUtils transformForAssetTrack:assetVideoTrack targetSize:videoSize];
          [layerInstruction setTransform:transform atTime:currentTime];

          instruction.layerInstructions = @[ layerInstruction ];
          [instructions addObject:instruction];
          DYYYLogVideo(@"添加合成指令: 时间范围=%.2f到%.2f秒", CMTimeGetSeconds(currentTime), CMTimeGetSeconds(CMTimeAdd(currentTime, assetDuration)));

          // 更新时间点
          currentTime = CMTimeAdd(currentTime, assetDuration);
      }

      // 设置合成指令
      videoComposition.instructions = instructions;
      DYYYLogVideo(@"设置了 %ld 个视频合成指令，总时长: %.2f秒", (long)instructions.count, CMTimeGetSeconds(currentTime));

      // 检查是否有内容需要导出
      if (instructions.count == 0 || CMTimeGetSeconds(currentTime) < 0.1) {
          DYYYLogVideo(@"错误: 没有足够的内容可以导出");
          if (completion) {
              dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO);
              });
          }

          for (NSDictionary *segment in mediaSegments) {
              if ([segment[@"type"] isEqualToString:@"image"]) {
                  [[NSFileManager defaultManager] removeItemAtPath:segment[@"path"] error:nil];
                  DYYYLogVideo(@"清理临时图片视频文件: %@", segment[@"path"]);
              }
          }
          return;
      }

      // 设置导出会话
      DYYYLogVideo(@"创建视频导出会话，使用最高质量编码");
      AVAssetExportSession *exportSession = [[AVAssetExportSession alloc] initWithAsset:composition presetName:AVAssetExportPresetHighestQuality];
      if (!exportSession) {
          DYYYLogVideo(@"错误: 创建导出会话失败");
          if (completion) {
              dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO);
              });
          }
          return;
      }

      exportSession.videoComposition = videoComposition;
      exportSession.outputURL = [NSURL fileURLWithPath:outputPath];
      exportSession.outputFileType = AVFileTypeMPEG4;
      exportSession.shouldOptimizeForNetworkUse = YES;

      // 导出视频
      DYYYLogVideo(@"开始导出视频到: %@", outputPath);
      [exportSession exportAsynchronouslyWithCompletionHandler:^{
        for (NSDictionary *segment in mediaSegments) {
            if ([segment[@"type"] isEqualToString:@"image"]) {
                NSError *removeError = nil;
                [[NSFileManager defaultManager] removeItemAtPath:segment[@"path"] error:&removeError];
                if (removeError) {
                    DYYYLogVideo(@"清理临时文件失败: %@, 错误: %@", segment[@"path"], removeError);
                } else {
                    DYYYLogVideo(@"清理临时图片视频文件: %@", segment[@"path"]);
                }
            }
        }
        switch (exportSession.status) {
            case AVAssetExportSessionStatusCompleted: {
                DYYYLogVideo(@"视频导出成功: %@", outputPath);

                NSDictionary *fileAttrs = [[NSFileManager defaultManager] attributesOfItemAtPath:outputPath error:nil];
                if (fileAttrs) {
                    unsigned long long fileSize = [fileAttrs fileSize];
                    DYYYLogVideo(@"导出视频大小: %.2f MB", fileSize / (1024.0 * 1024.0));
                }

                if (completion) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                      completion(YES);
                    });
                }
                break;
            }

            case AVAssetExportSessionStatusFailed: {
                DYYYLogVideo(@"导出视频失败: %@", exportSession.error);
                if (completion) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                      completion(NO);
                    });
                }
                break;
            }

            case AVAssetExportSessionStatusCancelled: {
                DYYYLogVideo(@"导出视频被取消");
                if (completion) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                      completion(NO);
                    });
                }
                break;
            }

            default: {
                DYYYLogVideo(@"导出视频结束，状态码: %ld", (long)exportSession.status);
                if (completion) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                      completion(NO);
                    });
                }
                break;
            }
        }
      }];
    });
}

// 创建从静态图片生成的视频片段
+ (void)createVideoFromImage:(UIImage *)image duration:(float)duration outputPath:(NSString *)outputPath completion:(void (^)(BOOL success))completion {
    [[self shared] enqueueMediaJob:^(dispatch_block_t jobDone) {
        void (^complete)(BOOL) = ^(BOOL success) {
            jobDone();
            if (completion) completion(success);
        };
        CGSize videoSize = CGSizeMake(1080, 1920);
        NSInteger frameRate = 30;
        if (!image.CGImage || !isfinite(duration) || duration <= 0 || duration > (double)NSIntegerMax / frameRate) { complete(NO); return; }
        NSInteger totalFrames = (NSInteger)(duration * frameRate);
        if (totalFrames <= 0) { complete(NO); return; }
        NSError *error = nil;
        AVAssetWriter *writer = [[AVAssetWriter alloc] initWithURL:[NSURL fileURLWithPath:outputPath] fileType:AVFileTypeMPEG4 error:&error];
        if (!writer) { complete(NO); return; }
        NSDictionary *settings = @{AVVideoCodecKey:AVVideoCodecTypeH264, AVVideoWidthKey:@1080, AVVideoHeightKey:@1920,
            AVVideoCompressionPropertiesKey:@{AVVideoAverageBitRateKey:@6000000, AVVideoProfileLevelKey:AVVideoProfileLevelH264HighAutoLevel}};
        AVAssetWriterInput *input = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:settings];
        input.expectsMediaDataInRealTime = NO;
        NSDictionary *attributes = @{(NSString *)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_32ARGB),
            (NSString *)kCVPixelBufferWidthKey:@1080, (NSString *)kCVPixelBufferHeightKey:@1920,
            (NSString *)kCVPixelBufferCGImageCompatibilityKey:@YES, (NSString *)kCVPixelBufferCGBitmapContextCompatibilityKey:@YES};
        AVAssetWriterInputPixelBufferAdaptor *adaptor = [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:input sourcePixelBufferAttributes:attributes];
        if (![writer canAddInput:input]) { complete(NO); return; }
        [writer addInput:input];
        if (![writer startWriting]) { complete(NO); return; }
        [writer startSessionAtSourceTime:kCMTimeZero];
        CVPixelBufferRef pixelBuffer = NULL;
        if (adaptor.pixelBufferPool) CVPixelBufferPoolCreatePixelBuffer(NULL, adaptor.pixelBufferPool, &pixelBuffer);
        if (!pixelBuffer) CVPixelBufferCreate(kCFAllocatorDefault, 1080, 1920, kCVPixelFormatType_32ARGB, (__bridge CFDictionaryRef)attributes, &pixelBuffer);
        if (!pixelBuffer) { [writer cancelWriting]; complete(NO); return; }
        CVPixelBufferLockBaseAddress(pixelBuffer, 0);
        CGColorSpaceRef colors = CGColorSpaceCreateDeviceRGB();
        CGContextRef context = CGBitmapContextCreate(CVPixelBufferGetBaseAddress(pixelBuffer), 1080, 1920, 8, CVPixelBufferGetBytesPerRow(pixelBuffer), colors, kCGImageAlphaPremultipliedFirst);
        CGColorSpaceRelease(colors);
        if (!context) {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
            CVPixelBufferRelease(pixelBuffer);
            [writer cancelWriting];
            complete(NO);
            return;
        }
        CGContextSetRGBFillColor(context, 0, 0, 0, 1);
        CGContextFillRect(context, CGRectMake(0, 0, 1080, 1920));
        CGContextDrawImage(context, [DYYYUtils rectForImageAspectFit:image.size inSize:videoSize], image.CGImage);
        CGContextRelease(context);
        CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
        dispatch_queue_t queue = dispatch_queue_create("com.dyyy.videoframe", DISPATCH_QUEUE_SERIAL);
        __block NSInteger frame = 0;
        __block BOOL finishing = NO;
        __block NSTimeInterval lastProgress = NSProcessInfo.processInfo.systemUptime;
        __block dispatch_source_t watchdog = nil;
        void (^finish)(BOOL) = ^(BOOL success) {
            if (finishing) return;
            finishing = YES;
            dispatch_source_t timer = watchdog;
            watchdog = nil;
            if (timer) { dispatch_source_set_event_handler(timer, ^{}); dispatch_source_cancel(timer); }
            if (!success || writer.status != AVAssetWriterStatusWriting) {
                NSLog(@"[DYYY] 图片视频写入失败: %@", writer.error);
                if (writer.status == AVAssetWriterStatusWriting) [writer cancelWriting];
                CVPixelBufferRelease(pixelBuffer);
                complete(NO);
                return;
            }
            [input markAsFinished];
            [writer finishWritingWithCompletionHandler:^{
                CVPixelBufferRelease(pixelBuffer);
                complete(writer.status == AVAssetWriterStatusCompleted);
            }];
        };
        watchdog = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
        dispatch_source_set_timer(watchdog, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), NSEC_PER_SEC, NSEC_PER_SEC / 10);
        dispatch_source_set_event_handler(watchdog, ^{
            if (writer.status == AVAssetWriterStatusFailed || writer.status == AVAssetWriterStatusCancelled || NSProcessInfo.processInfo.systemUptime - lastProgress > 30) finish(NO);
        });
        dispatch_resume(watchdog);
        [input requestMediaDataWhenReadyOnQueue:queue usingBlock:^{
            if (finishing) return;
            while (input.readyForMoreMediaData && frame < totalFrames) {
                if (![adaptor appendPixelBuffer:pixelBuffer withPresentationTime:CMTimeMake(frame, frameRate)]) { finish(NO); return; }
                frame++;
                lastProgress = NSProcessInfo.processInfo.systemUptime;
            }
            if (frame == totalFrames) finish(YES);
        }];
    }];
}

// 动画贴纸和GIF相关方法迁移自 DYYYUtils.m
+ (void)saveAnimatedSticker:(YYAnimatedImageView *)targetStickerView {
    if (!targetStickerView) {
        [DYYYUtils showToast:@"无法获取表情视图"];
        return;
    }
    [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
      dispatch_async(dispatch_get_main_queue(), ^{
        if (status != PHAuthorizationStatusAuthorized) {
            [DYYYUtils showToast:@"需要相册权限才能保存"];
            return;
        }
        if ([DYYYUtils isBDImageWithHeifURL:targetStickerView.image]) {
            [self saveHeifSticker:targetStickerView];
            return;
        }
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
          NSArray *images = [DYYYUtils getImagesFromYYAnimatedImageView:targetStickerView];
          CGFloat duration = [DYYYUtils getDurationFromYYAnimatedImageView:targetStickerView];
          if (!images || images.count == 0) {
              dispatch_async(dispatch_get_main_queue(), ^{
                [DYYYUtils showToast:@"无法获取表情帧"];
              });
              return;
          }
          NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"sticker_%ld.gif", (long)[[NSDate date] timeIntervalSince1970]]];
          BOOL success = [DYYYUtils createGIFWithImages:images
                                               duration:duration
                                                   path:tempPath
                                               progress:^(float progress){
                                               }];
          dispatch_async(dispatch_get_main_queue(), ^{
            if (!success) {
                return;
            }
            [DYYYUtils saveGIFToPhotoLibrary:tempPath
                                  completion:^(BOOL saved, NSError *error) {
                               if (saved) {
                                   [DYYYToast showSuccessToastWithMessage:@"已保存到相册"];
                               } else {
                                   NSString *errorMsg = error ? error.localizedDescription : @"未知错误";
                                   [DYYYUtils showToast:[NSString stringWithFormat:@"保存失败: %@", errorMsg]];
                               }
                             }];
          });
        });
      });
    }];
}
+ (void)saveHeifSticker:(YYAnimatedImageView *)stickerView {
    UIImage *image = stickerView.image;
    NSURL *heifURL = [image performSelector:@selector(bd_webURL)];
    if (!heifURL) {
        [DYYYUtils showToast:@"无法获取表情URL"];
        return;
    }
    [DYYYUtils convertHeicToGif:heifURL
                     completion:^(NSURL *gifURL, BOOL success) {
                         if (!success || !gifURL) {
                             [DYYYUtils showToast:@"表情转换失败"];
                             return;
                         }
                         [[PHPhotoLibrary sharedPhotoLibrary]
                             performChanges:^{
                               PHAssetCreationRequest *request = [PHAssetCreationRequest creationRequestForAsset];
                               [request addResourceWithType:PHAssetResourceTypePhoto fileURL:gifURL options:nil];
                             }
                             completionHandler:^(BOOL success, NSError *_Nullable error) {
                               dispatch_async(dispatch_get_main_queue(), ^{
                                 if (success) {
                                     [DYYYToast showSuccessToastWithMessage:@"已保存到相册"];
                                 } else {
                                     NSString *errorMsg = error ? error.localizedDescription : @"未知错误";
                                     [DYYYUtils showToast:[NSString stringWithFormat:@"保存失败: %@", errorMsg]];
                                 }
                                 NSError *removeError = nil;
                                 [[NSFileManager defaultManager] removeItemAtURL:gifURL error:&removeError];
                                 if (removeError) {
                                     NSLog(@"删除临时转换文件失败: %@", removeError);
                                 }
                               });
                             }];
                       }];
}
+ (void)downloadAndShareCommentAudio:(NSString *)audioContent
                            userName:(NSString *)userName
                          createTime:(NSNumber *)createTime {
    if (!audioContent || audioContent.length == 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [DYYYUtils showToast:@"语音内容为空"];
        });
        return;
    }
    
    NSData *jsonData = [audioContent dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    NSDictionary *audioDict = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
    
    if (error || !audioDict) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [DYYYUtils showToast:@"语音数据解析失败"];
        });
        NSLog(@"[DYYY] 解析语音 JSON 失败: %@", error);
        return;
    }
    
    NSArray *videoList = audioDict[@"video_list"];
    if (!videoList || videoList.count == 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [DYYYUtils showToast:@"未找到语音URL"];
        });
        return;
    }
    
    NSDictionary *videoInfo = videoList.firstObject;
    NSString *audioURLString = videoInfo[@"main_url"];
    if (!audioURLString || audioURLString.length == 0) {
        audioURLString = videoInfo[@"backup_url"];
    }
    
    if (!audioURLString || audioURLString.length == 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [DYYYUtils showToast:@"语音URL无效"];
        });
        return;
    }
    
    NSURL *audioURL = [NSURL URLWithString:audioURLString];
    if (!audioURL) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [DYYYUtils showToast:@"语音URL格式错误"];
        });
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [DYYYUtils showToast:@"正在下载语音..."];
    });
    
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];
    
    NSURLSessionDownloadTask *downloadTask = [session downloadTaskWithURL:audioURL completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [DYYYUtils showToast:[NSString stringWithFormat:@"下载失败: %@", error.localizedDescription]];
            });
            NSLog(@"[DYYY] 下载语音失败: %@", error);
            return;
        }
        
        if (!location) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [DYYYUtils showToast:@"下载失败：无效的文件"];
            });
            return;
        }
        
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
        NSTimeInterval timestamp = (createTime && [createTime doubleValue] > 0) ? [createTime doubleValue] : [[NSDate date] timeIntervalSince1970];
        NSDate *commentDate = [NSDate dateWithTimeIntervalSince1970:timestamp];
        NSString *timeString = [formatter stringFromDate:commentDate];
        timeString = [timeString stringByReplacingOccurrencesOfString:@":" withString:@"-"];
        timeString = [timeString stringByReplacingOccurrencesOfString:@" " withString:@"_"];
        
        NSString *safeUserName = userName ?: @"未知用户";
        safeUserName = [safeUserName stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
        safeUserName = [safeUserName stringByReplacingOccurrencesOfString:@"\\" withString:@"_"];
        
        NSString *fileName = [NSString stringWithFormat:@"%@_%@.m4a", safeUserName, timeString];
        NSString *tempDir = NSTemporaryDirectory();
        NSString *targetPath = [tempDir stringByAppendingPathComponent:fileName];
        
        NSError *moveError = nil;
        [[NSFileManager defaultManager] removeItemAtPath:targetPath error:nil];
        [[NSFileManager defaultManager] moveItemAtPath:location.path toPath:targetPath error:&moveError];
        
        if (moveError) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [DYYYUtils showToast:@"文件保存失败"];
            });
            NSLog(@"[DYYY] 移动文件失败: %@", moveError);
            return;
        }
        
        NSURL *fileURL = [NSURL fileURLWithPath:targetPath];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            UIViewController *topVC = [DYYYUtils topView];
            if (!topVC) {
                [DYYYUtils showToast:@"无法显示分享界面"];
                return;
            }
            
            UIActivityViewController *activityVC = [[UIActivityViewController alloc] initWithActivityItems:@[fileURL] applicationActivities:nil];
            
            activityVC.completionWithItemsHandler = ^(UIActivityType activityType, BOOL completed, NSArray *returnedItems, NSError *activityError) {
                [[NSFileManager defaultManager] removeItemAtPath:targetPath error:nil];
                
                if (completed) {
                    [DYYYUtils showToast:@"分享成功"];
                } else if (activityError) {
                    [DYYYUtils showToast:@"分享失败"];
                }
            };
            
            if ([activityVC respondsToSelector:@selector(popoverPresentationController)]) {
                activityVC.popoverPresentationController.sourceView = topVC.view;
                activityVC.popoverPresentationController.sourceRect = CGRectMake(topVC.view.bounds.size.width / 2, topVC.view.bounds.size.height / 2, 0, 0);
            }
            
            [topVC presentViewController:activityVC animated:YES completion:nil];
        });
    }];
    
    [downloadTask resume];
}

@end
