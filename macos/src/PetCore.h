#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSArray<NSString *> *ArgentinaPetNames(void);
FOUNDATION_EXPORT NSInteger ArgentinaFrameCount(NSInteger row);

enum {
    ArgentinaSpriteCellWidth = 192,
    ArgentinaSpriteCellHeight = 208,
    ArgentinaPetDisplayWidth = 132,
    ArgentinaPetDisplayHeight = 143
};

@interface AFPet : NSObject

@property(nonatomic, copy) NSString *name;
@property(nonatomic) NSPoint position;
@property(nonatomic) NSPoint velocity;
@property(nonatomic) NSInteger row;
@property(nonatomic) NSInteger frame;
@property(nonatomic) NSInteger specialRow;
@property(nonatomic) NSTimeInterval behaviorRemaining;
@property(nonatomic) NSTimeInterval animationAccumulator;
@property(nonatomic) BOOL manualControl;
@property(nonatomic) BOOL enabled;

- (instancetype)initWithName:(NSString *)name;

@end

NS_ASSUME_NONNULL_END
