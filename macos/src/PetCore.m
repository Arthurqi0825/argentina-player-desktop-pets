#import "PetCore.h"

NSArray<NSString *> *ArgentinaPetNames(void)
{
    static NSArray<NSString *> *names;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        names = @[@"Messi", @"Enzo", @"Romero", @"Lisandro", @"Paredes"];
    });
    return names;
}

NSInteger ArgentinaFrameCount(NSInteger row)
{
    switch (row) {
        case 0: return 6;
        case 1:
        case 2:
        case 5:
        case 9:
        case 10: return 8;
        case 3: return 4;
        case 4: return 5;
        case 6:
        case 7:
        case 8: return 6;
        default: return 6;
    }
}

@implementation AFPet

- (instancetype)initWithName:(NSString *)name
{
    self = [super init];
    if (self) {
        _name = [name copy];
        _enabled = YES;
        _specialRow = -1;
    }
    return self;
}

@end
