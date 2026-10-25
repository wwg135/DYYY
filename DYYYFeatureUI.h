#import <Foundation/Foundation.h>
@interface DYYYFeatureUI : NSObject
+ (id)value:(id)object key:(NSString *)key;
+ (void)setValue:(id)value object:(id)object key:(NSString *)key;
+ (id)ivar:(id)object name:(const char *)name;
@end
