#import "AwemeHeaders.h"
#import "DYYYManager.h"
#import <MobileCoreServices/MobileCoreServices.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "DYYYABTestHook.h"

// 导入所有弹窗类
#import "DYYYAboutDialogView.h"
#import "DYYYCustomInputView.h"
#import "DYYYIconOptionsDialogView.h"
#import "DYYYKeywordListView.h"
#import "DYYYOptionsSelectionView.h"

#import "DYYYUtils.h"

@class DYYYIconOptionsDialogView;
static void showIconOptionsDialog(NSString *title, UIImage *previewImage, NSString *saveFilename, void (^onClear)(void), void (^onSelect)(void));

@interface DYYYImagePickerDelegate : NSObject <UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property(nonatomic, copy) void (^completionBlock)(NSDictionary *info);
@end

@implementation DYYYImagePickerDelegate
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
	if (self.completionBlock) {
		self.completionBlock(info);
	}
	[picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
	[picker dismissViewControllerAnimated:YES completion:nil];
}
@end

@interface DYYYBackupPickerDelegate : NSObject <UIDocumentPickerDelegate>
@property(nonatomic, copy) void (^completionBlock)(NSURL *url);
@property(nonatomic, copy) NSString *tempFilePath; // 添加临时文件路径属性
@end

@implementation DYYYBackupPickerDelegate
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
	if (urls.count > 0 && self.completionBlock) {
		self.completionBlock(urls.firstObject);
	}

	// 清理临时文件
	[self cleanupTempFile];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
	// 用户取消操作时清理临时文件
	[self cleanupTempFile];
}

// 添加清理临时文件的方法
- (void)cleanupTempFile {
	if (self.tempFilePath && [[NSFileManager defaultManager] fileExistsAtPath:self.tempFilePath]) {
		NSError *error = nil;
		[[NSFileManager defaultManager] removeItemAtPath:self.tempFilePath error:&error];
		if (error) {
			NSLog(@"[DYYY] 清理临时文件失败: %@", error.localizedDescription);
		}
	}
}
@end

// 获取顶级视图控制器
static UIViewController *getActiveTopViewController() {
	UIWindowScene *activeScene = nil;
	for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
		if (scene.activationState == UISceneActivationStateForegroundActive) {
			activeScene = scene;
			break;
		}
	}
	if (!activeScene) {
		for (id scene in [UIApplication sharedApplication].connectedScenes) {
			if ([scene isKindOfClass:[UIWindowScene class]]) {
				activeScene = (UIWindowScene *)scene;
				break;
			}
		}
	}
	if (!activeScene)
		return nil;
	UIWindow *window = activeScene.windows.firstObject;
	UIViewController *topController = window.rootViewController;
	while (topController.presentedViewController) {
		topController = topController.presentedViewController;
	}
	return topController;
}

static AWESettingItemModel *createIconCustomizationItem(NSString *identifier, NSString *title, NSString *svgIconName, NSString *saveFilename) {
	AWESettingItemModel *item = [[%c(AWESettingItemModel) alloc] init];
	item.identifier = identifier;
	item.title = title;

	// 检查图片是否存在，使用saveFilename
	NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
	NSString *dyyyFolderPath = [documentsPath stringByAppendingPathComponent:@"DYYY"];
	NSString *imagePath = [dyyyFolderPath stringByAppendingPathComponent:saveFilename];

	BOOL fileExists = [[NSFileManager defaultManager] fileExistsAtPath:imagePath];
	item.detail = fileExists ? @"已设置" : @"默认";

	item.type = 0;
	item.svgIconImageName = svgIconName; // 使用传入的SVG图标名称
	item.cellType = 26;
	item.colorStyle = 0;
	item.isEnable = YES;
	item.cellTappedBlock = ^{
	  // 创建文件夹（如果不存在）
	  if (![[NSFileManager defaultManager] fileExistsAtPath:dyyyFolderPath]) {
		  [[NSFileManager defaultManager] createDirectoryAtPath:dyyyFolderPath withIntermediateDirectories:YES attributes:nil error:nil];
	  }

	  UIViewController *topVC = topView();

	  // 加载预览图片(如果存在)
	  UIImage *previewImage = nil;
	  if (fileExists) {
		  previewImage = [UIImage imageWithContentsOfFile:imagePath];
	  }

	  // 显示选项对话框 - 使用saveFilename作为参数传递
	  showIconOptionsDialog(
	      title, previewImage, saveFilename,
	      ^{
		// 清除按钮回调
		if ([[NSFileManager defaultManager] fileExistsAtPath:imagePath]) {
			NSError *error = nil;
			[[NSFileManager defaultManager] removeItemAtPath:imagePath error:&error];
			if (!error) {
				item.detail = @"默认";

				// 刷新表格视图
				if ([topVC isKindOfClass:%c(AWESettingBaseViewController)]) {
					dispatch_async(dispatch_get_main_queue(), ^{
					  UITableView *tableView = nil;
					  for (UIView *subview in topVC.view.subviews) {
						  if ([subview isKindOfClass:[UITableView class]]) {
							  tableView = (UITableView *)subview;
							  break;
						  }
					  }

					  if (tableView) {
						  [tableView reloadData];
					  }
					});
				}
			}
		}
	      },
	      ^{
		// 选择按钮回调 - 打开图片选择器
		UIImagePickerController *picker = [[UIImagePickerController alloc] init];
		picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
		picker.allowsEditing = NO;
		picker.mediaTypes = @[ @"public.image" ];

		// 创建并设置代理
		DYYYImagePickerDelegate *pickerDelegate = [[DYYYImagePickerDelegate alloc] init];
		pickerDelegate.completionBlock = ^(NSDictionary *info) {
		  UIImage *selectedImage = info[UIImagePickerControllerOriginalImage];
		  if (selectedImage) {
			  // 确保路径存在
			  NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
			  NSString *dyyyFolderPath = [documentsPath stringByAppendingPathComponent:@"DYYY"];
			  NSString *imagePath = [dyyyFolderPath stringByAppendingPathComponent:saveFilename];

			  // 保存图片
			  NSData *imageData = UIImagePNGRepresentation(selectedImage);
			  BOOL success = [imageData writeToFile:imagePath atomically:YES];

			  if (success) {
				  // 更新UI
				  item.detail = @"已设置";

				  // 确保在主线程刷新UI
				  dispatch_async(dispatch_get_main_queue(), ^{
				    // 刷新表格视图
				    if ([topVC isKindOfClass:%c(AWESettingBaseViewController)]) {
					    UITableView *tableView = nil;
					    for (UIView *subview in topVC.view.subviews) {
						    if ([subview isKindOfClass:[UITableView class]]) {
							    tableView = (UITableView *)subview;
							    break;
						    }
					    }

					    if (tableView) {
						    [tableView reloadData];
					    }
				    }
				  });
			  }
		  }
		};

		static char kDYYYPickerDelegateKey;
		picker.delegate = pickerDelegate;
		objc_setAssociatedObject(picker, &kDYYYPickerDelegateKey, pickerDelegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		[topVC presentViewController:picker animated:YES completion:nil];
	      });
	};

	return item;
}

// 显示自定义关于弹窗
static void showAboutDialog(NSString *title, NSString *message, void (^onConfirm)(void)) {
	DYYYAboutDialogView *aboutDialog = [[DYYYAboutDialogView alloc] initWithTitle:title message:message];
	aboutDialog.onConfirm = onConfirm;
	[aboutDialog show];
}

static void showTextInputAlert(NSString *title, void (^onConfirm)(NSString *text), void (^onCancel)(void));
static void showTextInputAlert(NSString *title, NSString *defaultText, void (^onConfirm)(NSString *text), void (^onCancel)(void));
static void showTextInputAlert(NSString *title, NSString *defaultText, NSString *placeholder, void (^onConfirm)(NSString *text), void (^onCancel)(void));

static void showTextInputAlert(NSString *title, NSString *defaultText, NSString *placeholder, void (^onConfirm)(NSString *text), void (^onCancel)(void)) {
	DYYYCustomInputView *inputView = [[DYYYCustomInputView alloc] initWithTitle:title defaultText:defaultText placeholder:placeholder];
	inputView.onConfirm = onConfirm;
	inputView.onCancel = onCancel;
	[inputView show];
}

static void showTextInputAlert(NSString *title, NSString *defaultText, void (^onConfirm)(NSString *text), void (^onCancel)(void)) { showTextInputAlert(title, defaultText, nil, onConfirm, onCancel); }

static void showTextInputAlert(NSString *title, void (^onConfirm)(NSString *text), void (^onCancel)(void)) { showTextInputAlert(title, nil, nil, onConfirm, onCancel); }

// 获取和设置用户偏好
static bool getUserDefaults(NSString *key) { return [[NSUserDefaults standardUserDefaults] boolForKey:key]; }

static void setUserDefaults(id object, NSString *key) {
	[[NSUserDefaults standardUserDefaults] setObject:object forKey:key];
	[[NSUserDefaults standardUserDefaults] synchronize];
}

// 显示图标选项弹窗
static void showIconOptionsDialog(NSString *title, UIImage *previewImage, NSString *saveFilename, void (^onClear)(void), void (^onSelect)(void)) {
	DYYYIconOptionsDialogView *optionsDialog = [[DYYYIconOptionsDialogView alloc] initWithTitle:title previewImage:previewImage];
	optionsDialog.onClear = onClear;
	optionsDialog.onSelect = onSelect;
	[optionsDialog show];
}

#undef DYYY
#define DYYY @"DYYY设置"

static void *kViewModelKey = &kViewModelKey;
%hook AWESettingBaseViewController
- (bool)useCardUIStyle {
	return YES;
}

- (AWESettingBaseViewModel *)viewModel {
	AWESettingBaseViewModel *original = %orig;
	if (!original)
		return objc_getAssociatedObject(self, &kViewModelKey);
	return original;
}
%end

static AWESettingBaseViewController *createSubSettingsViewController(NSString *title, NSArray *sectionsArray) {
	AWESettingBaseViewController *settingsVC = [[%c(AWESettingBaseViewController) alloc] init];

	// 等待视图加载并设置标题
	dispatch_async(dispatch_get_main_queue(), ^{
	  if ([settingsVC.view isKindOfClass:[UIView class]]) {
		  for (UIView *subview in settingsVC.view.subviews) {
			  if ([subview isKindOfClass:%c(AWENavigationBar)]) {
				  AWENavigationBar *navigationBar = (AWENavigationBar *)subview;
				  if ([navigationBar respondsToSelector:@selector(titleLabel)]) {
					  navigationBar.titleLabel.text = title;
				  }
				  break;
			  }
		  }
	  }
	});

	AWESettingsViewModel *viewModel = [[%c(AWESettingsViewModel) alloc] init];
	viewModel.colorStyle = 0;
	viewModel.sectionDataArray = sectionsArray;
	objc_setAssociatedObject(settingsVC, kViewModelKey, viewModel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

	return settingsVC;
}

// 创建一个section的辅助方法
static AWESettingSectionModel *createSection(NSString *title, NSArray *items) {
	AWESettingSectionModel *section = [[%c(AWESettingSectionModel) alloc] init];
	section.sectionHeaderTitle = title;
	section.sectionHeaderHeight = 40;
	section.type = 0;
	section.itemArray = items;
	return section;
}

static void showUserAgreementAlert() {
	showTextInputAlert(
	    @"用户协议", @"", @"",
	    ^(NSString *text) {
	      if ([text isEqualToString:@"我已阅读并同意继续使用"]) {
		      setUserDefaults(@"YES", @"DYYYUserAgreementAccepted");
	      } else {
		      [DYYYManager showToast:@"请正确输入内容"];
		      showUserAgreementAlert();
	      }
	    },
	    ^(void) {
	      [DYYYManager showToast:@"请立即卸载本插件"];
	      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		exit(0);
	      });
	    });
}

%hook AWESettingsViewModel
- (NSArray *)sectionDataArray {
	NSArray *originalSections = %orig;
	BOOL sectionExists = NO;
	for (AWESettingSectionModel *section in originalSections) {
		if ([section.sectionHeaderTitle isEqualToString:@"DYYY"]) {
			sectionExists = YES;
			break;
		}
	}
	if (self.traceEnterFrom && !sectionExists) {

		AWESettingItemModel *dyyyItem = [[%c(AWESettingItemModel) alloc] init];
		dyyyItem.identifier = @"DYYY";
		dyyyItem.title = @"DYYY";
		dyyyItem.detail = @"v2.2-4";
		dyyyItem.type = 0;
		dyyyItem.svgIconImageName = @"ic_sapling_outlined";
		dyyyItem.cellType = 26;
		dyyyItem.colorStyle = 2;
		dyyyItem.isEnable = YES;
		dyyyItem.cellTappedBlock = ^{
		  UIViewController *rootVC = self.controllerDelegate;
		  AWESettingBaseViewController *settingsVC = [[%c(AWESettingBaseViewController) alloc] init];
		  BOOL hasAgreed = getUserDefaults(@"DYYYUserAgreementAccepted");
		  if (!hasAgreed) {
			  showAboutDialog(@"用户协议",
					  @"本插件为开源项目\n仅供学习交流用途\n如有侵权请联系, GitHub 仓库：huami1314/DYYY\n请遵守当地法律法规, "
					  @"逆向工程仅为学习目的\n盗用源码进行商业用途/发布但未标记开源项目必究\n详情请参阅项目内 MIT 许可证\n\n请输入\"我已阅读并同意继续使用\"以继续",
					  ^{
					    showUserAgreementAlert();
					  });
		  }

		  // 等待视图加载并使用KVO安全访问属性
		  dispatch_async(dispatch_get_main_queue(), ^{
		    if ([settingsVC.view isKindOfClass:[UIView class]]) {
			    for (UIView *subview in settingsVC.view.subviews) {
				    if ([subview isKindOfClass:%c(AWENavigationBar)]) {
					    AWENavigationBar *navigationBar = (AWENavigationBar *)subview;
					    if ([navigationBar respondsToSelector:@selector(titleLabel)]) {
						    navigationBar.titleLabel.text = DYYY;
					    }
					    break;
				    }
			    }
		    }
		  });

		  AWESettingsViewModel *viewModel = [[%c(AWESettingsViewModel) alloc] init];
		  viewModel.colorStyle = 0;

		  // 创建主分类列表
		  AWESettingSectionModel *mainSection = [[%c(AWESettingSectionModel) alloc] init];
		  mainSection.sectionHeaderTitle = @"功能";
		  mainSection.sectionHeaderHeight = 40;
		  mainSection.type = 0;
		  NSMutableArray<AWESettingItemModel *> *mainItems = [NSMutableArray array];

		  // 创建基本设置分类项
		  AWESettingItemModel *basicSettingItem = [[%c(AWESettingItemModel) alloc] init];
		  basicSettingItem.identifier = @"DYYYBasicSettings";
		  basicSettingItem.title = @"基本设置";
		  basicSettingItem.type = 0;
		  basicSettingItem.svgIconImageName = @"ic_gearsimplify_outlined_20";
		  basicSettingItem.cellType = 26;
		  basicSettingItem.colorStyle = 0;
		  basicSettingItem.isEnable = YES;
		  basicSettingItem.cellTappedBlock = ^{
		    // 创建基本设置二级界面的设置项
		    NSMutableDictionary *cellTapHandlers = [NSMutableDictionary dictionary];

		    // 【外观设置】分类
		    NSMutableArray<AWESettingItemModel *> *appearanceItems = [NSMutableArray array];
		    NSArray *appearanceSettings = @[
			    @{@"identifier" : @"DYYYEnableDanmuColor",
			      @"title" : @"启用弹幕改色",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_dansquare_outlined_20"},
			    @{@"identifier" : @"DYYYdanmuColor",
			      @"title" : @"自定弹幕颜色",
			      @"detail" : @"十六进制",
			      @"cellType" : @26,
			      @"imageName" : @"ic_dansquarenut_outlined_20"},
		    ];

		    for (NSDictionary *dict in appearanceSettings) {
			    AWESettingItemModel *item = [self createSettingItem:dict cellTapHandlers:cellTapHandlers];
			    [appearanceItems addObject:item];
		    }

		    // 【视频播放设置】分类
		    NSMutableArray<AWESettingItemModel *> *videoItems = [NSMutableArray array];
		    NSArray *videoSettings = @[
			    @{@"identifier" : @"DYYYisShowScheduleDisplay",
			      @"title" : @"显示进度时长",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_playertime_outlined_20"},
			    @{@"identifier" : @"DYYYScheduleStyle",
			      @"title" : @"进度时长样式",
			      @"detail" : @"",
			      @"cellType" : @26,
			      @"imageName" : @"ic_playertime_outlined_20"},
			    @{@"identifier" : @"DYYYProgressLabelColor",
			      @"title" : @"进度标签颜色",
			      @"detail" : @"十六进制",
			      @"cellType" : @26,
			      @"imageName" : @"ic_playertime_outlined_20"},
			    @{@"identifier" : @"DYYYTimelineVerticalPosition",
			      @"title" : @"进度纵轴位置",
			      @"detail" : @"-12.5",
			      @"cellType" : @26,
			      @"imageName" : @"ic_playertime_outlined_20"},
			    @{@"identifier" : @"DYYYHideVideoProgress",
			      @"title" : @"隐藏视频进度",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_playertime_outlined_20"},
			    @{@"identifier" : @"DYYYisEnableAutoPlay",
			      @"title" : @"启用自动播放",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_play_outlined_12"},
			    @{@"identifier" : @"DYYYDefaultSpeed",
			      @"title" : @"设置默认倍速",
			      @"detail" : @"",
			      @"cellType" : @26,
			      @"imageName" : @"ic_speed_outlined_20"},
			    @{@"identifier" : @"DYYYisEnableArea",
			      @"title" : @"时间属地显示",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_location_outlined_20"},
			    @{@"identifier" : @"DYYYLabelColor",
			      @"title" : @"属地标签颜色",
			      @"detail" : @"十六进制",
			      @"cellType" : @26,
			      @"imageName" : @"ic_location_outlined_20"}
		    ];

		    for (NSDictionary *dict in videoSettings) {
			    AWESettingItemModel *item = [self createSettingItem:dict cellTapHandlers:cellTapHandlers];

			    if ([item.identifier isEqualToString:@"DYYYDefaultSpeed"]) {
				    // 获取已保存的默认倍速值
				    NSString *savedSpeed = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYDefaultSpeed"];
				    item.detail = savedSpeed ?: @"1.0x";

				    item.cellTappedBlock = ^{
				      NSArray *speedOptions = @[ @"0.75x", @"1.0x", @"1.25x", @"1.5x", @"2.0x", @"2.5x", @"3.0x" ];

				      // 显示选项选择视图并直接获取返回值
				      NSString *selectedValue = [DYYYOptionsSelectionView showWithPreferenceKey:@"DYYYDefaultSpeed"
												   optionsArray:speedOptions
												     headerText:@"选择默认倍速"
												 onPresentingVC:topView()];

				      // 设置详情文本为选中的值
				      item.detail = selectedValue;
				      UIViewController *topVC = topView();
				      // 刷新表格视图
				      if ([topVC isKindOfClass:%c(AWESettingBaseViewController)]) {
					      dispatch_async(dispatch_get_main_queue(), ^{
						UITableView *tableView = nil;
						for (UIView *subview in topVC.view.subviews) {
							if ([subview isKindOfClass:[UITableView class]]) {
								tableView = (UITableView *)subview;
								break;
							}
						}

						if (tableView) {
							[tableView reloadData];
						}
					      });
				      }
				    };
			    }

			    else if ([item.identifier isEqualToString:@"DYYYScheduleStyle"]) {
				    NSString *savedStyle = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYScheduleStyle"];
				    item.detail = savedStyle ?: @"默认";
				    item.cellTappedBlock = ^{
				      NSArray *styleOptions = @[ @"进度条两侧上下", @"进度条两侧左右", @"进度条右侧剩余", @"进度条右侧完整" ];

				      // 显示选项选择视图并直接获取返回值
				      NSString *selectedValue = [DYYYOptionsSelectionView showWithPreferenceKey:@"DYYYScheduleStyle"
												   optionsArray:styleOptions
												     headerText:@"选择进度时长样式"
												 onPresentingVC:topView()];

				      // 设置详情文本为选中的值

				      item.detail = selectedValue;
				      UIViewController *topVC = topView();
				      // 刷新表格视图
				      if ([topVC isKindOfClass:%c(AWESettingBaseViewController)]) {
					      dispatch_async(dispatch_get_main_queue(), ^{
						UITableView *tableView = nil;
						for (UIView *subview in topVC.view.subviews) {
							if ([subview isKindOfClass:[UITableView class]]) {
								tableView = (UITableView *)subview;
								break;
							}
						}

						if (tableView) {
							[tableView reloadData];
						}
					      });
				      }
				    };
			    }

			    [videoItems addObject:item];
		    }
		    // 【杂项设置】分类
		    NSMutableArray<AWESettingItemModel *> *miscellaneousItems = [NSMutableArray array];
		    NSArray *miscellaneousSettings = @[
			    @{@"identifier" : @"DYYYisHideStatusbar",
			      @"title" : @"隐藏系统顶栏",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYisEnablePure",
			      @"title" : @"启用首页净化",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_broom_outlined"},
			    @{@"identifier" : @"DYYYisEnableFullScreen",
			      @"title" : @"启用首页全屏",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_fullscreen_outlined_16"}
		    ];

		    for (NSDictionary *dict in miscellaneousSettings) {
			    AWESettingItemModel *item = [self createSettingItem:dict cellTapHandlers:cellTapHandlers];
			    [miscellaneousItems addObject:item];
		    }
		    // 【过滤与屏蔽】分类
		    NSMutableArray<AWESettingItemModel *> *filterItems = [NSMutableArray array];
		    NSArray *filterSettings = @[
			    @{@"identifier" : @"DYYYisSkipLive",
			      @"title" : @"推荐过滤直播",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_video_outlined_20"},
			    @{@"identifier" : @"DYYYisSkipHotSpot",
			      @"title" : @"推荐过滤热点",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_squaretriangletwo_outlined_20"},
			    @{@"identifier" : @"DYYYfilterLowLikes",
			      @"title" : @"推荐过滤低赞",
			      @"detail" : @"0",
			      @"cellType" : @26,
			      @"imageName" : @"ic_thumbsdown_outlined_20"},
			    @{@"identifier" : @"DYYYfilterUsers",
			      @"title" : @"推荐过滤用户",
			      @"detail" : @"",
			      @"cellType" : @26,
			      @"imageName" : @"ic_userban_outlined_20"},
			    @{@"identifier" : @"DYYYfilterKeywords",
			      @"title" : @"推荐过滤文案",
			      @"detail" : @"",
			      @"cellType" : @26,
			      @"imageName" : @"ic_tag_outlined_20"},
			    @{@"identifier" : @"DYYYfiltertimelimit",
			      @"title" : @"推荐视频时限",
			      @"detail" : @"",
			      @"cellType" : @26,
			      @"imageName" : @"ic_playertime_outlined_20"},
			    @{@"identifier" : @"DYYYNoAds",
			      @"title" : @"启用屏蔽广告",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_ad_outlined_20"},
			    @{@"identifier" : @"DYYYNoUpdates",
			      @"title" : @"屏蔽检测更新",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_circletop_outlined"},
			    @{@"identifier" : @"DYYYHideteenmode",
			      @"title" : @"去青少年弹窗",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_personcircleclean_outlined_20"}
		    ];

		    for (NSDictionary *dict in filterSettings) {
			    AWESettingItemModel *item = [self createSettingItem:dict cellTapHandlers:cellTapHandlers];

			    if ([item.identifier isEqualToString:@"DYYYfilterLowLikes"]) {
				    NSString *savedValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYfilterLowLikes"];
				    item.detail = savedValue ?: @"0";
				    item.cellTappedBlock = ^{
				      showTextInputAlert(
					  @"设置过滤赞数阈值", item.detail, @"填0关闭功能",
					  ^(NSString *text) {
					    NSScanner *scanner = [NSScanner scannerWithString:text];
					    NSInteger value;
					    BOOL isValidNumber = [scanner scanInteger:&value] && [scanner isAtEnd];

					    if (isValidNumber) {
						    if (value < 0)
							    value = 0;
						    NSString *valueString = [NSString stringWithFormat:@"%ld", (long)value];
						    setUserDefaults(valueString, @"DYYYfilterLowLikes");

						    item.detail = valueString;
						    UIViewController *topVC = topView();
						    if ([topVC isKindOfClass:%c(AWESettingBaseViewController)]) {
							    dispatch_async(dispatch_get_main_queue(), ^{
							      UITableView *tableView = nil;
							      for (UIView *subview in topVC.view.subviews) {
								      if ([subview isKindOfClass:[UITableView class]]) {
									      tableView = (UITableView *)subview;
									      break;
								      }
							      }

							      if (tableView) {
								      [tableView reloadData];
							      }
							    });
						    }
					    } else {
						    DYYYAboutDialogView *errorDialog = [[DYYYAboutDialogView alloc] initWithTitle:@"输入错误" message:@"请输入有效的数字\n\n\n"];
						    [errorDialog show];
					    }
					  },
					  nil);
				    };
			    } else if ([item.identifier isEqualToString:@"DYYYfilterUsers"]) {
				    NSString *savedValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYfilterUsers"];
				    item.detail = savedValue ?: @"";
				    item.cellTappedBlock = ^{
				      // 将保存的逗号分隔字符串转换为数组
				      NSString *savedKeywords = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYfilterUsers"] ?: @"";
				      NSArray *keywordArray = [savedKeywords length] > 0 ? [savedKeywords componentsSeparatedByString:@","] : @[];

				      // 创建并显示关键词列表视图
				      DYYYKeywordListView *keywordListView = [[DYYYKeywordListView alloc] initWithTitle:@"过滤用户列表" keywords:keywordArray];

				      // 设置确认回调
				      keywordListView.onConfirm = ^(NSArray *keywords) {
					// 将关键词数组转换为逗号分隔的字符串
					NSString *keywordString = [keywords componentsJoinedByString:@","];

					// 保存到用户默认设置
					setUserDefaults(keywordString, @"DYYYfilterUsers");

					// 更新UI显示
					item.detail = keywordString;

					// 刷新表格视图
					UIViewController *topVC = topView();
					if ([topVC isKindOfClass:%c(AWESettingBaseViewController)]) {
						dispatch_async(dispatch_get_main_queue(), ^{
						  UITableView *tableView = nil;
						  for (UIView *subview in topVC.view.subviews) {
							  if ([subview isKindOfClass:[UITableView class]]) {
								  tableView = (UITableView *)subview;
								  break;
							  }
						  }
						  if (tableView) {
							  [tableView reloadData];
						  }
						});
					}
				      };

				      // 显示关键词列表视图
				      [keywordListView show];
				    };
			    } else if ([item.identifier isEqualToString:@"DYYYfilterKeywords"]) {
				    NSString *savedValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYfilterKeywords"];
				    item.detail = savedValue ?: @"";
				    item.cellTappedBlock = ^{
				      // 将保存的逗号分隔字符串转换为数组
				      NSString *savedKeywords = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYfilterKeywords"] ?: @"";
				      NSArray *keywordArray = [savedKeywords length] > 0 ? [savedKeywords componentsSeparatedByString:@","] : @[];

				      // 创建并显示关键词列表视图
				      DYYYKeywordListView *keywordListView = [[DYYYKeywordListView alloc] initWithTitle:@"设置过滤关键词" keywords:keywordArray];

				      // 设置确认回调
				      keywordListView.onConfirm = ^(NSArray *keywords) {
					// 将关键词数组转换为逗号分隔的字符串
					NSString *keywordString = [keywords componentsJoinedByString:@","];

					// 保存到用户默认设置
					setUserDefaults(keywordString, @"DYYYfilterKeywords");

					// 更新UI显示
					item.detail = keywordString;

					// 刷新表格视图
					UIViewController *topVC = topView();
					if ([topVC isKindOfClass:%c(AWESettingBaseViewController)]) {
						dispatch_async(dispatch_get_main_queue(), ^{
						  UITableView *tableView = nil;
						  for (UIView *subview in topVC.view.subviews) {
							  if ([subview isKindOfClass:[UITableView class]]) {
								  tableView = (UITableView *)subview;
								  break;
							  }
						  }
						  if (tableView) {
							  [tableView reloadData];
						  }
						});
					}
				      };

				      // 显示关键词列表视图
				      [keywordListView show];
				    };
			    } else if ([item.identifier isEqualToString:@"DYYYfiltertimelimit"]) {
				    NSString *savedValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYfiltertimelimit"];
				    item.detail = savedValue ?: @"";
				    item.cellTappedBlock = ^{
				      showTextInputAlert(
					  @"过滤视频的发布时间", item.detail, @"单位为天",
					  ^(NSString *text) {
					    NSString *trimmedText = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
					    setUserDefaults(trimmedText, @"DYYYfiltertimelimit");
					    item.detail = trimmedText ?: @"";
					    UIViewController *topVC = topView();
					    if ([topVC isKindOfClass:%c(AWESettingBaseViewController)]) {
						    dispatch_async(dispatch_get_main_queue(), ^{
						      UITableView *tableView = nil;
						      for (UIView *subview in topVC.view.subviews) {
							      if ([subview isKindOfClass:[UITableView class]]) {
								      tableView = (UITableView *)subview;
								      break;
							      }
						      }
						      if (tableView) {
							      [tableView reloadData];
						      }
						    });
					    }
					  },
					  nil);
				    };
			    }
			    [filterItems addObject:item];
		    }

		    // 【二次确认】分类
		    NSMutableArray<AWESettingItemModel *> *securityItems = [NSMutableArray array];
		    NSArray *securitySettings = @[
			    @{@"identifier" : @"DYYYfollowTips",
			      @"title" : @"关注二次确认",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_userplus_outlined_20"},
			    @{@"identifier" : @"DYYYcollectTips",
			      @"title" : @"收藏二次确认",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_collection_outlined_20"}
		    ];

		    for (NSDictionary *dict in securitySettings) {
			    AWESettingItemModel *item = [self createSettingItem:dict cellTapHandlers:cellTapHandlers];
			    [securityItems addObject:item];
		    }

		    // 创建并组织所有section
		    NSMutableArray *sections = [NSMutableArray array];
		    [sections addObject:createSection(@"外观设置", appearanceItems)];
		    [sections addObject:createSection(@"视频播放", videoItems)];
		    [sections addObject:createSection(@"杂项设置", miscellaneousItems)];
		    [sections addObject:createSection(@"过滤与屏蔽", filterItems)];
		    [sections addObject:createSection(@"二次确认", securityItems)];

		    // 创建并推入二级设置页面
		    AWESettingBaseViewController *subVC = createSubSettingsViewController(@"基本设置", sections);
		    [rootVC.navigationController pushViewController:(UIViewController *)subVC animated:YES];
		  };
		  [mainItems addObject:basicSettingItem];

		  // 创建界面设置分类项
		  AWESettingItemModel *uiSettingItem = [[%c(AWESettingItemModel) alloc] init];
		  uiSettingItem.identifier = @"DYYYUISettings";
		  uiSettingItem.title = @"界面设置";
		  uiSettingItem.type = 0;
		  uiSettingItem.svgIconImageName = @"ic_ipadiphone_outlined";
		  uiSettingItem.cellType = 26;
		  uiSettingItem.colorStyle = 0;
		  uiSettingItem.isEnable = YES;
		  uiSettingItem.cellTappedBlock = ^{
		    // 创建界面设置二级界面的设置项
		    NSMutableDictionary *cellTapHandlers = [NSMutableDictionary dictionary];

		    // 【透明度设置】分类
		    NSMutableArray<AWESettingItemModel *> *transparencyItems = [NSMutableArray array];
		    NSArray *transparencySettings = @[
			    @{@"identifier" : @"DYYYtopbartransparent",
			      @"title" : @"设置顶栏透明",
			      @"detail" : @"0-1小数",
			      @"cellType" : @26,
			      @"imageName" : @"ic_module_outlined_20"},
			    @{@"identifier" : @"DYYYGlobalTransparency",
			      @"title" : @"设置全局透明",
			      @"detail" : @"0-1小数",
			      @"cellType" : @26,
			      @"imageName" : @"ic_eye_outlined_20"},
			    @{@"identifier" : @"DYYYAvatarViewTransparency",
			      @"title" : @"首页头像透明",
			      @"detail" : @"0-1小数",
			      @"cellType" : @26,
			      @"imageName" : @"ic_user_outlined_20"},
			    @{@"identifier" : @"DYYYisEnableCommentBlur",
			      @"title" : @"评论区毛玻璃",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_comment_outlined_20"},
			    @{@"identifier" : @"DYYYEnableNotificationTransparency",
			      @"title" : @"通知玻璃效果",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_comment_outlined_20"},
			    @{@"identifier" : @"DYYYCommentBlurTransparent",
			      @"title" : @"毛玻璃透明度",
			      @"detail" : @"0-1小数",
			      @"cellType" : @26,
			      @"imageName" : @"ic_eye_outlined_20"},
			    @{@"identifier" : @"DYYYNotificationCornerRadius",
			      @"title" : @"通知圆角半径",
			      @"detail" : @"默认12",
			      @"cellType" : @26,
			      @"imageName" : @"ic_comment_outlined_20"},
		    ];

		    for (NSDictionary *dict in transparencySettings) {
			    AWESettingItemModel *item = [self createSettingItem:dict cellTapHandlers:cellTapHandlers];
			    [transparencyItems addObject:item];
		    }

		    // 【缩放与大小】分类
		    NSMutableArray<AWESettingItemModel *> *scaleItems = [NSMutableArray array];
		    NSArray *scaleSettings = @[
			    @{@"identifier" : @"DYYYElementScale",
			      @"title" : @"右侧栏缩放度",
			      @"detail" : @"不填默认",
			      @"cellType" : @26,
			      @"imageName" : @"ic_zoomin_outlined_20"},
			    @{@"identifier" : @"DYYYNicknameScale",
			      @"title" : @"昵称文案缩放",
			      @"detail" : @"不填默认",
			      @"cellType" : @26,
			      @"imageName" : @"ic_zoomin_outlined_20"},
			    @{@"identifier" : @"DYYYNicknameVerticalOffset",
			      @"title" : @"昵称下移距离",
			      @"detail" : @"不填默认",
			      @"cellType" : @26,
			      @"imageName" : @"ic_pensketch_outlined_20"},
			    @{@"identifier" : @"DYYYDescriptionVerticalOffset",
			      @"title" : @"文案下移距离",
			      @"detail" : @"不填默认",
			      @"cellType" : @26,
			      @"imageName" : @"ic_pensketch_outlined_20"},
			    @{@"identifier" : @"DYYYIPLabelVerticalOffset",
			      @"title" : @"属地上移距离",
			      @"detail" : @"默认为 3",
			      @"cellType" : @26,
			      @"imageName" : @"ic_pensketch_outlined_20"},
		    ];

		    for (NSDictionary *dict in scaleSettings) {
			    AWESettingItemModel *item = [self createSettingItem:dict cellTapHandlers:cellTapHandlers];
			    [scaleItems addObject:item];
		    }

		    // 【标题自定义】分类
		    NSMutableArray<AWESettingItemModel *> *titleItems = [NSMutableArray array];
		    NSArray *titleSettings = @[
			    @{@"identifier" : @"DYYYIndexTitle",
			      @"title" : @"设置首页标题",
			      @"detail" : @"不填默认",
			      @"cellType" : @26,
			      @"imageName" : @"ic_squaretriangle_outlined_20"},
			    @{@"identifier" : @"DYYYFriendsTitle",
			      @"title" : @"设置朋友标题",
			      @"detail" : @"不填默认",
			      @"cellType" : @26,
			      @"imageName" : @"ic_usertwo_outlined_20"},
			    @{@"identifier" : @"DYYYMsgTitle",
			      @"title" : @"设置消息标题",
			      @"detail" : @"不填默认",
			      @"cellType" : @26,
			      @"imageName" : @"ic_msg_outlined_20"},
			    @{@"identifier" : @"DYYYSelfTitle",
			      @"title" : @"设置我的标题",
			      @"detail" : @"不填默认",
			      @"cellType" : @26,
			      @"imageName" : @"ic_user_outlined_20"},
		    ];

		    for (NSDictionary *dict in titleSettings) {
			    AWESettingItemModel *item = [self createSettingItem:dict cellTapHandlers:cellTapHandlers];
			    [titleItems addObject:item];
		    }

		    // 【图标自定义】分类
		    NSMutableArray<AWESettingItemModel *> *iconItems = [NSMutableArray array];

		    // 添加图标自定义项
		    [iconItems addObject:createIconCustomizationItem(@"DYYYIconLikeBefore", @"未点赞图标", @"ic_heart_outlined_20", @"like_before.png")];
		    [iconItems addObject:createIconCustomizationItem(@"DYYYIconLikeAfter", @"已点赞图标", @"ic_heart_filled_20", @"like_after.png")];
		    [iconItems addObject:createIconCustomizationItem(@"DYYYIconComment", @"评论的图标", @"ic_comment_outlined_20", @"comment.png")];
		    [iconItems addObject:createIconCustomizationItem(@"DYYYIconUnfavorite", @"未收藏图标", @"ic_star_outlined_20", @"unfavorite.png")];
		    [iconItems addObject:createIconCustomizationItem(@"DYYYIconFavorite", @"已收藏图标", @"ic_star_filled_20", @"favorite.png")];
		    [iconItems addObject:createIconCustomizationItem(@"DYYYIconShare", @"分享的图标", @"ic_share_outlined", @"share.png")];

		    // 将图标自定义section添加到sections数组
		    NSMutableArray *sections = [NSMutableArray array];
		    [sections addObject:createSection(@"透明度设置", transparencyItems)];
		    [sections addObject:createSection(@"缩放与大小", scaleItems)];
		    [sections addObject:createSection(@"标题自定义", titleItems)];
		    [sections addObject:createSection(@"图标自定义", iconItems)];
		    // 创建并组织所有section
		    // 创建并推入二级设置页面
		    AWESettingBaseViewController *subVC = createSubSettingsViewController(@"界面设置", sections);
		    [rootVC.navigationController pushViewController:(UIViewController *)subVC animated:YES];
		  };

		  [mainItems addObject:uiSettingItem];

		  // 创建隐藏设置分类项
		  AWESettingItemModel *hideSettingItem = [[%c(AWESettingItemModel) alloc] init];
		  hideSettingItem.identifier = @"DYYYHideSettings";
		  hideSettingItem.title = @"隐藏设置";
		  hideSettingItem.type = 0;
		  hideSettingItem.svgIconImageName = @"ic_eyeslash_outlined_20";
		  hideSettingItem.cellType = 26;
		  hideSettingItem.colorStyle = 0;
		  hideSettingItem.isEnable = YES;
		  hideSettingItem.cellTappedBlock = ^{
		    // 创建隐藏设置二级界面的设置项

		    // 【主界面元素】分类
		    NSMutableArray<AWESettingItemModel *> *mainUiItems = [NSMutableArray array];
		    NSArray *mainUiSettings = @[
			    @{@"identifier" : @"DYYYisHiddenBottomBg",
			      @"title" : @"隐藏底栏背景",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYisHiddenBottomDot",
			      @"title" : @"隐藏底栏红点",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYHideShopButton",
			      @"title" : @"隐藏底栏商城",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYHideMessageButton",
			      @"title" : @"隐藏底栏消息",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYHideFriendsButton",
			      @"title" : @"隐藏底栏朋友",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYisHiddenJia",
			      @"title" : @"隐藏底栏加号",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYHideTopBarBadge",
			      @"title" : @"隐藏顶栏红点",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"}
		    ];

		    for (NSDictionary *dict in mainUiSettings) {
			    AWESettingItemModel *item = [self createSettingItem:dict];
			    [mainUiItems addObject:item];
		    }

		    // 【视频播放界面】分类
		    NSMutableArray<AWESettingItemModel *> *videoUiItems = [NSMutableArray array];
		    NSArray *videoUiSettings = @[
			    @{@"identifier" : @"DYYYHideLOTAnimationView",
			      @"title" : @"隐藏头像加号",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYHideLikeLabel",
			      @"title" : @"隐藏点赞数值",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYHideCommentLabel",
			      @"title" : @"隐藏评论数值",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYHideCollectLabel",
			      @"title" : @"隐藏收藏数值",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYHideShareLabel",
			      @"title" : @"隐藏分享数值",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYHideLikeButton",
			      @"title" : @"隐藏点赞按钮",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYHideCommentButton",
			      @"title" : @"隐藏评论按钮",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYHideCollectButton",
			      @"title" : @"隐藏收藏按钮",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYHideShareButton",
			      @"title" : @"隐藏分享按钮",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYHideAvatarButton",
			      @"title" : @"隐藏头像按钮",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYHideMusicButton",
			      @"title" : @"隐藏音乐按钮",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYisHiddenEntry",
			      @"title" : @"隐藏全屏观看",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"}
		    ];

		    for (NSDictionary *dict in videoUiSettings) {
			    AWESettingItemModel *item = [self createSettingItem:dict];
			    [videoUiItems addObject:item];
		    }

		    // 【侧边栏】分类
		    NSMutableArray<AWESettingItemModel *> *sidebarItems = [NSMutableArray array];
		    NSArray *sidebarSettings = @[
			    @{@"identifier" : @"DYYYisHiddenSidebarDot",
			      @"title" : @"隐藏侧栏红点",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYisHiddenLeftSideBar",
			      @"title" : @"隐藏左侧边栏",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
		    ];

		    for (NSDictionary *dict in sidebarSettings) {
			    AWESettingItemModel *item = [self createSettingItem:dict];
			    [sidebarItems addObject:item];
		    }

		    // 【消息页与我的页】分类
		    NSMutableArray<AWESettingItemModel *> *messageAndMineItems = [NSMutableArray array];
		    NSArray *messageAndMineSettings = @[
			    @{@"identifier" : @"DYYYHidePushBanner",
			      @"title" : @"隐藏通知权限提示",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYisHiddenAvatarList",
			      @"title" : @"隐藏消息头像列表",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYisHiddenAvatarBubble",
			      @"title" : @"隐藏消息头像气泡",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYHideGroupShop",
			      @"title" : @"隐藏群聊商店按钮",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYGroupLiving",
			      @"title" : @"隐藏群头像直播中",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYHideGroupInputActionBar",
			      @"title" : @"隐藏群聊页工具栏",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYHidePostView",
			      @"title" : @"隐藏我的页发作品",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"}
		    ];
		    for (NSDictionary *dict in messageAndMineSettings) {
			    AWESettingItemModel *item = [self createSettingItem:dict];
			    [messageAndMineItems addObject:item];
		    }

		    // 【提示与位置信息】分类
		    NSMutableArray<AWESettingItemModel *> *infoItems = [NSMutableArray array];
		    NSArray *infoSettings = @[
			    @{@"identifier" : @"DYYYHidenLiveView",
			      @"title" : @"隐藏关注顶端",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYHideMenuView",
			      @"title" : @"隐藏同城顶端",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYHideNearbyCapsuleView",
			      @"title" : @"隐藏吃喝玩乐",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYHideDiscover",
			      @"title" : @"隐藏右上搜索",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYHideInteractionSearch",
			      @"title" : @"隐藏相关搜索",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYHideDanmuButton",
			      @"title" : @"隐藏弹幕按钮",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYHideCancelMute",
			      @"title" : @"隐藏静音按钮",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYHideLocation",
			      @"title" : @"隐藏视频定位",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYHideQuqishuiting",
			      @"title" : @"隐藏去汽水听",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYHideGongChuang",
			      @"title" : @"隐藏共创头像",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYHideHotspot",
			      @"title" : @"隐藏热点提示",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYHideRecommendTips",
			      @"title" : @"隐藏推荐提示",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYHideBottomRelated",
			      @"title" : @"隐藏底部相关",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYHideShareContentView",
			      @"title" : @"隐藏分享提示",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYHideAntiAddictedNotice",
			      @"title" : @"隐藏作者声明",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYHideFeedAnchorContainer",
			      @"title" : @"隐藏拍摄同款",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYHideChallengeStickers",
			      @"title" : @"隐藏挑战贴纸",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYHideTemplateTags",
			      @"title" : @"隐藏校园提示",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYHideHisShop",
			      @"title" : @"隐藏作者店铺",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYHideConcernCapsuleView",
			      @"title" : @"隐藏关注直播",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYHidentopbarprompt",
			      @"title" : @"隐藏顶栏横线",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYHideTemplateVideo",
			      @"title" : @"隐藏视频合集",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYHideTemplatePlaylet",
			      @"title" : @"隐藏短剧合集",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYHideLiveGIF",
			      @"title" : @"隐藏动图标签",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYHideItemTag",
			      @"title" : @"隐藏笔记标签",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYHideTemplateGroup",
			      @"title" : @"隐藏底部话题",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYHideCameraLocation",
			      @"title" : @"隐藏相机定位",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYHideCommentViews",
			      @"title" : @"隐藏评论视图",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYHideLiveCapsuleView",
			      @"title" : @"隐藏直播胶囊",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYHideStoryProgressSlide",
			      @"title" : @"隐藏视频滑条",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYHideDotsIndicator",
			      @"title" : @"隐藏图片滑条",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYHidePrivateMessages",
			      @"title" : @"隐藏分享私信",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYHideRightLable",
			      @"title" : @"隐藏昵称右侧",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYHideChatCommentBg",
			      @"title" : @"聊天评论透明",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
		    ];

		    for (NSDictionary *dict in infoSettings) {
			    AWESettingItemModel *item = [self createSettingItem:dict];
			    [infoItems addObject:item];
		    }

		    // 【直播界面净化】分类
		    NSMutableArray<AWESettingItemModel *> *livestreamItems = [NSMutableArray array];
		    NSArray *livestreamSettings = @[
			    @{@"identifier" : @"DYYYHideLivePlayground",
			      @"title" : @"隐藏直播广场",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYHideEnterLive",
			      @"title" : @"隐藏进入直播",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYHideGiftPavilion",
			      @"title" : @"隐藏礼物展馆",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYHideLiveRoomClear",
			      @"title" : @"隐藏退出清屏",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYHideLiveRoomMirroring",
			      @"title" : @"隐藏投屏按钮",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYHideLiveDiscovery",
			      @"title" : @"隐藏直播发现",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYHideKTVSongIndicator",
			      @"title" : @"隐藏直播点歌",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"},
			    @{@"identifier" : @"DYYYHideCellularAlert",
			      @"title" : @"隐藏流量提醒",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"}

		    ];
		    for (NSDictionary *dict in livestreamSettings) {
			    AWESettingItemModel *item = [self createSettingItem:dict];
			    [livestreamItems addObject:item];
		    }

		    // 创建并组织所有section
		    NSMutableArray *sections = [NSMutableArray array];
		    [sections addObject:createSection(@"主界面元素", mainUiItems)];
		    [sections addObject:createSection(@"视频播放界面", videoUiItems)];
		    [sections addObject:createSection(@"侧边栏元素", sidebarItems)];
		    [sections addObject:createSection(@"消息页与我的页", messageAndMineItems)];
		    [sections addObject:createSection(@"提示与位置信息", infoItems)];
		    [sections addObject:createSection(@"直播间界面", livestreamItems)];

		    // 创建并推入二级设置页面
		    AWESettingBaseViewController *subVC = createSubSettingsViewController(@"隐藏设置", sections);
		    [rootVC.navigationController pushViewController:(UIViewController *)subVC animated:YES];
		  };
		  [mainItems addObject:hideSettingItem];

		  // 创建顶栏移除分类项
		  AWESettingItemModel *removeSettingItem = [[%c(AWESettingItemModel) alloc] init];
		  removeSettingItem.identifier = @"DYYYRemoveSettings";
		  removeSettingItem.title = @"顶栏移除";
		  removeSettingItem.type = 0;
		  removeSettingItem.svgIconImageName = @"ic_doublearrowup_outlined_20";
		  removeSettingItem.cellType = 26;
		  removeSettingItem.colorStyle = 0;
		  removeSettingItem.isEnable = YES;
		  removeSettingItem.cellTappedBlock = ^{
		    // 创建顶栏移除二级界面的设置项
		    NSMutableArray<AWESettingItemModel *> *removeSettingsItems = [NSMutableArray array];
		    NSArray *removeSettings = @[
			    @{@"identifier" : @"DYYYHideHotContainer",
			      @"title" : @"移除推荐",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_xmark_outlined_20"},
			    @{@"identifier" : @"DYYYHideFollow",
			      @"title" : @"移除关注",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_xmark_outlined_20"},
			    @{@"identifier" : @"DYYYHideMediumVideo",
			      @"title" : @"移除精选",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_xmark_outlined_20"},
			    @{@"identifier" : @"DYYYHideMall",
			      @"title" : @"移除商城",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_xmark_outlined_20"},
			    @{@"identifier" : @"DYYYHideNearby",
			      @"title" : @"移除同城",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_xmark_outlined_20"},
			    @{@"identifier" : @"DYYYHideGroupon",
			      @"title" : @"移除团购",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_xmark_outlined_20"},
			    @{@"identifier" : @"DYYYHideTabLive",
			      @"title" : @"移除直播",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_xmark_outlined_20"},
			    @{@"identifier" : @"DYYYHidePadHot",
			      @"title" : @"移除热点",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_xmark_outlined_20"},
			    @{@"identifier" : @"DYYYHideHangout",
			      @"title" : @"移除经验",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_xmark_outlined_20"},
			    @{@"identifier" : @"DYYYHidePlaylet",
			      @"title" : @"移除短剧",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_xmark_outlined_20"}
		    ];

		    for (NSDictionary *dict in removeSettings) {
			    AWESettingItemModel *item = [[%c(AWESettingItemModel) alloc] init];
			    item.identifier = dict[@"identifier"];
			    item.title = dict[@"title"];
			    NSString *savedDetail = [[NSUserDefaults standardUserDefaults] objectForKey:item.identifier];
			    item.detail = savedDetail ?: dict[@"detail"];
			    item.type = 1000;
			    item.svgIconImageName = dict[@"imageName"];
			    item.cellType = [dict[@"cellType"] integerValue];
			    item.colorStyle = 0;
			    item.isEnable = YES;
			    item.isSwitchOn = getUserDefaults(item.identifier);
			    __weak AWESettingItemModel *weakItem = item;
			    item.switchChangedBlock = ^{
			      __strong AWESettingItemModel *strongItem = weakItem;
			      if (strongItem) {
				      BOOL isSwitchOn = !strongItem.isSwitchOn;
				      strongItem.isSwitchOn = isSwitchOn;
				      setUserDefaults(@(isSwitchOn), strongItem.identifier);
			      }
			    };
			    [removeSettingsItems addObject:item];
		    }

		    NSMutableArray *sections = [NSMutableArray array];
		    [sections addObject:createSection(@"顶栏选项", removeSettingsItems)];

		    // 创建并推入二级设置页面，使用sections数组而不是直接使用removeSettingsItems
		    AWESettingBaseViewController *subVC = createSubSettingsViewController(@"顶栏移除", sections);
		    [rootVC.navigationController pushViewController:(UIViewController *)subVC animated:YES];
		  };
		  [mainItems addObject:removeSettingItem];

		  // 创建增强设置分类项
		  AWESettingItemModel *enhanceSettingItem = [[%c(AWESettingItemModel) alloc] init];
		  enhanceSettingItem.identifier = @"DYYYEnhanceSettings";
		  enhanceSettingItem.title = @"增强设置";
		  enhanceSettingItem.type = 0;
		  enhanceSettingItem.svgIconImageName = @"ic_squaresplit_outlined_20";
		  enhanceSettingItem.cellType = 26;
		  enhanceSettingItem.colorStyle = 0;
		  enhanceSettingItem.isEnable = YES;
		  enhanceSettingItem.cellTappedBlock = ^{
		    // 创建增强设置二级界面的设置项

		    // 【复制功能】分类
		    NSMutableArray<AWESettingItemModel *> *copyItems = [NSMutableArray array];
		    NSArray *copySettings = @[
			    @{@"identifier" : @"DYYYCopyText",
			      @"title" : @"长按面板复制功能",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_rectangleonrectangleup_outlined_20"},
			    @{@"identifier" : @"DYYYCommentCopyText",
			      @"title" : @"长按评论复制文案",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_at_outlined_20"}
		    ];

		    for (NSDictionary *dict in copySettings) {
			    AWESettingItemModel *item = [self createSettingItem:dict];
			    [copyItems addObject:item];
		    }

		    // 【过滤功能】分类
		    NSMutableArray<AWESettingItemModel *> *filterItems = [NSMutableArray array];
		    NSArray *filterSettings = @[
			    @{@"identifier" : @"DYYYLongPressFilterUser",
			      @"title" : @"长按面板过滤用户",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_userban_outlined_20"},
			    @{@"identifier" : @"DYYYLongPressFilterTitle",
			      @"title" : @"长按面板过滤标题",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_funnel_outlined_20"}
		    ];

		    for (NSDictionary *dict in filterSettings) {
			    AWESettingItemModel *item = [self createSettingItem:dict];
			    [filterItems addObject:item];
		    }

		    // 【媒体保存】分类
		    NSMutableArray<AWESettingItemModel *> *downloadItems = [NSMutableArray array];
		    NSArray *downloadSettings = @[
			    @{@"identifier" : @"DYYYLongPressDownload",
			      @"title" : @"长按面板保存媒体",
			      @"detail" : @"无水印保存",
			      @"cellType" : @6,
			      @"imageName" : @"ic_boxarrowdown_outlined"},
			    @{@"identifier" : @"DYYYInterfaceDownload",
			      @"title" : @"接口解析保存媒体",
			      @"detail" : @"不填关闭",
			      @"cellType" : @26,
			      @"imageName" : @"ic_cloudarrowdown_outlined_20"},
			    @{@"identifier" : @"DYYYShowAllVideoQuality",
			      @"title" : @"接口显示清晰选项",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_hamburgernut_outlined_20"},
			    @{@"identifier" : @"DYYYCommentLivePhotoNotWaterMark",
			      @"title" : @"移除评论实况水印",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_livephoto_outlined_20"},
			    @{@"identifier" : @"DYYYCommentNotWaterMark",
			      @"title" : @"移除评论图片水印",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_removeimage_outlined_20"},
			    @{@"identifier" : @"DYYYFourceDownloadEmotion",
			      @"title" : @"保存评论区表情包",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_emoji_outlined"}
		    ];

		    for (NSDictionary *dict in downloadSettings) {
			    AWESettingItemModel *item = [self createSettingItem:dict];

			    // 特殊处理接口解析保存媒体选项
			    if ([item.identifier isEqualToString:@"DYYYInterfaceDownload"]) {
				    // 获取已保存的接口URL
				    NSString *savedURL = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYInterfaceDownload"];
				    item.detail = savedURL.length > 0 ? savedURL : @"不填关闭";

				    item.cellTappedBlock = ^{
				      NSString *defaultText = [item.detail isEqualToString:@"不填关闭"] ? @"" : item.detail;
				      showTextInputAlert(
					  @"设置媒体解析接口", defaultText, @"解析接口以url=结尾",
					  ^(NSString *text) {
					    // 保存用户输入的接口URL
					    NSString *trimmedText = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
					    setUserDefaults(trimmedText, @"DYYYInterfaceDownload");

					    // 更新UI显示
					    item.detail = trimmedText.length > 0 ? trimmedText : @"不填关闭";

					    // 刷新设置表格
					    UIViewController *topVC = topView();
					    if ([topVC isKindOfClass:%c(AWESettingBaseViewController)]) {
						    dispatch_async(dispatch_get_main_queue(), ^{
						      UITableView *tableView = nil;
						      for (UIView *subview in topVC.view.subviews) {
							      if ([subview isKindOfClass:[UITableView class]]) {
								      tableView = (UITableView *)subview;
								      break;
							      }
						      }

						      if (tableView) {
							      [tableView reloadData];
						      }
						    });
					    }
					  },
					  nil);
				    };
			    }

			    [downloadItems addObject:item];
		    }

		    // 【热更新】分类
		    NSMutableArray<AWESettingItemModel *> *hotUpdateItems = [NSMutableArray array];

		    // 获取当前热更新状态
		    abTestBlockEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:@"ABTestBlockEnabled"];

		    // 添加"禁用热更新"开关
		    AWESettingItemModel *disableHotUpdateItem = [[%c(AWESettingItemModel) alloc] init];
		    disableHotUpdateItem.identifier = @"ABTestBlockEnabled";
		    disableHotUpdateItem.title = @"禁用下发配置";
		    disableHotUpdateItem.detail = @"";
		    disableHotUpdateItem.type = 1000;
		    disableHotUpdateItem.svgIconImageName = @"ic_fire_outlined_20";
		    disableHotUpdateItem.cellType = 6;
		    disableHotUpdateItem.colorStyle = 0;
		    disableHotUpdateItem.isEnable = YES;
		    disableHotUpdateItem.isSwitchOn = abTestBlockEnabled;

		    disableHotUpdateItem.switchChangedBlock = ^{
		      BOOL newValue = !disableHotUpdateItem.isSwitchOn;
		      disableHotUpdateItem.isSwitchOn = newValue;
		      abTestBlockEnabled = newValue;

		      // 保存设置
		      [[NSUserDefaults standardUserDefaults] setBool:newValue forKey:@"ABTestBlockEnabled"];
		      [[NSUserDefaults standardUserDefaults] synchronize];

		      // 如果启用了拦截，重新加载固定数据
		      if (newValue) {
			      // 重置全局变量，下次加载时会重新读取文件
			      gFixedABTestData = nil;
			      onceToken = 0;
			      loadFixedABTestData();
		      }

		      // 刷新表格以反映状态变化
		      UIViewController *topVC = topView();
		      if ([topVC isKindOfClass:%c(AWESettingBaseViewController)]) {
			      dispatch_async(dispatch_get_main_queue(), ^{
				UITableView *tableView = nil;
				for (UIView *subview in topVC.view.subviews) {
					if ([subview isKindOfClass:[UITableView class]]) {
						tableView = (UITableView *)subview;
						break;
					}
				}
				if (tableView) {
					[tableView reloadData];
				}
			      });
		      }
		    };

		    [hotUpdateItems addObject:disableHotUpdateItem];

		    // 添加"保存当前配置"按钮
		    AWESettingItemModel *saveCurrentConfigItem = [[%c(AWESettingItemModel) alloc] init];
		    saveCurrentConfigItem.identifier = @"SaveCurrentABTestData";
		    saveCurrentConfigItem.title = @"保存当前配置";
		    saveCurrentConfigItem.detail = @"";
		    saveCurrentConfigItem.type = 0;
		    saveCurrentConfigItem.svgIconImageName = @"ic_memorycard_outlined_20";
		    saveCurrentConfigItem.cellType = 26;
		    saveCurrentConfigItem.colorStyle = 0;
		    saveCurrentConfigItem.isEnable = YES;

		    saveCurrentConfigItem.cellTappedBlock = ^{
		      // 获取当前ABTest配置数据
		      NSDictionary *currentData = getCurrentABTestData();

		      if (!currentData) {
			      [DYYYManager showToast:@"获取ABTest配置失败"];
			      return;
		      }

		      // 转换为JSON数据
		      NSError *error;
		      NSData *jsonData = [NSJSONSerialization dataWithJSONObject:currentData options:NSJSONWritingPrettyPrinted error:&error];

		      if (error) {
			      [DYYYManager showToast:@"序列化配置数据失败"];
			      return;
		      }

		      // 创建带时间戳的文件名
		      NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
		      [formatter setDateFormat:@"yyyyMMdd_HHmmss"];
		      NSString *timestamp = [formatter stringFromDate:[NSDate date]];
		      NSString *filename = [NSString stringWithFormat:@"ABTest_Config_%@.json", timestamp];

		      // 创建临时文件
		      NSString *tempDir = NSTemporaryDirectory();
		      NSString *tempFilePath = [tempDir stringByAppendingPathComponent:filename];

		      // 写入临时文件
		      BOOL success = [jsonData writeToFile:tempFilePath atomically:YES];

		      if (!success) {
			      [DYYYManager showToast:@"创建临时文件失败"];
			      return;
		      }

		      // 创建文档选择器让用户选择保存位置
		      NSURL *tempFileURL = [NSURL fileURLWithPath:tempFilePath];
		      UIDocumentPickerViewController *documentPicker = [[UIDocumentPickerViewController alloc] initWithURLs:@[ tempFileURL ] inMode:UIDocumentPickerModeExportToService];

		      DYYYBackupPickerDelegate *pickerDelegate = [[DYYYBackupPickerDelegate alloc] init];
		      pickerDelegate.tempFilePath = tempFilePath; // 设置临时文件路径，以便之后清理
		      pickerDelegate.completionBlock = ^(NSURL *url) {
			// 保存成功
			[DYYYManager showToast:@"ABTest配置已保存"];
		      };

		      static char kABTestPickerDelegateKey;
		      documentPicker.delegate = pickerDelegate;
		      objc_setAssociatedObject(documentPicker, &kABTestPickerDelegateKey, pickerDelegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

		      // 显示文档选择器
		      UIViewController *topVC = topView();
		      [topVC presentViewController:documentPicker animated:YES completion:nil];
		    };
		    [hotUpdateItems addObject:saveCurrentConfigItem];

		    // 添加"选择本地配置"按钮
		    AWESettingItemModel *loadConfigItem = [[%c(AWESettingItemModel) alloc] init];
		    loadConfigItem.identifier = @"LoadABTestConfigFile";
		    loadConfigItem.title = @"本地选择配置";
		    loadConfigItem.detail = @"";
		    loadConfigItem.type = 0;
		    loadConfigItem.svgIconImageName = @"ic_phonearrowup_outlined_20";
		    loadConfigItem.cellType = 26;
		    loadConfigItem.colorStyle = 0;
		    loadConfigItem.isEnable = YES;

		    loadConfigItem.cellTappedBlock = ^{
		      UIDocumentPickerViewController *documentPicker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[ @"public.json" ] inMode:UIDocumentPickerModeImport];

		      // 创建代理对象来处理文件选择
		      DYYYBackupPickerDelegate *pickerDelegate = [[DYYYBackupPickerDelegate alloc] init];
		      pickerDelegate.completionBlock = ^(NSURL *url) {
			// 获取选择的文件路径
			NSString *sourcePath = [url path];

			// 目标路径
			NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
			NSString *documentsDirectory = [paths firstObject];
			NSString *dyyyFolderPath = [documentsDirectory stringByAppendingPathComponent:@"DYYY"];
			NSString *destPath = [dyyyFolderPath stringByAppendingPathComponent:@"abtest_data_fixed.json"];

			// 确保DYYY目录存在
			if (![[NSFileManager defaultManager] fileExistsAtPath:dyyyFolderPath]) {
				[[NSFileManager defaultManager] createDirectoryAtPath:dyyyFolderPath withIntermediateDirectories:YES attributes:nil error:nil];
			}

			NSError *error;
			// 如果目标文件已存在，先删除
			if ([[NSFileManager defaultManager] fileExistsAtPath:destPath]) {
				[[NSFileManager defaultManager] removeItemAtPath:destPath error:&error];
				if (error) {
					NSLog(@"[ABTest] 删除旧配置文件失败: %@", error);
				}
			}

			// 复制文件
			BOOL success = [[NSFileManager defaultManager] copyItemAtPath:sourcePath toPath:destPath error:&error];

			NSString *message;
			if (success) {
				// 重置全局变量，下次加载时会重新读取文件
				gFixedABTestData = nil;
				onceToken = 0;
				// 重新加载配置
				loadFixedABTestData();
				message = @"配置文件已导入，请禁用下发配置，重启抖音生效";
			} else {
				message = [NSString stringWithFormat:@"导入失败: %@", error.localizedDescription];
			}

			// 显示结果提示
			[DYYYManager showToast:message];
		      };

		      // 保存代理对象的引用，防止它被提前释放
		      static char kPickerDelegateKey;
		      documentPicker.delegate = pickerDelegate;
		      objc_setAssociatedObject(documentPicker, &kPickerDelegateKey, pickerDelegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

		      // 显示文件选择器
		      UIViewController *topVC = topView();
		      [topVC presentViewController:documentPicker animated:YES completion:nil];
		    };

		    [hotUpdateItems addObject:loadConfigItem];
		    // 添加"删除本地配置"按钮
		    AWESettingItemModel *deleteConfigItem = [[%c(AWESettingItemModel) alloc] init];
		    deleteConfigItem.identifier = @"DeleteABTestConfigFile";
		    deleteConfigItem.title = @"删除本地配置";
		    deleteConfigItem.detail = @"";
		    deleteConfigItem.type = 0;
		    deleteConfigItem.svgIconImageName = @"ic_xmark_outlined_20";
		    deleteConfigItem.cellType = 26;
		    deleteConfigItem.colorStyle = 0;
		    deleteConfigItem.isEnable = YES;

		    deleteConfigItem.cellTappedBlock = ^{
		      // 目标路径
		      NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
		      NSString *documentsDirectory = [paths firstObject];
		      NSString *dyyyFolderPath = [documentsDirectory stringByAppendingPathComponent:@"DYYY"];
		      NSString *configPath = [dyyyFolderPath stringByAppendingPathComponent:@"abtest_data_fixed.json"];

		      // 检查文件是否存在
		      if ([[NSFileManager defaultManager] fileExistsAtPath:configPath]) {
			      // 删除文件
			      NSError *error = nil;
			      BOOL success = [[NSFileManager defaultManager] removeItemAtPath:configPath error:&error];

			      if (success) {
				      // 重置全局变量
				      gFixedABTestData = nil;
				      onceToken = 0;

				      // 显示成功提示
				      [DYYYManager showToast:@"本地配置已删除成功"];
			      } else {
				      // 显示错误信息
				      NSString *errorMsg = [NSString stringWithFormat:@"删除失败: %@", error.localizedDescription];
				      [DYYYManager showToast:errorMsg];
			      }
		      } else {
			      // 文件不存在
			      [DYYYManager showToast:@"本地配置不存在"];
		      }
		    };

		    [hotUpdateItems addObject:deleteConfigItem];

		    // 【交互增强】分类
		    NSMutableArray<AWESettingItemModel *> *interactionItems = [NSMutableArray array];
		    NSArray *interactionSettings = @[
			    @{@"identifier" : @"DYYYisEnableModern",
			      @"title" : @"启用新版玻璃面板",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_gearsimplify_outlined_20"},
			    @{@"identifier" : @"DYYYEnableSaveAvatar",
			      @"title" : @"启用保存他人头像",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_personcircleclean_outlined_20"},
			    @{@"identifier" : @"DYYYDisableHomeRefresh",
			      @"title" : @"禁用点击首页刷新",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_arrowcircle_outlined_20"},
			    @{@"identifier" : @"DYYYDouble",
			      @"title" : @"禁用双击视频点赞",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_thumbsup_outlined_20"},
			    @{@"identifier" : @"DYYYEnableDoubleOpenComment",
			      @"title" : @"启用双击打开评论",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_comment_outlined_20"},
			    @{
				    @"identifier" : @"DYYYEnableDoubleOpenAlertController",
				    @"title" : @"启用双击打开菜单",
				    @"detail" : @"",
				    @"cellType" : @26,
				    @"imageName" : @"ic_xiaoxihuazhonghua_outlined_20"
			    }
		    ];

		    for (NSDictionary *dict in interactionSettings) {
			    AWESettingItemModel *item = [self createSettingItem:dict];
			    // 为双击菜单选项添加特殊处理
			    if ([item.identifier isEqualToString:@"DYYYEnableDoubleOpenAlertController"]) {
				    item.cellTappedBlock = ^{
				      // 检查是否启用了双击打开评论功能
				      BOOL isEnableDoubleOpenComment = getUserDefaults(@"DYYYEnableDoubleOpenComment");
				      if (isEnableDoubleOpenComment) {
					      return;
				      }

				      NSMutableArray<AWESettingItemModel *> *doubleTapItems = [NSMutableArray array];
				      AWESettingItemModel *enableDoubleTapMenu = [self createSettingItem:@{
					      @"identifier" : @"DYYYEnableDoubleOpenAlertController",
					      @"title" : @"启用双击打开菜单",
					      @"detail" : @"",
					      @"cellType" : @6,
					      @"imageName" : @"ic_xiaoxihuazhonghua_outlined_20"
				      }];
				      [doubleTapItems addObject:enableDoubleTapMenu];

				      NSArray *doubleTapFunctions = @[
					      @{@"identifier" : @"DYYYDoubleTapDownload",
						@"title" : @"保存视频/图片",
						@"detail" : @"",
						@"cellType" : @6,
						@"imageName" : @"ic_boxarrowdown_outlined"},
					      @{@"identifier" : @"DYYYDoubleTapDownloadAudio",
						@"title" : @"保存音频",
						@"detail" : @"",
						@"cellType" : @6,
						@"imageName" : @"ic_boxarrowdown_outlined"},
					      @{
						      @"identifier" : @"DYYYDoubleInterfaceDownload",
						      @"title" : @"接口保存",
						      @"detail" : @"",
						      @"cellType" : @6,
						      @"imageName" : @"ic_cloudarrowdown_outlined_20"
					      },
					      @{
						      @"identifier" : @"DYYYDoubleTapCopyDesc",
						      @"title" : @"复制文案",
						      @"detail" : @"",
						      @"cellType" : @6,
						      @"imageName" : @"ic_rectangleonrectangleup_outlined_20"
					      },
					      @{@"identifier" : @"DYYYDoubleTapComment",
						@"title" : @"打开评论",
						@"detail" : @"",
						@"cellType" : @6,
						@"imageName" : @"ic_comment_outlined_20"},
					      @{@"identifier" : @"DYYYDoubleTapLike",
						@"title" : @"点赞视频",
						@"detail" : @"",
						@"cellType" : @6,
						@"imageName" : @"ic_heart_outlined_20"},
					      @{
						      @"identifier" : @"DYYYDoubleTapshowDislikeOnVideo",
						      @"title" : @"长按面板",
						      @"detail" : @"",
						      @"cellType" : @6,
						      @"imageName" : @"ic_xiaoxihuazhonghua_outlined_20"
					      },
					      @{@"identifier" : @"DYYYDoubleTapshowSharePanel",
						@"title" : @"分享视频",
						@"detail" : @"",
						@"cellType" : @6,
						@"imageName" : @"ic_share_outlined"},
				      ];

				      for (NSDictionary *dict in doubleTapFunctions) {
					      AWESettingItemModel *functionItem = [self createSettingItem:dict];
					      [doubleTapItems addObject:functionItem];
				      }
				      NSMutableArray *sections = [NSMutableArray array];
				      [sections addObject:createSection(@"双击菜单设置", doubleTapItems)];
				      UIViewController *rootVC = self.controllerDelegate;
				      AWESettingBaseViewController *subVC = createSubSettingsViewController(@"双击菜单设置", sections);
				      [rootVC.navigationController pushViewController:(UIViewController *)subVC animated:YES];
				    };
			    }

			    [interactionItems addObject:item];
		    }

		    // 创建并组织所有section
		    NSMutableArray *sections = [NSMutableArray array];
		    [sections addObject:createSection(@"复制功能", copyItems)];
		    [sections addObject:createSection(@"过滤功能", filterItems)];
		    [sections addObject:createSection(@"媒体保存", downloadItems)];
		    [sections addObject:createSection(@"交互增强", interactionItems)];
		    [sections addObject:createSection(@"热更新", hotUpdateItems)];
		    // 创建并推入二级设置页面
		    AWESettingBaseViewController *subVC = createSubSettingsViewController(@"增强设置", sections);
		    [rootVC.navigationController pushViewController:(UIViewController *)subVC animated:YES];
		  };

		  [mainItems addObject:enhanceSettingItem];

		  // 创建悬浮按钮设置分类项
		  AWESettingItemModel *floatButtonSettingItem = [[%c(AWESettingItemModel) alloc] init];
		  floatButtonSettingItem.identifier = @"DYYYFloatButtonSettings";
		  floatButtonSettingItem.title = @"悬浮按钮";
		  floatButtonSettingItem.type = 0;
		  floatButtonSettingItem.svgIconImageName = @"ic_gongchuang_outlined_20";
		  floatButtonSettingItem.cellType = 26;
		  floatButtonSettingItem.colorStyle = 0;
		  floatButtonSettingItem.isEnable = YES;
		  floatButtonSettingItem.cellTappedBlock = ^{
		    // 创建悬浮按钮设置二级界面的设置项

		    // 快捷倍速section
		    NSMutableArray<AWESettingItemModel *> *speedButtonItems = [NSMutableArray array];

		    // 倍速按钮
		    AWESettingItemModel *enableSpeedButton = [self
			createSettingItem:
			    @{@"identifier" : @"DYYYEnableFloatSpeedButton",
			      @"title" : @"启用快捷倍速按钮",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_speed_outlined_20"}];
		    [speedButtonItems addObject:enableSpeedButton];

		    // 添加倍速设置项
		    AWESettingItemModel *speedSettingsItem = [[%c(AWESettingItemModel) alloc] init];
		    speedSettingsItem.identifier = @"DYYYSpeedSettings";
		    speedSettingsItem.title = @"快捷倍速数值设置";
		    speedSettingsItem.type = 0;
		    speedSettingsItem.svgIconImageName = @"ic_speed_outlined_20";
		    speedSettingsItem.cellType = 26;
		    speedSettingsItem.colorStyle = 0;
		    speedSettingsItem.isEnable = YES;

		    // 获取已保存的倍速数值设置
		    NSString *savedSpeedSettings = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYSpeedSettings"];
		    // 如果没有设置过，使用默认值
		    if (!savedSpeedSettings || savedSpeedSettings.length == 0) {
			    savedSpeedSettings = @"1.0,1.25,1.5,2.0";
		    }
		    speedSettingsItem.detail = [NSString stringWithFormat:@"%@", savedSpeedSettings];
		    speedSettingsItem.cellTappedBlock = ^{
		      showTextInputAlert(
			  @"设置快捷倍速数值", speedSettingsItem.detail, @"使用半角逗号(,)分隔倍速值",
			  ^(NSString *text) {
			    // 保存用户输入的倍速值
			    NSString *trimmedText = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
			    [[NSUserDefaults standardUserDefaults] setObject:trimmedText forKey:@"DYYYSpeedSettings"];
			    [[NSUserDefaults standardUserDefaults] synchronize];

			    // 更新UI显示
			    speedSettingsItem.detail = trimmedText;

			    // 刷新表格以反映更改
			    UIViewController *topVC = topView();
			    if ([topVC isKindOfClass:%c(AWESettingBaseViewController)]) {
				    dispatch_async(dispatch_get_main_queue(), ^{
				      UITableView *tableView = nil;
				      for (UIView *subview in topVC.view.subviews) {
					      if ([subview isKindOfClass:[UITableView class]]) {
						      tableView = (UITableView *)subview;
						      break;
					      }
				      }

				      if (tableView) {
					      [tableView reloadData];
				      }
				    });
			    }
			  },
			  nil);
		    };

		    // 添加自动恢复倍速设置项
		    AWESettingItemModel *autoRestoreSpeedItem = [[%c(AWESettingItemModel) alloc] init];
		    autoRestoreSpeedItem.identifier = @"DYYYAutoRestoreSpeed";
		    autoRestoreSpeedItem.title = @"自动恢复默认倍速";
		    autoRestoreSpeedItem.detail = @"";
		    autoRestoreSpeedItem.type = 1000;
		    autoRestoreSpeedItem.svgIconImageName = @"ic_switch_outlined";
		    autoRestoreSpeedItem.cellType = 6;
		    autoRestoreSpeedItem.colorStyle = 0;
		    autoRestoreSpeedItem.isEnable = YES;
		    autoRestoreSpeedItem.isSwitchOn = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYAutoRestoreSpeed"];
		    autoRestoreSpeedItem.switchChangedBlock = ^{
		      BOOL newValue = !autoRestoreSpeedItem.isSwitchOn;
		      autoRestoreSpeedItem.isSwitchOn = newValue;
		      [[NSUserDefaults standardUserDefaults] setBool:newValue forKey:@"DYYYAutoRestoreSpeed"];
		      [[NSUserDefaults standardUserDefaults] synchronize];
		    };
		    [speedButtonItems addObject:autoRestoreSpeedItem];

		    AWESettingItemModel *showXItem = [[%c(AWESettingItemModel) alloc] init];
		    showXItem.identifier = @"DYYYSpeedButtonShowX";
		    showXItem.title = @"倍速按钮显示后缀";
		    showXItem.detail = @"";
		    showXItem.type = 1000;
		    showXItem.svgIconImageName = @"ic_text_outlined_20";
		    showXItem.cellType = 6;
		    showXItem.colorStyle = 0;
		    showXItem.isEnable = YES;
		    showXItem.isSwitchOn = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYSpeedButtonShowX"];
		    showXItem.switchChangedBlock = ^{
		      BOOL newValue = !showXItem.isSwitchOn;
		      showXItem.isSwitchOn = newValue;
		      [[NSUserDefaults standardUserDefaults] setBool:newValue forKey:@"DYYYSpeedButtonShowX"];
		      [[NSUserDefaults standardUserDefaults] synchronize];
		    };
		    [speedButtonItems addObject:showXItem];
		    // 添加按钮大小配置项
		    AWESettingItemModel *buttonSizeItem = [[%c(AWESettingItemModel) alloc] init];
		    buttonSizeItem.identifier = @"DYYYSpeedButtonSize";
		    buttonSizeItem.title = @"快捷倍速按钮大小";
		    // 获取当前的按钮大小，如果没有设置则默认为32
		    CGFloat currentButtonSize = [[NSUserDefaults standardUserDefaults] floatForKey:@"DYYYSpeedButtonSize"] ?: 32;
		    buttonSizeItem.detail = [NSString stringWithFormat:@"%.0f", currentButtonSize];
		    buttonSizeItem.type = 0;
		    buttonSizeItem.svgIconImageName = @"ic_zoomin_outlined_20";
		    buttonSizeItem.cellType = 26;
		    buttonSizeItem.colorStyle = 0;
		    buttonSizeItem.isEnable = YES;
		    buttonSizeItem.cellTappedBlock = ^{
		      NSString *currentValue = [NSString stringWithFormat:@"%.0f", currentButtonSize];

		      showTextInputAlert(
			  @"设置按钮大小", currentValue, @"请输入20-60之间的数值",
			  ^(NSString *text) {
			    NSInteger size = [text integerValue];

			    // 确保输入值在有效范围内
			    if (size >= 20 && size <= 60) {
				    [[NSUserDefaults standardUserDefaults] setFloat:size forKey:@"DYYYSpeedButtonSize"];
				    [[NSUserDefaults standardUserDefaults] synchronize];

				    // 更新UI显示
				    buttonSizeItem.detail = [NSString stringWithFormat:@"%.0f", (CGFloat)size];

				    // 刷新表格
				    UIViewController *topVC = topView();
				    if ([topVC isKindOfClass:%c(AWESettingBaseViewController)]) {
					    dispatch_async(dispatch_get_main_queue(), ^{
					      UITableView *tableView = nil;
					      for (UIView *subview in topVC.view.subviews) {
						      if ([subview isKindOfClass:[UITableView class]]) {
							      tableView = (UITableView *)subview;
							      break;
						      }
					      }

					      if (tableView) {
						      [tableView reloadData];
					      }
					    });
				    }
			    } else {
				    [DYYYManager showToast:@"请输入20-60之间的有效数值"];
			    }
			  },
			  nil);
		    };
		    [speedButtonItems addObject:buttonSizeItem];

		    [speedButtonItems addObject:speedSettingsItem];

		    // 一键清屏section
		    NSMutableArray<AWESettingItemModel *> *clearButtonItems = [NSMutableArray array];

		    // 清屏按钮
		    AWESettingItemModel *enableClearButton = [self
			createSettingItem:
			    @{@"identifier" : @"DYYYEnableFloatClearButton",
			      @"title" : @"一键清屏按钮",
			      @"detail" : @"",
			      @"cellType" : @6,
			      @"imageName" : @"ic_eyeslash_outlined_16"}];
		    [clearButtonItems addObject:enableClearButton];

		    // 添加清屏按钮大小配置项
		    AWESettingItemModel *clearButtonSizeItem = [[%c(AWESettingItemModel) alloc] init];
		    clearButtonSizeItem.identifier = @"DYYYEnableFloatClearButtonSize";
		    clearButtonSizeItem.title = @"快捷清屏按钮大小";
		    // 获取当前的按钮大小，如果没有设置则默认为40
		    CGFloat currentClearButtonSize = [[NSUserDefaults standardUserDefaults] floatForKey:@"DYYYEnableFloatClearButtonSize"] ?: 40;
		    clearButtonSizeItem.detail = [NSString stringWithFormat:@"%.0f", currentClearButtonSize];
		    clearButtonSizeItem.type = 0;
		    clearButtonSizeItem.svgIconImageName = @"ic_zoomin_outlined_20";
		    clearButtonSizeItem.cellType = 26;
		    clearButtonSizeItem.colorStyle = 0;
		    clearButtonSizeItem.isEnable = YES;
		    clearButtonSizeItem.cellTappedBlock = ^{
		      NSString *currentValue = [NSString stringWithFormat:@"%.0f", currentClearButtonSize];
		      showTextInputAlert(
			  @"设置清屏按钮大小", currentValue, @"请输入20-60之间的数值",
			  ^(NSString *text) {
			    NSInteger size = [text integerValue];
			    // 确保输入值在有效范围内
			    if (size >= 20 && size <= 60) {
				    [[NSUserDefaults standardUserDefaults] setFloat:size forKey:@"DYYYEnableFloatClearButtonSize"];
				    [[NSUserDefaults standardUserDefaults] synchronize];
				    // 更新UI显示
				    clearButtonSizeItem.detail = [NSString stringWithFormat:@"%.0f", (CGFloat)size];
				    // 刷新表格
				    UIViewController *topVC = topView();
				    if ([topVC isKindOfClass:%c(AWESettingBaseViewController)]) {
					    dispatch_async(dispatch_get_main_queue(), ^{
					      UITableView *tableView = nil;
					      for (UIView *subview in topVC.view.subviews) {
						      if ([subview isKindOfClass:[UITableView class]]) {
							      tableView = (UITableView *)subview;
							      break;
						      }
					      }
					      if (tableView) {
						      [tableView reloadData];
					      }
					    });
				    }
			    } else {
				    [DYYYManager showToast:@"请输入20-60之间的有效数值"];
			    }
			  },
			  nil);
		    };
		    [clearButtonItems addObject:clearButtonSizeItem];

		    // 添加清屏按钮自定义图标选项
		    AWESettingItemModel *clearButtonIcon = createIconCustomizationItem(@"DYYYClearButtonIcon", @"清屏按钮图标", @"ic_roaming_outlined", @"qingping.png");

		    [clearButtonItems addObject:clearButtonIcon];

		    // 获取清屏按钮的当前开关状态
		    BOOL isEnabled = getUserDefaults(@"DYYYEnableFloatClearButton");
		    // 更新清屏按钮大小和图标设置项的启用状态
		    clearButtonSizeItem.isEnable = isEnabled;
		    clearButtonIcon.isEnable = isEnabled;

		    // 创建并组织所有section
		    NSMutableArray *sections = [NSMutableArray array];
		    [sections addObject:createSection(@"快捷倍速", speedButtonItems)];
		    [sections addObject:createSection(@"一键清屏", clearButtonItems)];

		    // 创建并推入二级设置页面
		    UIViewController *rootVC = self.controllerDelegate;
		    AWESettingBaseViewController *subVC = createSubSettingsViewController(@"悬浮按钮", sections);
		    [rootVC.navigationController pushViewController:(UIViewController *)subVC animated:YES];
		  };
		  [mainItems addObject:floatButtonSettingItem];

		  // 创建备份设置分类（单独section）
		  AWESettingSectionModel *backupSection = [[%c(AWESettingSectionModel) alloc] init];
		  backupSection.sectionHeaderTitle = @"备份";
		  backupSection.sectionHeaderHeight = 40;
		  backupSection.type = 0;
		  NSMutableArray<AWESettingItemModel *> *backupItems = [NSMutableArray array];

		  AWESettingItemModel *backupItem = [[%c(AWESettingItemModel) alloc] init];
		  backupItem.identifier = @"DYYYBackupSettings";
		  backupItem.title = @"备份设置";
		  backupItem.detail = @"";
		  backupItem.type = 0;
		  backupItem.svgIconImageName = @"ic_memorycard_outlined_20";
		  backupItem.cellType = 26;
		  backupItem.colorStyle = 0;
		  backupItem.isEnable = YES;
		  backupItem.cellTappedBlock = ^{
		    // 获取所有以DYYY开头的NSUserDefaults键值
		    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
		    NSDictionary *allDefaults = [defaults dictionaryRepresentation];
		    NSMutableDictionary *dyyySettings = [NSMutableDictionary dictionary];

		    for (NSString *key in allDefaults.allKeys) {
			    if ([key hasPrefix:@"DYYY"]) {
				    dyyySettings[key] = [defaults objectForKey:key];
			    }
		    }

		    // 查找并添加图标文件
		    NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
		    NSString *dyyyFolderPath = [documentsPath stringByAppendingPathComponent:@"DYYY"];

		    NSArray *iconFileNames = @[ @"like_before.png", @"like_after.png", @"comment.png", @"unfavorite.png", @"favorite.png", @"share.png", @"qingping.png" ];

		    NSMutableDictionary *iconBase64Dict = [NSMutableDictionary dictionary];

		    for (NSString *iconFileName in iconFileNames) {
			    NSString *iconPath = [dyyyFolderPath stringByAppendingPathComponent:iconFileName];
			    if ([[NSFileManager defaultManager] fileExistsAtPath:iconPath]) {
				    // 读取图片数据并转换为Base64
				    NSData *imageData = [NSData dataWithContentsOfFile:iconPath];
				    if (imageData) {
					    NSString *base64String = [imageData base64EncodedStringWithOptions:0];
					    iconBase64Dict[iconFileName] = base64String;
				    }
			    }
		    }

		    // 将图标Base64数据添加到备份设置中
		    if (iconBase64Dict.count > 0) {
			    dyyySettings[@"DYYYIconsBase64"] = iconBase64Dict;
		    }

		    // 转换为JSON数据
		    NSError *error;
		    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dyyySettings options:NSJSONWritingPrettyPrinted error:&error];

		    if (error) {
			    [DYYYManager showToast:@"备份失败：无法序列化设置数据"];
			    return;
		    }

		    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
		    [formatter setDateFormat:@"yyyyMMdd_HHmmss"];
		    NSString *timestamp = [formatter stringFromDate:[NSDate date]];
		    NSString *backupFileName = [NSString stringWithFormat:@"DYYY_Backup_%@.json", timestamp];
		    NSString *tempDir = NSTemporaryDirectory();
		    NSString *tempFilePath = [tempDir stringByAppendingPathComponent:backupFileName];

		    BOOL success = [jsonData writeToFile:tempFilePath atomically:YES];

		    if (!success) {
			    [DYYYManager showToast:@"备份失败：无法创建临时文件"];
			    return;
		    }

		    // 创建文档选择器让用户选择保存位置
		    NSURL *tempFileURL = [NSURL fileURLWithPath:tempFilePath];
		    UIDocumentPickerViewController *documentPicker = [[UIDocumentPickerViewController alloc] initWithURLs:@[ tempFileURL ] inMode:UIDocumentPickerModeExportToService];

		    DYYYBackupPickerDelegate *pickerDelegate = [[DYYYBackupPickerDelegate alloc] init];
		    pickerDelegate.tempFilePath = tempFilePath; // 设置临时文件路径
		    pickerDelegate.completionBlock = ^(NSURL *url) {
		      // 备份成功
		      [DYYYManager showToast:@"备份成功"];
		    };

		    static char kDYYYBackupPickerDelegateKey;
		    documentPicker.delegate = pickerDelegate;
		    objc_setAssociatedObject(documentPicker, &kDYYYBackupPickerDelegateKey, pickerDelegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

		    // 显示文档选择器
		    UIViewController *topVC = topView();
		    [topVC presentViewController:documentPicker animated:YES completion:nil];
		  };
		  [backupItems addObject:backupItem];

		  // 添加恢复设置
		  AWESettingItemModel *restoreItem = [[%c(AWESettingItemModel) alloc] init];
		  restoreItem.identifier = @"DYYYRestoreSettings";
		  restoreItem.title = @"恢复设置";
		  restoreItem.detail = @"";
		  restoreItem.type = 0;
		  restoreItem.svgIconImageName = @"ic_phonearrowup_outlined_20";
		  restoreItem.cellType = 26;
		  restoreItem.colorStyle = 0;
		  restoreItem.isEnable = YES;
		  restoreItem.cellTappedBlock = ^{
		    UIDocumentPickerViewController *documentPicker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[ @"public.json", @"public.text" ]
															    inMode:UIDocumentPickerModeImport];
		    documentPicker.allowsMultipleSelection = NO;

		    // 设置委托
		    DYYYBackupPickerDelegate *pickerDelegate = [[DYYYBackupPickerDelegate alloc] init];
		    pickerDelegate.completionBlock = ^(NSURL *url) {
		      NSData *jsonData = [NSData dataWithContentsOfURL:url];

		      if (!jsonData) {
			      [DYYYManager showToast:@"无法读取备份文件"];
			      return;
		      }

		      NSError *jsonError;
		      NSDictionary *dyyySettings = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&jsonError];

		      if (jsonError || ![dyyySettings isKindOfClass:[NSDictionary class]]) {
			      [DYYYManager showToast:@"备份文件格式错误"];
			      return;
		      }

		      // 恢复图标文件
		      NSDictionary *iconBase64Dict = dyyySettings[@"DYYYIconsBase64"];
		      if (iconBase64Dict && [iconBase64Dict isKindOfClass:[NSDictionary class]]) {
			      NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
			      NSString *dyyyFolderPath = [documentsPath stringByAppendingPathComponent:@"DYYY"];

			      // 确保DYYY文件夹存在
			      if (![[NSFileManager defaultManager] fileExistsAtPath:dyyyFolderPath]) {
				      [[NSFileManager defaultManager] createDirectoryAtPath:dyyyFolderPath withIntermediateDirectories:YES attributes:nil error:nil];
			      }

			      // 从Base64还原图标文件
			      for (NSString *iconFileName in iconBase64Dict) {
				      NSString *base64String = iconBase64Dict[iconFileName];
				      if ([base64String isKindOfClass:[NSString class]]) {
					      NSData *imageData = [[NSData alloc] initWithBase64EncodedString:base64String options:0];
					      if (imageData) {
						      NSString *iconPath = [dyyyFolderPath stringByAppendingPathComponent:iconFileName];
						      [imageData writeToFile:iconPath atomically:YES];
					      }
				      }
			      }

			      NSMutableDictionary *cleanSettings = [dyyySettings mutableCopy];
			      [cleanSettings removeObjectForKey:@"DYYYIconsBase64"];
			      dyyySettings = cleanSettings;
		      }

		      // 恢复设置
		      NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
		      for (NSString *key in dyyySettings) {
			      [defaults setObject:dyyySettings[key] forKey:key];
		      }
		      [defaults synchronize];

		      [DYYYManager showToast:@"设置已恢复，请重启应用以应用所有更改"];

		      // 刷新设置表格
		      UIViewController *topVC = topView();
		      if ([topVC isKindOfClass:%c(AWESettingBaseViewController)]) {
			      dispatch_async(dispatch_get_main_queue(), ^{
				UITableView *tableView = nil;
				for (UIView *subview in topVC.view.subviews) {
					if ([subview isKindOfClass:[UITableView class]]) {
						tableView = (UITableView *)subview;
						break;
					}
				}

				if (tableView) {
					[tableView reloadData];
				}
			      });
		      }
		    };

		    static char kDYYYRestorePickerDelegateKey;
		    documentPicker.delegate = pickerDelegate;
		    objc_setAssociatedObject(documentPicker, &kDYYYRestorePickerDelegateKey, pickerDelegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

		    // 显示文档选择器
		    UIViewController *topVC = topView();
		    [topVC presentViewController:documentPicker animated:YES completion:nil];
		  };
		  [backupItems addObject:restoreItem];
		  backupSection.itemArray = backupItems;

		  // 创建关于分类（单独section）
		  AWESettingSectionModel *aboutSection = [[%c(AWESettingSectionModel) alloc] init];
		  aboutSection.sectionHeaderTitle = @"关于";
		  aboutSection.sectionHeaderHeight = 40;
		  aboutSection.type = 0;
		  NSMutableArray<AWESettingItemModel *> *aboutItems = [NSMutableArray array];

		  // 添加关于
		  AWESettingItemModel *aboutItem = [[%c(AWESettingItemModel) alloc] init];
		  aboutItem.identifier = @"DYYYAbout";
		  aboutItem.title = @"关于插件";
		  aboutItem.detail = @"v2.2-4";
		  aboutItem.type = 0;
		  aboutItem.iconImageName = @"awe-settings-icon-about";
		  aboutItem.cellType = 26;
		  aboutItem.colorStyle = 0;
		  aboutItem.isEnable = YES;
		  aboutItem.cellTappedBlock = ^{
		    showAboutDialog(@"关于DYYY",
				    @"版本: v2.2-4\n\n"
				    @"感谢使用DYYY\n\n"
				    @"感谢huami开源\n\n"
				    @"@维他入我心 基于DYYY二次开发\n\n"
				    @"感谢huami group中群友的支持赞助\n\n"
				    @"Telegram @huamidev\n\n"
				    @"Telegram @vita_app\n\n"
				    @"开源地址 huami1314/DYYY\n\n"
				    @"仓库地址 Wtrwx/DYYY\n\n",
				    nil);
		  };
		  [aboutItems addObject:aboutItem];

		  AWESettingItemModel *licenseItem = [[%c(AWESettingItemModel) alloc] init];
		  licenseItem.identifier = @"DYYYLicense";
		  licenseItem.title = @"开源协议";
		  licenseItem.detail = @"MIT License";
		  licenseItem.type = 0;
		  licenseItem.iconImageName = @"awe-settings-icon-opensource-notice";
		  licenseItem.cellType = 26;
		  licenseItem.colorStyle = 0;
		  licenseItem.isEnable = YES;
		  licenseItem.cellTappedBlock = ^{
		    showAboutDialog(@"MIT License",
				    @"Copyright (c) 2024 huami.\n\n"
				    @"Permission is hereby granted, free of charge, to any person obtaining a copy "
				    @"of this software and associated documentation files (the \"Software\"), to deal "
				    @"in the Software without restriction, including without limitation the rights "
				    @"to use, copy, modify, merge, publish, distribute, sublicense, and/or sell "
				    @"copies of the Software, and to permit persons to whom the Software is "
				    @"furnished to do so, subject to the following conditions:\n\n"
				    @"The above copyright notice and this permission notice shall be included in all "
				    @"copies or substantial portions of the Software.\n\n"
				    @"THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR "
				    @"IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, "
				    @"FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE "
				    @"AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER "
				    @"LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, "
				    @"OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE "
				    @"SOFTWARE.",
				    nil);
		  };
		  [aboutItems addObject:licenseItem];
		  mainSection.itemArray = mainItems;
		  aboutSection.itemArray = aboutItems;

		  viewModel.sectionDataArray = @[ mainSection, backupSection, aboutSection ];
		  objc_setAssociatedObject(settingsVC, kViewModelKey, viewModel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		  [rootVC.navigationController pushViewController:(UIViewController *)settingsVC animated:YES];
		};
		AWESettingSectionModel *newSection = [[%c(AWESettingSectionModel) alloc] init];
		newSection.itemArray = @[ dyyyItem ];
		newSection.type = 0;
		newSection.sectionHeaderHeight = 40;
		newSection.sectionHeaderTitle = @"DYYY";
		NSMutableArray *newSections = [NSMutableArray arrayWithArray:originalSections];
		[newSections insertObject:newSection atIndex:0];
		return newSections;
	}
	return originalSections;
}

%new
- (AWESettingItemModel *)createSettingItem:(NSDictionary *)dict {
	return [self createSettingItem:dict cellTapHandlers:nil];
}

%new
- (AWESettingItemModel *)createSettingItem:(NSDictionary *)dict cellTapHandlers:(NSMutableDictionary *)cellTapHandlers {
	AWESettingItemModel *item = [[%c(AWESettingItemModel) alloc] init];
	item.identifier = dict[@"identifier"];
	item.title = dict[@"title"];

	// 获取保存的实际值
	NSString *savedDetail = [[NSUserDefaults standardUserDefaults] objectForKey:item.identifier];
	NSString *placeholder = dict[@"detail"];
	item.detail = savedDetail ?: @"";

	item.type = 1000;
	item.svgIconImageName = dict[@"imageName"];
	item.cellType = [dict[@"cellType"] integerValue];
	item.colorStyle = 0;
	item.isEnable = YES;
	item.isSwitchOn = getUserDefaults(item.identifier);

	[self applyDependencyRulesForItem:item];
	if (item.cellType == 26 && cellTapHandlers != nil) {
		cellTapHandlers[item.identifier] = ^{
		  if (!item.isEnable)
			  return;

		  showTextInputAlert(
		      item.title, item.detail, placeholder,
		      ^(NSString *text) {
			setUserDefaults(text, item.identifier);
			item.detail = text;

			if ([item.identifier isEqualToString:@"DYYYInterfaceDownload"]) {
				[self updateDependentItemsForSetting:@"DYYYInterfaceDownload" value:text];
			}

			UIViewController *topVC = topView();
			if ([topVC isKindOfClass:%c(AWESettingBaseViewController)]) {
				dispatch_async(dispatch_get_main_queue(), ^{
				  UITableView *tableView = nil;
				  for (UIView *subview in topVC.view.subviews) {
					  if ([subview isKindOfClass:[UITableView class]]) {
						  tableView = (UITableView *)subview;
						  break;
					  }
				  }

				  if (tableView) {
					  [tableView reloadData];
				  }
				});
			}
		      },
		      nil);
		};
		item.cellTappedBlock = cellTapHandlers[item.identifier];
	} else if (item.cellType == 6) {
		__weak AWESettingItemModel *weakItem = item;
		item.switchChangedBlock = ^{
		  __strong AWESettingItemModel *strongItem = weakItem;
		  if (strongItem) {
			  if (!strongItem.isEnable)
				  return;
			  BOOL isSwitchOn = !strongItem.isSwitchOn;
			  strongItem.isSwitchOn = isSwitchOn;
			  setUserDefaults(@(isSwitchOn), strongItem.identifier);
			  [self handleConflictsAndDependenciesForSetting:strongItem.identifier isEnabled:isSwitchOn];
		  }
		};
	}

	return item;
}

%new
- (void)applyDependencyRulesForItem:(AWESettingItemModel *)item {
	// 处理依赖关系
	if ([item.identifier isEqualToString:@"DYYYdanmuColor"]) {
		// 弹幕颜色设置依赖于弹幕改色开关
		BOOL isEnabled = getUserDefaults(@"DYYYEnableDanmuColor");
		item.isEnable = isEnabled;
	} else if ([item.identifier isEqualToString:@"DYYYCommentBlurTransparent"]) {
		// 毛玻璃透明度依赖于评论区毛玻璃开关
		BOOL isEnabled = getUserDefaults(@"DYYYisEnableCommentBlur");
		item.isEnable = isEnabled;
	} else if ([item.identifier isEqualToString:@"DYYYShowAllVideoQuality"]) {
		// 清晰度选项依赖于接口解析URL是否设置
		NSString *interfaceUrl = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYInterfaceDownload"];
		item.isEnable = (interfaceUrl != nil && interfaceUrl.length > 0);
	} else if ([item.identifier isEqualToString:@"DYYYEnableDoubleOpenComment"]) {
		// 双击打开评论依赖于双击打开菜单未启用
		BOOL menuEnabled = getUserDefaults(@"DYYYEnableDoubleOpenAlertController");
		item.isEnable = !menuEnabled;
	} else if ([item.identifier isEqualToString:@"DYYYEnableDoubleOpenAlertController"]) {
		// 双击打开菜单依赖于双击打开评论未启用
		BOOL commentEnabled = getUserDefaults(@"DYYYEnableDoubleOpenComment");
		item.isEnable = !commentEnabled;
	} else if ([item.identifier isEqualToString:@"DYYYDoubleInterfaceDownload"]) {
		// 接口保存功能依赖于接口解析URL是否设置
		NSString *interfaceUrl = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYInterfaceDownload"];
		item.isEnable = (interfaceUrl != nil && interfaceUrl.length > 0);
	}
	// 新增依赖关系
	else if ([item.identifier isEqualToString:@"DYYYLabelColor"]) {
		// 属地标签颜色依赖于时间属地显示开关
		BOOL isEnabled = getUserDefaults(@"DYYYisEnableArea");
		item.isEnable = isEnabled;
	} else if ([item.identifier isEqualToString:@"DYYYScheduleStyle"] || [item.identifier isEqualToString:@"DYYYProgressLabelColor"] ||
		   [item.identifier isEqualToString:@"DYYYTimelineVerticalPosition"]) {
		// 进度时长相关设置依赖于显示进度时长开关
		BOOL isEnabled = getUserDefaults(@"DYYYisShowScheduleDisplay");
		item.isEnable = isEnabled;
	} else if ([item.identifier isEqualToString:@"DYYYNotificationCornerRadius"]) {
		// 通知角度依赖于通知开关
		BOOL isEnabled = getUserDefaults(@"DYYYEnableNotificationTransparency");
		item.isEnable = isEnabled;
	}
	// 添加悬浮按钮依赖关系
	else if ([item.identifier isEqualToString:@"DYYYAutoRestoreSpeed"] || [item.identifier isEqualToString:@"DYYYSpeedButtonShowX"] || [item.identifier isEqualToString:@"DYYYSpeedButtonSize"] ||
		 [item.identifier isEqualToString:@"DYYYSpeedSettings"]) {
		// 倍速设置相关选项依赖于快捷倍速按钮开关
		BOOL isEnabled = getUserDefaults(@"DYYYEnableFloatSpeedButton");
		item.isEnable = isEnabled;
	} else if ([item.identifier isEqualToString:@"DYYYClearButtonIcon"] || [item.identifier isEqualToString:@"DYYYEnableFloatClearButtonSize"]) {
		// 清屏按钮图标和大小设置依赖于清屏按钮开关
		BOOL isEnabled = getUserDefaults(@"DYYYEnableFloatClearButton");
		item.isEnable = isEnabled;
	}
}

%new
- (void)handleConflictsAndDependenciesForSetting:(NSString *)identifier isEnabled:(BOOL)isEnabled {
	UIViewController *topVC = topView();
	UITableView *tableView = nil;

	// 查找当前的表格视图
	if ([topVC isKindOfClass:%c(AWESettingBaseViewController)]) {
		for (UIView *subview in topVC.view.subviews) {
			if ([subview isKindOfClass:[UITableView class]]) {
				tableView = (UITableView *)subview;
				break;
			}
		}
	}

	// 处理冲突和依赖关系逻辑
	if ([identifier isEqualToString:@"DYYYEnableDanmuColor"]) {
		// 更新对应的弹幕颜色设置的启用状态
		[self updateDependentItemsForSetting:identifier value:@(isEnabled)];
	} else if ([identifier isEqualToString:@"DYYYisEnableCommentBlur"]) {
		// 更新对应的毛玻璃透明度设置的启用状态
		[self updateDependentItemsForSetting:identifier value:@(isEnabled)];
	} else if ([identifier isEqualToString:@"DYYYEnableDoubleOpenComment"]) {
		// 不论是开启还是关闭，都需要更新相关依赖项状态
		[self updateDependentItemsForSetting:identifier value:@(isEnabled)];

		if (isEnabled) {
			// 如果启用双击打开评论，禁用双击打开菜单
			setUserDefaults(@(NO), @"DYYYEnableDoubleOpenAlertController");
			[self updateDependentItemsForSetting:@"DYYYEnableDoubleOpenAlertController" value:@(NO)];
		}
	} else if ([identifier isEqualToString:@"DYYYEnableDoubleOpenAlertController"]) {
		// 不论是开启还是关闭，都需要更新相关依赖项状态
		[self updateDependentItemsForSetting:identifier value:@(isEnabled)];

		if (isEnabled) {
			// 如果启用双击打开菜单，禁用双击打开评论
			setUserDefaults(@(NO), @"DYYYEnableDoubleOpenComment");
			[self updateDependentItemsForSetting:@"DYYYEnableDoubleOpenComment" value:@(NO)];
		}
	}
	// 新增依赖处理
	else if ([identifier isEqualToString:@"DYYYisEnableArea"]) {
		// 更新对应的属地标签颜色设置的启用状态
		[self updateDependentItemsForSetting:identifier value:@(isEnabled)];
	} else if ([identifier isEqualToString:@"DYYYisShowScheduleDisplay"]) {
		// 更新对应的进度时长相关设置的启用状态
		[self updateDependentItemsForSetting:identifier value:@(isEnabled)];
	}
	// 添加悬浮按钮依赖处理
	else if ([identifier isEqualToString:@"DYYYEnableFloatSpeedButton"]) {
		// 更新对应的倍速设置相关选项的启用状态
		[self updateDependentItemsForSetting:identifier value:@(isEnabled)];
	} else if ([identifier isEqualToString:@"DYYYEnableFloatClearButton"]) {
		// 更新对应的清屏按钮图标的启用状态
		[self updateDependentItemsForSetting:identifier value:@(isEnabled)];
	}

	// 刷新表格视图以反映状态变化
	if (tableView) {
		dispatch_async(dispatch_get_main_queue(), ^{
		  [tableView reloadData];
		});
	}
}

%new
- (void)updateDependentItemsForSetting:(NSString *)identifier value:(id)value {
	// 寻找依赖于指定设置项的其他设置项并更新其状态
	UIViewController *topVC = topView();
	if (![topVC isKindOfClass:%c(AWESettingBaseViewController)])
		return;

	AWESettingBaseViewController *settingsVC = (AWESettingBaseViewController *)topVC;
	AWESettingsViewModel *viewModel = (AWESettingsViewModel *)[settingsVC viewModel];
	if (!viewModel || ![viewModel respondsToSelector:@selector(sectionDataArray)])
		return;

	NSArray *sectionDataArray = [viewModel sectionDataArray];
	for (AWESettingSectionModel *section in sectionDataArray) {
		if (![section respondsToSelector:@selector(itemArray)])
			continue;

		NSArray *itemArray = section.itemArray;
		for (id itemObj in itemArray) {
			if (![itemObj isKindOfClass:%c(AWESettingItemModel)])
				continue;

			AWESettingItemModel *item = (AWESettingItemModel *)itemObj;

			// 更新依赖项状态
			if ([identifier isEqualToString:@"DYYYEnableDanmuColor"] && [item.identifier isEqualToString:@"DYYYdanmuColor"]) {
				item.isEnable = [value boolValue];
			} else if ([identifier isEqualToString:@"DYYYisEnableCommentBlur"] && [item.identifier isEqualToString:@"DYYYCommentBlurTransparent"]) {
				item.isEnable = [value boolValue];
			} else if ([identifier isEqualToString:@"DYYYInterfaceDownload"]) {
				if ([item.identifier isEqualToString:@"DYYYShowAllVideoQuality"] || [item.identifier isEqualToString:@"DYYYDoubleInterfaceDownload"]) {
					// 对于字符串值，检查是否有内容
					if ([value isKindOfClass:[NSString class]]) {
						NSString *strValue = (NSString *)value;
						item.isEnable = (strValue.length > 0);
					}
				}
			} else if ([identifier isEqualToString:@"DYYYEnableDoubleOpenComment"]) {
				if ([item.identifier isEqualToString:@"DYYYEnableDoubleOpenAlertController"]) {
					// 如果"双击打开评论"被禁用，则启用"双击打开菜单"选项
					item.isEnable = ![value boolValue];
				}
			} else if ([identifier isEqualToString:@"DYYYEnableDoubleOpenAlertController"]) {
				if ([item.identifier isEqualToString:@"DYYYEnableDoubleOpenComment"]) {
					// 如果"双击打开菜单"被禁用，则启用"双击打开评论"选项
					item.isEnable = ![value boolValue];
				}
			}
			// 新增更新逻辑
			else if ([identifier isEqualToString:@"DYYYisEnableArea"] && [item.identifier isEqualToString:@"DYYYLabelColor"]) {
				item.isEnable = [value boolValue];
			} else if ([identifier isEqualToString:@"DYYYisShowScheduleDisplay"] &&
				   ([item.identifier isEqualToString:@"DYYYScheduleStyle"] || [item.identifier isEqualToString:@"DYYYProgressLabelColor"] ||
				    [item.identifier isEqualToString:@"DYYYTimelineVerticalPosition"])) {
				item.isEnable = [value boolValue];
			}
			// 添加悬浮按钮相关更新逻辑
			else if ([identifier isEqualToString:@"DYYYEnableFloatSpeedButton"] &&
				 ([item.identifier isEqualToString:@"DYYYAutoRestoreSpeed"] || [item.identifier isEqualToString:@"DYYYSpeedButtonShowX"] ||
				  [item.identifier isEqualToString:@"DYYYSpeedButtonSize"] || [item.identifier isEqualToString:@"DYYYSpeedSettings"])) {
				item.isEnable = [value boolValue];
			} else if ([identifier isEqualToString:@"DYYYEnableFloatClearButton"] &&
				   ([item.identifier isEqualToString:@"DYYYClearButtonIcon"] || [item.identifier isEqualToString:@"DYYYEnableFloatClearButtonSize"])) {
				item.isEnable = [value boolValue];
			}
		}
	}
}
%end
