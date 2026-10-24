#!/usr/bin/env python3
"""在 macOS 上运行生产下载/编码方法；UIKit 与相册行为仍需真机回归。"""
import http.server
import os
import pathlib
import re
import subprocess
import tempfile
import threading
import time
import urllib.parse

ROOT = pathlib.Path(__file__).resolve().parents[1]


def method(source, prefix):
    start = source.index(prefix)
    end = re.search(r"^}", source[start:], re.M)
    assert end, prefix
    return source[start:start + end.end()]


manager = (ROOT / "DYYYManager.m").read_text()
utils = (ROOT / "DYYYUtils.m").read_text()
prefixes = [
    "+ (instancetype)shared", "- (instancetype)init", "+ (void)cancelAllDownloads",
    "- (void)setBatchInfo:", "- (void)incrementCompletedAndUpdateProgressForBatch:", "- (void)finishBatch:",
    "- (NSURL *)destinationURLForTask:", "- (NSString *)enqueueDownloadURL:", "- (void)finishTransfer:",
    "- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)task\n",
    "- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)task didFinishDownloadingToURL:",
    "- (void)URLSession:(NSURLSession *)session task:", "- (void)enqueueMediaJob:", "- (void)startNextMediaJob",
    "- (void)removeTemporaryFiles:", "- (NSError *)mediaErrorWithDescription:", "- (void)useAssetWriter:",
    "- (BOOL)addMetadataToPhoto:", "- (void)writeLivePhotoMetadataToVideo:",
    "- (AVMetadataItem *)createContentIdentifierMetadataItem:", "- (AVAssetWriterInput *)createStillImageTimeAssetWriterInput",
    "- (AVMetadataItem *)createStillImageTimeMetadataItem", "+ (void)createVideoFromImage:",
]
methods = [method(manager, prefix) for prefix in prefixes]
properties = manager[manager.index("@property", manager.index("@interface DYYYManager")):manager.index("@end", manager.index("@interface DYYYManager"))]
utility_methods = [method(utils, prefix) for prefix in ["+ (NSURL *)uniqueTemporaryFileURLWithFileName:", "+ (CGRect)rectForImageAspectFit:"]]
header = r'''
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>
#import <CoreServices/CoreServices.h>
#import <AudioToolbox/AudioToolbox.h>
#import <objc/runtime.h>
#import <assert.h>
#import <math.h>
#import "DYYYDownloadScheduler.h"

@interface DYYYToast : NSObject
@property(nonatomic, assign) BOOL isCancelled;
@property(nonatomic, assign) BOOL allowSuccessAnimation;
@property(nonatomic, copy) dispatch_block_t cancelBlock;
- (void)dismiss;
- (void)setProgress:(float)value;
@end
@implementation DYYYToast
- (void)dismiss {}
- (void)setProgress:(float)value {}
@end

// 只提供静态图片编码所需的不可变 CGImage，不模拟 UIKit 布局。
@interface UIImage : NSObject
@property(nonatomic, assign) CGImageRef CGImage;
@property(nonatomic, assign) CGSize size;
@end
@implementation UIImage
- (instancetype)init {
    if ((self = [super init])) {
        CGColorSpaceRef colors = CGColorSpaceCreateDeviceRGB();
        CGContextRef context = CGBitmapContextCreate(NULL, 64, 64, 8, 256, colors, kCGImageAlphaPremultipliedFirst);
        CGContextSetRGBFillColor(context, 0.2, 0.5, 0.7, 1);
        CGContextFillRect(context, CGRectMake(0, 0, 64, 64));
        _CGImage = CGBitmapContextCreateImage(context);
        _size = CGSizeMake(64, 64);
        CGContextRelease(context);
        CGColorSpaceRelease(colors);
    }
    return self;
}
- (void)dealloc { CGImageRelease(_CGImage); }
@end

@interface DYYYTestProbe : NSObject
@property(atomic, assign) NSUInteger calls;
+ (void)waitFor:(BOOL (^)(void))condition;
@end
@implementation DYYYTestProbe
+ (void)waitFor:(BOOL (^)(void))condition {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:40];
    while (!condition() && deadline.timeIntervalSinceNow > 0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    assert(condition());
}
@end
'''
source = header + "\n@interface DYYYUtils : NSObject\n" + "\n".join(m[:m.index("{")].strip() + ";" for m in utility_methods) + "\n@end\n@implementation DYYYUtils\n" + "\n".join(utility_methods) + "\n@end\n"
source += "\n@interface DYYYManager : NSObject <NSURLSessionDownloadDelegate>\n@property(nonatomic, strong) NSMutableDictionary *fileLinks;\n" + properties + "\n" + "\n".join(m[:m.index("{")].strip() + ";" for m in methods) + "\n@end\n@implementation DYYYManager\n" + "\n".join(methods) + "\n@end\n"
source += r'''
int main(int argc, const char **argv) {
    @autoreleasepool {
        DYYYManager *manager = DYYYManager.shared;
        NSMutableArray<NSURL *> *temporary = [NSMutableArray array];
        NSString *port = [NSString stringWithUTF8String:argv[1]];
        __block NSUInteger completed = 0;
        NSMutableSet *names = [NSMutableSet set];
        for (NSUInteger index = 0; index < 8; index++) {
            NSString *host = index % 2 ? @"localhost" : @"127.0.0.1";
            NSString *payload = [NSString stringWithFormat:@"item%lu", (unsigned long)index];
            NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://%@:%@/same-name?id=%@", host, port, payload]];
            NSURL *destination = [DYYYUtils uniqueTemporaryFileURLWithFileName:url.lastPathComponent];
            assert(![names containsObject:destination.path]);
            [names addObject:destination.path];
            [temporary addObject:destination];
            [manager enqueueDownloadURL:url destinationURL:destination progress:nil completion:^(BOOL success, NSURL *fileURL) {
                assert(success && NSThread.isMainThread);
                NSString *data = [[NSString alloc] initWithData:[NSData dataWithContentsOfURL:fileURL] encoding:NSUTF8StringEncoding];
                assert([data hasPrefix:payload]);
                completed++;
            }];
        }
        [DYYYTestProbe waitFor:^BOOL(void) { return completed == 8; }];
        assert(manager.downloadTasks.count == 0 && manager.transferCompletionBlocks.count == 0 && manager.taskProgressMap.count == 0);
        __block BOOL missingFinished = NO;
        NSURL *missingDestination = [DYYYUtils uniqueTemporaryFileURLWithFileName:@"missing.jpg"];
        [manager enqueueDownloadURL:[NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%@/missing", port]] destinationURL:missingDestination progress:nil completion:^(BOOL success, NSURL *fileURL) {
            assert(!success && !fileURL);
            missingFinished = YES;
        }];
        [DYYYTestProbe waitFor:^BOOL(void) { return missingFinished; }];
        assert(![NSFileManager.defaultManager fileExistsAtPath:missingDestination.path]);
        assert(![[[DYYYUtils uniqueTemporaryFileURLWithFileName:@"/"] path] hasSuffix:@"/"]);
        completed = 0;
        for (NSUInteger index = 0; index < 12; index++) {
            NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%@/slow?id=cancel", port]];
            NSURL *destination = [DYYYUtils uniqueTemporaryFileURLWithFileName:@"cancelled"];
            [temporary addObject:destination];
            [manager enqueueDownloadURL:url destinationURL:destination progress:nil completion:^(BOOL success, NSURL *fileURL) {
                assert(!success && !fileURL && NSThread.isMainThread);
                completed++;
            }];
        }
        [DYYYManager cancelAllDownloads];
        [DYYYTestProbe waitFor:^BOOL(void) { return completed == 12; }];
        assert(manager.downloadTasks.count == 0 && manager.transferCompletionBlocks.count == 0 && manager.transferProgressBlocks.count == 0);
        __block NSUInteger batchCallbacks = 0;
        [manager setBatchInfo:@"cancelled-batch" totalCount:3 progressBlock:nil completionBlock:^(NSInteger successes, NSInteger total) { assert(successes == 0 && total == 3); batchCallbacks++; }];
        [manager finishBatch:@"cancelled-batch" cancelled:YES];
        [manager finishBatch:@"cancelled-batch" cancelled:YES];
        for (NSUInteger index = 0; index < 3; index++) [manager incrementCompletedAndUpdateProgressForBatch:@"cancelled-batch" success:NO];
        assert(batchCallbacks == 1 && manager.batchTotalCountMap.count == 0 && manager.batchCompletedCountMap.count == 0);

        UIImage *image = [UIImage new];
        NSURL *photo = [DYYYUtils uniqueTemporaryFileURLWithFileName:@"source.png"];
        NSURL *video = [DYYYUtils uniqueTemporaryFileURLWithFileName:@"source.mp4"];
        [temporary addObjectsFromArray:@[photo, video]];
        CGImageDestinationRef png = CGImageDestinationCreateWithURL((__bridge CFURLRef)photo, kUTTypePNG, 1, NULL);
        assert(png);
        CGImageDestinationAddImage(png, image.CGImage, NULL);
        assert(CGImageDestinationFinalize(png));
        CFRelease(png);
        DYYYTestProbe *encoded = [DYYYTestProbe new];
        [DYYYManager createVideoFromImage:image duration:0.2 outputPath:video.path completion:^(BOOL success) { assert(success); encoded.calls++; }];
        [DYYYTestProbe waitFor:^BOOL(void) { return encoded.calls == 1; }];
        assert([AVAsset assetWithURL:video].tracks.count > 0);
        __block NSUInteger conversions = 0;
        for (NSString *identifier in @[NSUUID.UUID.UUIDString, NSUUID.UUID.UUIDString]) {
            [manager useAssetWriter:photo video:video identifier:identifier complete:^(BOOL success, NSString *photoFile, NSString *videoFile, NSError *error) {
                assert(success && !error && NSThread.isMainThread);
                NSURL *photoURL = [NSURL fileURLWithPath:photoFile];
                NSURL *videoURL = [NSURL fileURLWithPath:videoFile];
                [temporary addObjectsFromArray:@[photoURL, videoURL]];
                CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)photoURL, NULL);
                NSDictionary *properties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL));
                CFRelease(source);
                assert([properties[(__bridge NSString *)kCGImagePropertyMakerAppleDictionary][@"17"] isEqual:identifier]);
                AVAsset *asset = [AVAsset assetWithURL:videoURL];
                BOOL foundIdentifier = NO;
                for (AVMetadataItem *item in asset.metadata) if ([item.key isEqual:AVMetadataQuickTimeMetadataKeyContentIdentifier] && [item.stringValue isEqual:identifier]) foundIdentifier = YES;
                assert(foundIdentifier && [asset tracksWithMediaType:AVMediaTypeMetadata].count > 0);
                conversions++;
            }];
        }
        [manager useAssetWriter:[NSURL fileURLWithPath:@"/nonexistent/dyyy-test-image"] video:video identifier:@"invalid" complete:^(BOOL success, NSString *photoFile, NSString *videoFile, NSError *error) {
            assert(!success && !photoFile && !videoFile && error);
            conversions++;
        }];
        [DYYYTestProbe waitFor:^BOOL(void) { return conversions == 3; }];
        DYYYTestProbe *invalid = [DYYYTestProbe new];
        [DYYYManager createVideoFromImage:image duration:NAN outputPath:video.path completion:^(BOOL success) { assert(!success); invalid.calls++; }];
        [DYYYTestProbe waitFor:^BOOL(void) { return invalid.calls == 1; }];
        [DYYYTestProbe waitFor:^BOOL(void) { __block BOOL idle; dispatch_sync(manager.mediaProcessingQueue, ^{ idle = !manager.mediaJobActive && manager.mediaJobs.count == 0; }); return idle; }];
        for (NSURL *file in temporary) [NSFileManager.defaultManager removeItemAtURL:file error:nil];
        [manager.downloadSession finishTasksAndInvalidate];
        puts("Pipeline: streamed files, concurrency, cancellation/late completion, image video encoding, independent Live Photo metadata and failure recovery passed");
    }
    return 0;
}
'''


class FixtureServer(http.server.ThreadingHTTPServer):
    daemon_threads = True
    active = 0
    maximum = 0
    lock = threading.Lock()


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        if urllib.parse.urlsplit(self.path).path == "/missing":
            self.send_error(404)
            return
        value = urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query).get("id", ["fixture"])[0].encode()
        payload = value * 16384
        with self.server.lock:
            self.server.active += 1
            self.server.maximum = max(self.server.maximum, self.server.active)
        try:
            self.send_response(200)
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            for offset in range(0, len(payload), 4096):
                self.wfile.write(payload[offset:offset + 4096])
                self.wfile.flush()
                if offset + 4096 < len(payload):
                    time.sleep(0.004)
        except (BrokenPipeError, ConnectionResetError):
            pass
        finally:
            with self.server.lock:
                self.server.active -= 1


with tempfile.TemporaryDirectory(prefix="dyyy-pipeline-tests-") as scratch:
    scratch = pathlib.Path(scratch)
    implementation = scratch / "Pipeline.m"
    implementation.write_text(source)
    binary = scratch / "pipeline-tests"
    subprocess.run(["clang", "-fobjc-arc", "-fblocks", "-Wno-deprecated-declarations", "-I", str(ROOT), str(implementation), str(ROOT / "DYYYDownloadScheduler.m"), "-framework", "Foundation", "-framework", "AVFoundation", "-framework", "ImageIO", "-framework", "CoreServices", "-framework", "CoreGraphics", "-framework", "CoreVideo", "-framework", "CoreMedia", "-framework", "AudioToolbox", "-o", str(binary)], check=True)
    server = FixtureServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        subprocess.run([str(binary), str(server.server_port)], check=True, timeout=100, env={**os.environ, "TMPDIR": str(scratch) + "/"})
        assert 1 <= server.maximum <= 3, server.maximum
        print(f"Loopback HTTP maximum concurrent responses: {server.maximum}")
    finally:
        server.shutdown()
        server.server_close()
