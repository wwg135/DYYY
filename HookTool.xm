#import <UIKit/UIKit.h>

@interface AWEAwemeModel : NSObject
@end

@interface AWELongPressPanelConfiguration : NSObject
@end

@interface LOTAnimationView : UIView
@end

@interface AWEShareItem : NSObject
@end

@protocol AWELongPressPanelTableViewControllerProtocol <NSObject>
@end

@interface AWELongPressPanelManager : NSObject
@end

@interface AWELongPressPanelViewGroupModel : NSObject
@property(nonatomic) NSUInteger groupType;
@property(retain, nonatomic) NSArray *groupArr;
@end

@interface AWELongPressPanelBaseViewModel : NSObject
+ (id)longPressPanelViewModel;
- (void)setAction:(id)action;
- (void)setAwemeModel:(AWEAwemeModel *)awemeModel;
- (void)setPanelManager:(AWELongPressPanelManager *)panelManager;
- (void)setLogExtraDict:(NSDictionary *)logExtraDict;
- (void)setReferString:(NSString *)referString;
- (void)setDuxIconName:(id)arg1;
- (void)setDescribeString:(id)arg1;
- (void)setAction:(id)arg1;
@end

@interface AWELongPressPanelFamiliarRecommendViewModel : AWELongPressPanelBaseViewModel
@property(nonatomic) NSUInteger familiarRecommendActionType;
+ (id)longPressPanelViewModel;
- (void)recommendAweme;
- (void)configVM;
@end

@interface AWELongPressPanelCustomViewModel : AWELongPressPanelBaseViewModel
@property(nonatomic) NSUInteger customActionType;
+ (id)longPressPanelViewModel;
- (void)configVM;
@end

@interface AWEModernLongPressInteractiveCell : UITableViewCell
@property(nonatomic, strong) AWELongPressPanelViewGroupModel *longPressViewGroupModel;
@end

%subclass AWELongPressPanelCustomViewModel : AWELongPressPanelBaseViewModel

+ (id)longPressPanelViewModel {
	return [[%c(AWELongPressPanelCustomViewModel) alloc] init];
}

%end

%hook AWEModernLongPressInteractiveCell

- (void)setLongPressViewGroupModel:(AWELongPressPanelViewGroupModel *)model {
	if (model.groupType == 11) {
		NSArray *originalGroupArr = model.groupArr;
		if (originalGroupArr.count > 0) {
			// 使用自定义类创建实例
			AWELongPressPanelCustomViewModel *customViewModel = [%c(AWELongPressPanelCustomViewModel) longPressPanelViewModel];

			// 配置自定义模型
			[customViewModel setDescribeString:@"自定义操作"];
			[customViewModel setCustomActionType:999];
			[customViewModel setDuxIconName:@"ic_xiaoxihuazhonghua_outlined"];

			// 创建新数组并添加我们的模型
			NSMutableArray *newGroupArr = [NSMutableArray array];
			[newGroupArr addObject:customViewModel];
			[newGroupArr addObjectsFromArray:originalGroupArr];

			[model setGroupArr:newGroupArr];
		}
	}

	%orig(model);
}

%end

%ctor {
	%init;
}
