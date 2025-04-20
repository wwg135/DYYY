#import "DYYYSettingViewController.h"
#import <Photos/Photos.h>

typedef NS_ENUM(NSInteger, DYYYSettingItemType) {
    DYYYSettingItemTypeSwitch,
    DYYYSettingItemTypeTextField,
    DYYYSettingItemTypeSpeedPicker,
    DYYYSettingItemTypeColorPicker
};

@interface DYYYSettingItem : NSObject

@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *key;
@property (nonatomic, assign) DYYYSettingItemType type;
@property (nonatomic, copy, nullable) NSString *placeholder;

+ (instancetype)itemWithTitle:(NSString *)title key:(NSString *)key type:(DYYYSettingItemType)type;
+ (instancetype)itemWithTitle:(NSString *)title key:(NSString *)key type:(DYYYSettingItemType)type placeholder:(nullable NSString *)placeholder;

@end

@implementation DYYYSettingItem

+ (instancetype)itemWithTitle:(NSString *)title key:(NSString *)key type:(DYYYSettingItemType)type {
    return [self itemWithTitle:title key:key type:type placeholder:nil];
}

+ (instancetype)itemWithTitle:(NSString *)title key:(NSString *)key type:(DYYYSettingItemType)type placeholder:(nullable NSString *)placeholder {
    DYYYSettingItem *item = [[DYYYSettingItem alloc] init];
    item.title = title;
    item.key = key;
    item.type = type;
    item.placeholder = placeholder;
    return item;
}

@end

@interface DYYYSettingViewController () <UITableViewDelegate, UITableViewDataSource, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UISearchBarDelegate>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<NSArray<DYYYSettingItem *> *> *settingSections;
@property (nonatomic, strong) NSArray<NSArray<DYYYSettingItem *> *> *filteredSections;
@property (nonatomic, strong) NSMutableArray<NSString *> *filteredSectionTitles;
@property (nonatomic, strong) UILabel *footerLabel;
@property (nonatomic, strong) NSMutableArray<NSString *> *sectionTitles;
@property (nonatomic, strong) NSMutableSet *expandedSections;
@property (nonatomic, strong) UIVisualEffectView *blurEffectView;
@property (nonatomic, strong) UIView *backgroundColorView;
@property (nonatomic, strong) UIImageView *avatarImageView;
@property (nonatomic, strong) UIView *avatarContainerView;
@property (nonatomic, strong) UILabel *avatarTapLabel;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, assign) BOOL isSearching;
@property (nonatomic, assign) BOOL isKVOAdded;

@end

@implementation DYYYSettingViewController

#pragma mark - View Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    
    NSLog(@"DYYYSettingViewController viewDidLoad");
    self.title = @"DYYY设置";
    self.expandedSections = [NSMutableSet set];
    self.isSearching = NO;
    self.isKVOAdded = NO;
    
    UIBarButtonItem *backItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"chevron.left"]
                                                                 style:UIBarButtonItemStylePlain
                                                                target:self
                                                                action:@selector(backButtonTapped:)];
    self.navigationItem.leftBarButtonItem = backItem;
    
    [self setupAppearance];
    [self setupBackgroundColorView];
    [self setupBlurEffect];
    [self setupAvatarView];
    [self setupSearchBar];
    [self setupTableView];
    [self setupSettingItems];
    [self setupSectionTitles];
    [self setupFooterLabel];
}

- (void)backButtonTapped:(id)sender {
    NSLog(@"DYYYSettingViewController backButtonTapped");
    if (self.navigationController && self.navigationController.viewControllers.count > 1) {
        [self.navigationController popViewControllerAnimated:YES];
    } else {
        NSLog(@"DYYYSettingViewController: No navigation controller, dismissing");
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    NSLog(@"DYYYSettingViewController viewWillDisappear");
    
    self.isSearching = NO;
    self.searchBar.text = @"";
    self.filteredSections = nil;
    self.filteredSectionTitles = nil;
    [self.expandedSections removeAllObjects];
    
    if (self.tableView && [self.tableView numberOfSections] > 0) {
        @try {
            [self.tableView reloadData];
            NSLog(@"DYYYSettingViewController tableView reloaded");
        } @catch (NSException *exception) {
            NSLog(@"DYYYSettingViewController reloadData failed: %@", exception);
        }
    }
    
    if (self.isKVOAdded && self.tableView) {
        @try {
            [self.tableView removeObserver:self forKeyPath:@"contentOffset"];
            self.isKVOAdded = NO;
            NSLog(@"DYYYSettingViewController KVO removed in viewWillDisappear");
        } @catch (NSException *exception) {
            NSLog(@"DYYYSettingViewController KVO removal failed: %@", exception);
        }
    }
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    NSLog(@"DYYYSettingViewController viewDidDisappear");
    
    if (self.isKVOAdded && self.tableView) {
        @try {
            [self.tableView removeObserver:self forKeyPath:@"contentOffset"];
            self.isKVOAdded = NO;
            NSLog(@"DYYYSettingViewController KVO removed in viewDidDisappear");
        } @catch (NSException *exception) {
            NSLog(@"DYYYSettingViewController KVO removal failed in viewDidDisappear: %@", exception);
        }
    }
}

#pragma mark - Setup Methods

- (void)setupAppearance {
    if (self.navigationController) {
        self.navigationController.navigationBar.prefersLargeTitles = YES;
        self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
        self.navigationController.navigationBar.translucent = YES;
        self.navigationController.navigationBar.backgroundColor = [UIColor clearColor];
        self.navigationController.navigationBar.tintColor = [UIColor systemBlueColor];
    }
}

- (void)setupBackgroundColorView {
    self.backgroundColorView = [[UIView alloc] initWithFrame:self.view.bounds];
    self.backgroundColorView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    NSData *colorData = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYBackgroundColor"];
    UIColor *savedColor = colorData ? [NSKeyedUnarchiver unarchiveObjectWithData:colorData] : [UIColor systemBackgroundColor];
    self.backgroundColorView.backgroundColor = savedColor;
    [self.view insertSubview:self.backgroundColorView atIndex:0];
}

- (void)setupBlurEffect {
    UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
    self.blurEffectView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    self.blurEffectView.frame = self.view.bounds;
    self.blurEffectView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.blurEffectView.alpha = 0.5;
    [self.view insertSubview:self.blurEffectView aboveSubview:self.backgroundColorView];
    
    if (self.tableView) {
        @try {
            [self.tableView addObserver:self forKeyPath:@"contentOffset" options:NSKeyValueObservingOptionNew context:nil];
            self.isKVOAdded = YES;
            NSLog(@"DYYYSettingViewController KVO added");
        } @catch (NSException *exception) {
            NSLog(@"DYYYSettingViewController KVO addition failed: %@", exception);
        }
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ([keyPath isEqualToString:@"contentOffset"] && object == self.tableView) {
        CGFloat offset = self.tableView.contentOffset.y;
        self.blurEffectView.alpha = MIN(1.0, MAX(0.5, offset / 200.0));
    }
}

- (void)setupAvatarView {
    self.avatarContainerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 160)];
    self.avatarContainerView.backgroundColor = [UIColor clearColor];
    
    self.avatarImageView = [[UIImageView alloc] initWithFrame:CGRectMake((self.view.bounds.size.width - 100) / 2, 20, 100, 100)];
    self.avatarImageView.layer.cornerRadius = 50;
    self.avatarImageView.clipsToBounds = YES;
    self.avatarImageView.contentMode = UIViewContentModeScaleAspectFill;
    self.avatarImageView.backgroundColor = [UIColor systemGray4Color];
    
    NSString *avatarPath = [self avatarImagePath];
    if ([[NSFileManager defaultManager] fileExistsAtPath:avatarPath]) {
        self.avatarImageView.image = [UIImage imageWithContentsOfFile:avatarPath];
    } else {
        self.avatarImageView.image = [UIImage systemImageNamed:@"person.circle.fill"];
        self.avatarImageView.tintColor = [UIColor systemGrayColor];
    }
    
    [self.avatarContainerView addSubview:self.avatarImageView];
    
    self.avatarTapLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 120, self.view.bounds.size.width, 30)];
    NSString *customTapText = [[NSUserDefaults standardUserDefaults] stringForKey:@"DYYYAvatarTapText"];
    self.avatarTapLabel.text = customTapText.length > 0 ? customTapText : @"更改头像";
    self.avatarTapLabel.textAlignment = NSTextAlignmentCenter;
    self.avatarTapLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle3];
    self.avatarTapLabel.textColor = [UIColor systemBlueColor];
    [self.avatarContainerView addSubview:self.avatarTapLabel];
    
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(avatarTapped:)];
    self.avatarImageView.userInteractionEnabled = YES;
    [self.avatarImageView addGestureRecognizer:tapGesture];
}

- (void)setupSearchBar {
    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 44)];
    self.searchBar.delegate = self;
    self.searchBar.placeholder = @"搜索设置";
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.searchBar.backgroundColor = [UIColor clearColor];
}

- (void)setupTableView {
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    self.tableView.sectionHeaderTopPadding = 20;
    self.tableView.tableHeaderView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 204)];
    [self.tableView.tableHeaderView addSubview:self.avatarContainerView];
    [self.tableView.tableHeaderView addSubview:self.searchBar];
    self.searchBar.frame = CGRectMake(0, 160, self.view.bounds.size.width, 44);
    [self.view addSubview:self.tableView];
    
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    [self.tableView addGestureRecognizer:longPress];
}

- (void)setupSettingItems {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSArray<NSArray<DYYYSettingItem *> *> *sections = @[
            @[
                [DYYYSettingItem itemWithTitle:@"启用弹幕改色" key:@"DYYYEnableDanmuColor" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"自定弹幕颜色" key:@"DYYYdanmuColor" type:DYYYSettingItemTypeTextField placeholder:@"十六进制"],
                [DYYYSettingItem itemWithTitle:@"显示进度时长" key:@"DYYYisShowScheduleDisplay" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"进度纵轴位置" key:@"DYYYTimelineVerticalPosition" type:DYYYSettingItemTypeTextField placeholder:@"-12.5"],
                [DYYYSettingItem itemWithTitle:@"进度标签颜色" key:@"DYYYProgressLabelColor" type:DYYYSettingItemTypeTextField placeholder:@"十六进制"],
                [DYYYSettingItem itemWithTitle:@"隐藏视频进度" key:@"DYYYHideVideoProgress" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"启用自动播放" key:@"DYYYisEnableAutoPlay" type:DYYYSettingItemTypeSwitch],
                
                [DYYYSettingItem itemWithTitle:@"推荐视频时限" key:@"DYYYfiltertimelimit" type:DYYYSettingItemTypeTextField placeholder:@"填0关闭，单位为天"],
                [DYYYSettingItem itemWithTitle:@"启用首页净化" key:@"DYYYisEnablePure" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"启用首页全屏" key:@"DYYYisEnableFullScreen" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"屏蔽检测更新" key:@"DYYYNoUpdates" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"去青少年弹窗" key:@"DYYYHideteenmode" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"评论区毛玻璃" key:@"DYYYisEnableCommentBlur" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"通知玻璃效果" key:@"DYYYEnableNotificationTransparency" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"毛玻璃透明度" key:@"DYYYCommentBlurTransparent" type:DYYYSettingItemTypeTextField placeholder:@"0-1小数"],
                [DYYYSettingItem itemWithTitle:@"通知圆角半径" key:@"DYYYNotificationCornerRadius" type:DYYYSettingItemTypeTextField placeholder:@"默认12"],
                [DYYYSettingItem itemWithTitle:@"时间属地显示" key:@"DYYYisEnableArea" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"时间标签颜色" key:@"DYYYLabelColor" type:DYYYSettingItemTypeTextField placeholder:@"十六进制"],
                [DYYYSettingItem itemWithTitle:@"隐藏系统顶栏" key:@"DYYYisHideStatusbar" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"关注二次确认" key:@"DYYYfollowTips" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"收藏二次确认" key:@"DYYYcollectTips" type:DYYYSettingItemTypeSwitch]
            ],
            @[
                [DYYYSettingItem itemWithTitle:@"设置顶栏透明" key:@"DYYYtopbartransparent" type:DYYYSettingItemTypeTextField placeholder:@"0-1小数"],
                [DYYYSettingItem itemWithTitle:@"设置全局透明" key:@"DYYYGlobalTransparency" type:DYYYSettingItemTypeTextField placeholder:@"0-1小数"],
                [DYYYSettingItem itemWithTitle:@"首页头像透明" key:@"DYYYAvatarViewTransparency" type:DYYYSettingItemTypeTextField placeholder:@"0-1小数"],
                [DYYYSettingItem itemWithTitle:@"设置默认倍速" key:@"DYYYDefaultSpeed" type:DYYYSettingItemTypeSpeedPicker],
                [DYYYSettingItem itemWithTitle:@"右侧栏缩放度" key:@"DYYYElementScale" type:DYYYSettingItemTypeTextField placeholder:@"不填默认"],
                [DYYYSettingItem itemWithTitle:@"昵称文案缩放" key:@"DYYYNicknameScale" type:DYYYSettingItemTypeTextField placeholder:@"不填默认"],
                [DYYYSettingItem itemWithTitle:@"昵称下移距离" key:@"DYYYNicknameVerticalOffset" type:DYYYSettingItemTypeTextField placeholder:@"不填默认"],
                [DYYYSettingItem itemWithTitle:@"文案下移距离" key:@"DYYYDescriptionVerticalOffset" type:DYYYSettingItemTypeTextField placeholder:@"不填默认"],
                [DYYYSettingItem itemWithTitle:@"属地下移距离" key:@"DYYYIPLabelVerticalOffset" type:DYYYSettingItemTypeTextField placeholder:@"不填默认"],
                [DYYYSettingItem itemWithTitle:@"设置首页标题" key:@"DYYYIndexTitle" type:DYYYSettingItemTypeTextField placeholder:@"不填默认"],
                [DYYYSettingItem itemWithTitle:@"设置朋友标题" key:@"DYYYFriendsTitle" type:DYYYSettingItemTypeTextField placeholder:@"不填默认"],
                [DYYYSettingItem itemWithTitle:@"设置消息标题" key:@"DYYYMsgTitle" type:DYYYSettingItemTypeTextField placeholder:@"不填默认"],
                [DYYYSettingItem itemWithTitle:@"设置我的标题" key:@"DYYYSelfTitle" type:DYYYSettingItemTypeTextField placeholder:@"不填默认"]
            ],
            @[
                [DYYYSettingItem itemWithTitle:@"隐藏全屏观看" key:@"DYYYisHiddenEntry" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏底栏商城" key:@"DYYYHideShopButton" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏底栏消息" key:@"DYYYHideMessageButton" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏底栏朋友" key:@"DYYYHideFriendsButton" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏底栏加号" key:@"DYYYisHiddenJia" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏底栏红点" key:@"DYYYisHiddenBottomDot" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏底栏背景" key:@"DYYYisHiddenBottomBg" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏侧栏红点" key:@"DYYYisHiddenSidebarDot" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏发作品框" key:@"DYYYHidePostView" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏头像加号" key:@"DYYYHideLOTAnimationView" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏点赞数值" key:@"DYYYHideLikeLabel" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏评论数值" key:@"DYYYHideCommentLabel" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏收藏数值" key:@"DYYYHideCollectLabel" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏分享数值" key:@"DYYYHideShareLabel" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏点赞按钮" key:@"DYYYHideLikeButton" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏评论按钮" key:@"DYYYHideCommentButton" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏收藏按钮" key:@"DYYYHideCollectButton" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏头像按钮" key:@"DYYYHideAvatarButton" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏音乐按钮" key:@"DYYYHideMusicButton" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏分享按钮" key:@"DYYYHideShareButton" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏视频定位" key:@"DYYYHideLocation" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏右上搜索" key:@"DYYYHideDiscover" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏相关搜索" key:@"DYYYHideInteractionSearch" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏进入直播" key:@"DYYYHideEnterLive" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏评论视图" key:@"DYYYHideCommentViews" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏通知提示" key:@"DYYYHidePushBanner" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏头像列表" key:@"DYYYisHiddenAvatarList" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏头像气泡" key:@"DYYYisHiddenAvatarBubble" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏左侧边栏" key:@"DYYYisHiddenLeftSideBar" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏吃喝玩乐" key:@"DYYYHideNearbyCapsuleView" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏弹幕按钮" key:@"DYYYHideDanmuButton" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏取消静音" key:@"DYYYHideCancelMute" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏去汽水听" key:@"DYYYHideQuqishuiting" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏共创头像" key:@"DYYYHideGongChuang" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏热点提示" key:@"DYYYHideHotspot" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏推荐提示" key:@"DYYYHideRecommendTips" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏分享提示" key:@"DYYYHideShareContentView" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏作者声明" key:@"DYYYHideAntiAddictedNotice" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏底部相关" key:@"DYYYHideBottomRelated" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏拍摄同款" key:@"DYYYHideFeedAnchorContainer" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏挑战贴纸" key:@"DYYYHideChallengeStickers" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏校园提示" key:@"DYYYHideTemplateTags" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏作者店铺" key:@"DYYYHideHisShop" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏关注直播" key:@"DYYYHideConcernCapsuleView" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏顶栏横线" key:@"DYYYHidentopbarprompt" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏视频合集" key:@"DYYYHideTemplateVideo" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏短剧合集" key:@"DYYYHideTemplatePlaylet" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏动图标签" key:@"DYYYHideLiveGIF" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏笔记标签" key:@"DYYYHideItemTag" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏底部话题" key:@"DYYYHideTemplateGroup" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏相机定位" key:@"DYYYHideCameraLocation" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏视频滑条" key:@"DYYYHideStoryProgressSlide" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏图片滑条" key:@"DYYYHideDotsIndicator" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏分享私信" key:@"DYYYHidePrivateMessages" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏昵称右侧" key:@"DYYYHideRightLable" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏群聊商店" key:@"DYYYHideGroupShop" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏直播胶囊" key:@"DYYYHideLiveCapsuleView" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏关注顶端" key:@"DYYYHidenLiveView" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏同城顶端" key:@"DYYYHideMenuView" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏群直播中" key:@"DYYYGroupLiving" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏群工具栏" key:@"DYYYHideGroupInputActionBar" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏直播广场" key:@"DYYYHideLivePlayground" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏礼物展馆" key:@"DYYYHideGiftPavilion" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏顶栏红点" key:@"DYYYHideTopBarBadge" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏退出清屏" key:@"DYYYHideLiveRoomClear" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏投屏按钮" key:@"DYYYHideLiveRoomMirroring" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏直播发现" key:@"DYYYHideLiveDiscovery" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏直播点歌" key:@"DYYYHideKTVSongIndicator" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"隐藏流量提醒" key:@"DYYYHideCellularAlert" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"聊天评论透明" key:@"DYYYHideChatCommentBg" type:DYYYSettingItemTypeSwitch]
            ],
            @[
                [DYYYSettingItem itemWithTitle:@"移除推荐" key:@"DYYYHideHotContainer" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"移除关注" key:@"DYYYHideFollow" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"移除精选" key:@"DYYYHideMediumVideo" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"移除商城" key:@"DYYYHideMall" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"移除朋友" key:@"DYYYHideFriend" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"移除同城" key:@"DYYYHideNearby" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"移除团购" key:@"DYYYHideGroupon" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"移除直播" key:@"DYYYHideTabLive" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"移除热点" key:@"DYYYHidePadHot" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"移除经验" key:@"DYYYHideHangout" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"移除短剧" key:@"DYYYHidePlaylet" type:DYYYSettingItemTypeSwitch]
            ],
           @[ 

                [DYYYSettingItem itemWithTitle:@"长按面板过滤标题" key:@"DYYYLongPressFilterTitle" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"长按面板过滤用户" key:@"DYYYLongPressFilterUser" type:DYYYSettingItemTypeSwitch],

                [DYYYSettingItem itemWithTitle:@"推荐过滤直播" key:@"DYYYisSkipLive" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"推荐过滤热点" key:@"DYYYisSkipHotSpot" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"推荐过滤低赞" key:@"DYYYfilterLowLikes" type:DYYYSettingItemTypeTextField placeholder:@"填0关闭"],
                [DYYYSettingItem itemWithTitle:@"推荐过滤文案" key:@"DYYYfilterKeywords" type:DYYYSettingItemTypeTextField placeholder:@"不填关闭"]          
                ],
                @[
                [DYYYSettingItem itemWithTitle:@"启用新版玻璃面板" key:@"DYYYisEnableModern" type:DYYYSettingItemTypeSwitch],
              
                [DYYYSettingItem itemWithTitle:@"启用保存他人头像" key:@"DYYYEnableSaveAvatar" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"禁用点击首页刷新" key:@"DYYYDisableHomeRefresh" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"禁用双击视频点赞" key:@"DYYYDouble" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"评论区-双击触发" key:@"DYYYEnableDoubleOpenComment" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"评论区-长按复制文本" key:@"DYYYEnableCommentCopyText" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"长按面板复制功能" key:@"DYYYCopyText" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"评论区-保存动态图" key:@"DYYYCommentLivePhotoNoWaterMark" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"评论区-保存图片" key:@"DYYYCommentNoWaterMark" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"评论区-保存表情包" key:@"DYYYInterfaceDownload" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"视频-时间属地显示" key:@"DYYYisEnableArea" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"属地前缀" key:@"DYYYLocationPrefix" type:DYYYSettingItemTypeTextField placeholder:@"IP:"],
                [DYYYSettingItem itemWithTitle:@"长按视频-触发下载功能" key:@"DYYYLongPressDownload" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"屏蔽广告" key:@"DYYYNoAds" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"头像-自定义文本" key:@"DYYYAvatarTapText" type:DYYYSettingItemTypeTextField placeholder:@"输入提示文本"],
                [DYYYSettingItem itemWithTitle:@"背景颜色" key:@"DYYYBackgroundColor" type:DYYYSettingItemTypeColorPicker],
                [DYYYSettingItem itemWithTitle:@"启用快捷倍速按钮" key:@"DYYYEnableFloatSpeedButton" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"快捷倍速数值设置" key:@"DYYYSpeedSettings" type:DYYYSettingItemTypeTextField placeholder:@"逗号分隔"],
                [DYYYSettingItem itemWithTitle:@"自动恢复默认倍速" key:@"DYYYAutoRestoreSpeed" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"倍速按钮显示后缀" key:@"DYYYSpeedButtonShowX" type:DYYYSettingItemTypeSwitch],
                [DYYYSettingItem itemWithTitle:@"快捷倍速按钮大小" key:@"DYYYSpeedButtonSize" type:DYYYSettingItemTypeTextField placeholder:@"默认32"],
                [DYYYSettingItem itemWithTitle:@"启用一键清屏按钮" key:@"DYYYEnableFloatClearButton" type:DYYYSettingItemTypeSwitch],
                
                [DYYYSettingItem itemWithTitle:@"快捷清屏按钮大小" key:@"DYYYEnableFloatClearButtonSize" type:DYYYSettingItemTypeTextField placeholder:@"默认40"]
            ]
        ];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.settingSections = sections;
            self.filteredSections = sections;
            self.filteredSectionTitles = [self.sectionTitles mutableCopy];
            if (self.tableView) {
                [self.tableView reloadData];
            }
        });
    });
}

- (void)setupSectionTitles {
    self.sectionTitles = [@[@"基本设置", @"界面设置", @"隐藏设置", @"顶栏移除", @"过滤功能", @"增强设置"] mutableCopy];
    self.filteredSectionTitles = [self.sectionTitles mutableCopy];
}

- (void)setupFooterLabel {
    self.footerLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 50)];
    self.footerLabel.text = @"开发者:花米\n 插件版本:2.4.4";
    self.footerLabel.textAlignment = NSTextAlignmentCenter;
    self.footerLabel.font = [UIFont systemFontOfSize:14];
    self.footerLabel.textColor = [UIColor secondaryLabelColor];
    self.footerLabel.numberOfLines = 2;
// 动态计算宽度（适配 Safe Area）
    CGFloat width = self.view.safeAreaLayoutGuide.layoutFrame.size.width;
    self.footerLabel.frame = CGRectMake(0, 0, width, 50);
    self.tableView.tableFooterView = self.footerLabel;
}

#pragma mark - Avatar Handling

- (void)avatarTapped:(UITapGestureRecognizer *)gesture {
    [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (status == PHAuthorizationStatusAuthorized) {
                UIImagePickerController *picker = [[UIImagePickerController alloc] init];
                picker.delegate = self;
                picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
                picker.allowsEditing = YES;
                [self presentViewController:picker animated:YES completion:nil];
            } else {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"无法访问相册"
                                                                               message:@"请在设置中允许访问相册"
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
            }
        });
    }];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey, id> *)info {
    UIImage *selectedImage = info[UIImagePickerControllerEditedImage] ?: info[UIImagePickerControllerOriginalImage];
    if (selectedImage) {
        self.avatarImageView.image = selectedImage;
        
        NSString *avatarPath = [self avatarImagePath];
        NSData *imageData = UIImageJPEGRepresentation(selectedImage, 0.8);
        [imageData writeToFile:avatarPath atomically:YES];
    }
    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (NSString *)avatarImagePath {
    NSString *documentsPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    return [documentsPath stringByAppendingPathComponent:@"DYYYAvatar.jpg"];
}

#pragma mark - Color Picker

- (void)showColorPicker {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"选择背景颜色"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    NSArray<NSDictionary *> *colors = @[
        @{@"name": @"粉红", @"color": [UIColor systemRedColor]},
        @{@"name": @"蓝色", @"color": [UIColor systemBlueColor]},
        @{@"name": @"绿色", @"color": [UIColor systemGreenColor]},
        @{@"name": @"黄色", @"color": [UIColor systemYellowColor]},
        @{@"name": @"紫色", @"color": [UIColor systemPurpleColor]},
        @{@"name": @"橙色", @"color": [UIColor systemOrangeColor]},
        @{@"name": @"粉色", @"color": [UIColor systemPinkColor]},
        @{@"name": @"灰色", @"color": [UIColor systemGrayColor]},
        @{@"name": @"白色", @"color": [UIColor whiteColor]},
        @{@"name": @"黑色", @"color": [UIColor blackColor]}
    ];
    
    for (NSDictionary *colorInfo in colors) {
        NSString *name = colorInfo[@"name"];
        UIColor *color = colorInfo[@"color"];
        UIAlertAction *action = [UIAlertAction actionWithTitle:name style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            self.backgroundColorView.backgroundColor = color;
            NSData *colorData = [NSKeyedArchiver archivedDataWithRootObject:color];
            [[NSUserDefaults standardUserDefaults] setObject:colorData forKey:@"DYYYBackgroundColor"];
            [[NSUserDefaults standardUserDefaults] synchronize];
            
            for (NSInteger section = 0; section < self.settingSections.count; section++) {
                NSArray *items = self.settingSections[section];
                for (NSInteger row = 0; row < items.count; row++) {
                    DYYYSettingItem *item = items[row];
                    if (item.type == DYYYSettingItemTypeColorPicker) {
                        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:section];
                        if (self.tableView) {
                            [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
                        }
                        break;
                    }
                }
            }
        }];
        UIImage *colorImage = [self imageWithColor:color size:CGSizeMake(20, 20)];
        [action setValue:colorImage forKey:@"image"];
        [alert addAction:action];
    }
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil];
    [alert addAction:cancelAction];
    
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = self.tableView;
        alert.popoverPresentationController.sourceRect = self.tableView.bounds;
    }
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (UIImage *)imageWithColor:(UIColor *)color size:(CGSize)size {
    UIGraphicsBeginImageContextWithOptions(size, YES, 0);
    [color setFill];
    [[UIColor whiteColor] setStroke];
    UIBezierPath *path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(1, 1, size.width - 2, size.height - 2)];
    path.lineWidth = 1.0;
    [path fill];
    [path stroke];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

#pragma mark - UISearchBarDelegate

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    if (searchText.length == 0) {
        self.isSearching = NO;
        self.filteredSections = self.settingSections;
        self.filteredSectionTitles = [self.sectionTitles mutableCopy];
        [self.expandedSections removeAllObjects];
    } else {
        self.isSearching = YES;
        NSMutableArray *filtered = [NSMutableArray array];
        NSMutableArray *filteredTitles = [NSMutableArray array];
        for (NSUInteger i = 0; i < self.settingSections.count; i++) {
            NSArray<DYYYSettingItem *> *section = self.settingSections[i];
            NSMutableArray<DYYYSettingItem *> *filteredItems = [NSMutableArray array];
            for (DYYYSettingItem *item in section) {
                if ([item.title localizedCaseInsensitiveContainsString:searchText]) {
                    [filteredItems addObject:item];
                }
            }
            if (filteredItems.count > 0) {
                [filtered addObject:filteredItems];
                [filteredTitles addObject:self.sectionTitles[i]];
            }
        }
        self.filteredSections = filtered;
        self.filteredSectionTitles = filteredTitles;
        [self.expandedSections removeAllObjects];
    }
    if (self.tableView) {
        [self.tableView reloadData];
    }
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.isSearching ? self.filteredSections.count : self.settingSections.count;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 44)];
    
    CGFloat margin = 16;
    CGFloat buttonWidth = tableView.bounds.size.width - 2 * margin;
    UIView *buttonContainer = [[UIView alloc] initWithFrame:CGRectMake(margin, 4, buttonWidth, 36)];
    buttonContainer.backgroundColor = [UIColor systemBackgroundColor];
    buttonContainer.layer.cornerRadius = 10;
    buttonContainer.layer.masksToBounds = YES;
    [headerView addSubview:buttonContainer];
    
    UIImageView *iconView = [[UIImageView alloc] initWithFrame:CGRectMake(10, 8, 20, 20)];
    // 修改后的 iconConfigs 数组（新增两个图标）
// 根据截图中的实际图标调整配置
NSArray<NSDictionary *> *iconConfigs = @[
    @{@"name": @"gearshape.fill", @"color": [UIColor systemBlueColor]},       // 基本设置（齿轮图标）
    @{@"name": @"display", @"color": [UIColor systemOrangeColor]},           // 界面设置（显示器图标）
    @{@"name": @"eye.slash.fill", @"color": [UIColor systemPurpleColor]},      // 隐藏设置（隐藏眼睛图标）
    @{@"name": @"trash.fill", @"color": [UIColor systemRedColor]}, // 顶栏移除（减号图标）
    @{@"name": @"star.fill", @"color": [UIColor systemYellowColor]},        // 过滤功能（漏斗图标）
    @{@"name": @"bolt.fill", @"color": [UIColor systemBlueColor]}            // 增强设置（闪电图标）
];


    NSDictionary *config = iconConfigs[MIN(section, iconConfigs.count - 1)];
    UIImage *iconImage = [UIImage systemImageNamed:config[@"name"] withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightMedium]];
    iconView.image = [iconImage imageWithTintColor:config[@"color"] renderingMode:UIImageRenderingModeAlwaysOriginal];
    [buttonContainer addSubview:iconView];
    
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(40, 0, buttonContainer.bounds.size.width - 80, 36)];
    titleLabel.text = self.isSearching ? self.filteredSectionTitles[section] : self.sectionTitles[section];
    titleLabel.textColor = [UIColor labelColor];
    titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    titleLabel.textAlignment = NSTextAlignmentLeft;
    [buttonContainer addSubview:titleLabel];
    
    UIImageView *arrow = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:[self.expandedSections containsObject:@(section)] ? @"chevron.down" : @"chevron.right"]];
    arrow.tintColor = [UIColor systemGrayColor];
    arrow.frame = CGRectMake(buttonContainer.bounds.size.width - 30, 10, 12, 16);
    arrow.tag = 100;
    [buttonContainer addSubview:arrow];
    
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.frame = buttonContainer.bounds;
    button.tag = section;
    [button addTarget:self action:@selector(headerTapped:) forControlEvents:UIControlEventTouchUpInside];
    [buttonContainer addSubview:button];
    
    return headerView;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 44;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSArray<NSArray<DYYYSettingItem *> *> *sections = self.isSearching ? self.filteredSections : self.settingSections;
    if (section >= sections.count) {
        return 0;
    }
    return [self.expandedSections containsObject:@(section)] ? sections[section].count : 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSArray<NSArray<DYYYSettingItem *> *> *sections = self.isSearching ? self.filteredSections : self.settingSections;
    if (indexPath.section >= sections.count || indexPath.row >= sections[indexPath.section].count) {
        return [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    }
    
    DYYYSettingItem *item = sections[indexPath.section][indexPath.row];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"SettingCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"SettingCell"];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    
    cell.textLabel.text = item.title;
    cell.textLabel.textColor = [UIColor labelColor];
    cell.textLabel.font = [UIFont systemFontOfSize:16];
    cell.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    
    if (item.type == DYYYSettingItemTypeSwitch) {
        UISwitch *switchView = [[UISwitch alloc] init];
        switchView.onTintColor = [UIColor systemBlueColor];
        [switchView setOn:[[NSUserDefaults standardUserDefaults] boolForKey:item.key]];
        [switchView addTarget:self action:@selector(switchToggled:) forControlEvents:UIControlEventValueChanged];
        switchView.tag = indexPath.section * 1000 + indexPath.row;
        cell.accessoryView = switchView;
    } else if (item.type == DYYYSettingItemTypeTextField) {
        UITextField *textField = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 120, 30)];
        textField.layer.cornerRadius = 8;
        textField.clipsToBounds = YES;
        textField.backgroundColor = [UIColor tertiarySystemFillColor];
        textField.textColor = [UIColor labelColor];
        textField.placeholder = item.placeholder;
        textField.textAlignment = NSTextAlignmentRight;
        textField.text = [[NSUserDefaults standardUserDefaults] stringForKey:item.key];
        [textField addTarget:self action:@selector(textFieldDidChange:) forControlEvents:UIControlEventEditingDidEnd];
        textField.tag = indexPath.section * 1000 + indexPath.row;
        cell.accessoryView = textField;
        
        if ([item.key isEqualToString:@"DYYYAvatarTapText"]) {
            [textField addTarget:self action:@selector(avatarTextFieldDidChange:) forControlEvents:UIControlEventEditingChanged];
        }
    } else if (item.type == DYYYSettingItemTypeSpeedPicker) {
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        UITextField *speedField = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 80, 30)];
        speedField.text = [NSString stringWithFormat:@"%.2f", [[NSUserDefaults standardUserDefaults] floatForKey:@"DYYYDefaultSpeed"]];
        speedField.textColor = [UIColor labelColor];
        speedField.borderStyle = UITextBorderStyleNone;
        speedField.backgroundColor = [UIColor clearColor];
        speedField.textAlignment = NSTextAlignmentRight;
        speedField.enabled = NO;
        speedField.tag = 999;
        cell.accessoryView = speedField;
    } else if (item.type == DYYYSettingItemTypeColorPicker) {
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        UIView *colorView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 30, 30)];
        colorView.layer.cornerRadius = 15;
        colorView.clipsToBounds = YES;
        colorView.layer.borderWidth = 1.0;
        colorView.layer.borderColor = [UIColor whiteColor].CGColor;
        NSData *colorData = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYBackgroundColor"];
        colorView.backgroundColor = colorData ? [NSKeyedUnarchiver unarchiveObjectWithData:colorData] : [UIColor systemBackgroundColor];
        cell.accessoryView = colorView;
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    CGFloat cornerRadius = 10.0;
    UIBezierPath *maskPath = [UIBezierPath bezierPathWithRoundedRect:cell.bounds
                                                  byRoundingCorners:(indexPath.row == 0 ? (UIRectCornerTopLeft | UIRectCornerTopRight) : 0) |
                                                                   (indexPath.row == [tableView numberOfRowsInSection:indexPath.section] - 1 ? (UIRectCornerBottomLeft | UIRectCornerBottomRight) : 0)
                                                        cornerRadii:CGSizeMake(cornerRadius, cornerRadius)];
    CAShapeLayer *maskLayer = [CAShapeLayer layer];
    maskLayer.path = maskPath.CGPath;
    cell.layer.mask = maskLayer;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSArray<NSArray<DYYYSettingItem *> *> *sections = self.isSearching ? self.filteredSections : self.settingSections;
    if (indexPath.section >= sections.count || indexPath.row >= sections[indexPath.section].count) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        return;
    }
    
    DYYYSettingItem *item = sections[indexPath.section][indexPath.row];
    if (item.type == DYYYSettingItemTypeSpeedPicker) {
        [self showSpeedPicker];
    } else if (item.type == DYYYSettingItemTypeColorPicker) {
        [self showColorPicker];
    }
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)showSpeedPicker {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"选择倍速"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    NSArray *speeds = @[@0.75, @1.0, @1.25, @1.5, @2.0, @2.5, @3.0];
    for (NSNumber *speed in speeds) {
        UIAlertAction *action = [UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%.2f", speed.floatValue]
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction * _Nonnull action) {
            [[NSUserDefaults standardUserDefaults] setFloat:speed.floatValue forKey:@"DYYYDefaultSpeed"];
            [[NSUserDefaults standardUserDefaults] synchronize];
            
            for (NSInteger section = 0; section < self.settingSections.count; section++) {
                NSArray *items = self.settingSections[section];
                for (NSInteger row = 0; row < items.count; row++) {
                    DYYYSettingItem *item = items[row];
                    if (item.type == DYYYSettingItemTypeSpeedPicker) {
                        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:section];
                        UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
                        UITextField *speedField = [cell.accessoryView viewWithTag:999];
                        if (speedField) {
                            speedField.text = [NSString stringWithFormat:@"%.2f", speed.floatValue];
                        }
                        break;
                    }
                }
            }
        }];
        [alert addAction:action];
    }
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil];
    [alert addAction:cancelAction];
    
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        UITableViewCell *selectedCell = [self.tableView cellForRowAtIndexPath:[self.tableView indexPathForSelectedRow]];
        alert.popoverPresentationController.sourceView = selectedCell;
        alert.popoverPresentationController.sourceRect = selectedCell.bounds;
    }
    
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Actions

- (void)switchToggled:(UISwitch *)sender {
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:sender.tag % 1000 inSection:sender.tag / 1000];
    NSArray<NSArray<DYYYSettingItem *> *> *sections = self.isSearching ? self.filteredSections : self.settingSections;
    if (indexPath.section >= sections.count || indexPath.row >= sections[indexPath.section].count) {
        return;
    }
    
    DYYYSettingItem *item = sections[indexPath.section][indexPath.row];
    [[NSUserDefaults standardUserDefaults] setBool:sender.isOn forKey:item.key];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)textFieldDidChange:(UITextField *)textField {
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:textField.tag % 1000 inSection:textField.tag / 1000];
    NSArray<NSArray<DYYYSettingItem *> *> *sections = self.isSearching ? self.filteredSections : self.settingSections;
    if (indexPath.section >= sections.count || indexPath.row >= sections[indexPath.section].count) {
        return;
    }
    
    DYYYSettingItem *item = sections[indexPath.section][indexPath.row];
    [[NSUserDefaults standardUserDefaults] setObject:textField.text forKey:item.key];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)avatarTextFieldDidChange:(UITextField *)textField {
    self.avatarTapLabel.text = textField.text.length > 0 ? textField.text : @"更改头像";
}

- (void)headerTapped:(UIButton *)sender {
    NSNumber *section = @(sender.tag);
    NSArray<NSArray<DYYYSettingItem *> *> *sections = self.isSearching ? self.filteredSections : self.settingSections;
    if (section.integerValue >= sections.count) {
        return;
    }
    
    BOOL isExpanded = [self.expandedSections containsObject:section];
    if (isExpanded) {
        [self.expandedSections removeObject:section];
    } else {
        [self.expandedSections addObject:section];
    }
    
    UIView *headerView = [self.tableView headerViewForSection:sender.tag];
    UIImageView *arrow = [headerView viewWithTag:100];
    [UIView animateWithDuration:0.3 animations:^{
        arrow.image = [UIImage systemImageNamed:isExpanded ? @"chevron.right" : @"chevron.down"];
    }];
    
    if (self.tableView) {
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:sender.tag] withRowAnimation:UITableViewRowAnimationAutomatic];
    }
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        CGPoint point = [gesture locationInView:self.tableView];
        NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:point];
        if (indexPath) {
            NSArray<NSArray<DYYYSettingItem *> *> *sections = self.isSearching ? self.filteredSections : self.settingSections;
            if (indexPath.section >= sections.count || indexPath.row >= sections[indexPath.section].count) {
                return;
            }
            
            DYYYSettingItem *item = sections[indexPath.section][indexPath.row];
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"选项"
                                                                          message:item.title
                                                                   preferredStyle:UIAlertControllerStyleActionSheet];
            [alert addAction:[UIAlertAction actionWithTitle:@"重置" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                [[NSUserDefaults standardUserDefaults] removeObjectForKey:item.key];
                [[NSUserDefaults standardUserDefaults] synchronize];
                if (self.tableView) {
                    [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
                }
                if ([item.key isEqualToString:@"DYYYAvatarTapText"]) {
                    self.avatarTapLabel.text = @"更改头像";
                }
            }]];
            [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
            
            if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
                alert.popoverPresentationController.sourceView = self.tableView;
                alert.popoverPresentationController.sourceRect = CGRectMake(point.x, point.y, 1, 1);
            }
            
            [self presentViewController:alert animated:YES completion:nil];
        }
    }
}

#pragma mark - Dealloc

- (void)dealloc {
    NSLog(@"DYYYSettingViewController dealloc");
    if (self.isKVOAdded && self.tableView) {
        @try {
            [self.tableView removeObserver:self forKeyPath:@"contentOffset"];
            self.isKVOAdded = NO;
            NSLog(@"DYYYSettingViewController KVO removed in dealloc");
        } @catch (NSException *exception) {
            NSLog(@"DYYYSettingViewController KVO removal failed in dealloc: %@", exception);
        }
    }
}

@end
