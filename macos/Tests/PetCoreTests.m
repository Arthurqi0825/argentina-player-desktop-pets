#import <Foundation/Foundation.h>
#import "../src/PetCore.h"

static void Require(BOOL condition, NSString *message)
{
    if (!condition) {
        NSLog(@"TEST FAILURE: %@", message);
        exit(1);
    }
}

int main(void)
{
    @autoreleasepool {
        Require([ArgentinaPetNames() isEqualToArray:@[@"Messi", @"Enzo", @"Romero", @"Lisandro", @"Paredes"]],
                @"The five-player roster changed.");
        NSArray<NSNumber *> *expected = @[@6, @8, @8, @4, @5, @8, @6, @6, @6, @8, @8];
        for (NSInteger row = 0; row < (NSInteger)expected.count; row++) {
            Require(ArgentinaFrameCount(row) == expected[(NSUInteger)row].integerValue,
                    [NSString stringWithFormat:@"Unexpected frame count for row %ld.", (long)row]);
        }
        AFPet *pet = [[AFPet alloc] initWithName:@"Messi"];
        Require(pet.enabled, @"Pets must be enabled by default.");
        Require(pet.specialRow == -1, @"Pets must start outside a special animation.");
        NSLog(@"PetCoreTests: all checks passed.");
    }
    return 0;
}
