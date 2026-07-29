#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <sys/file.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
#import "PetCore.h"

static CGFloat AFRandomUnit(void)
{
    return (CGFloat)arc4random_uniform(UINT32_MAX) / (CGFloat)UINT32_MAX;
}

static CGFloat AFRandomRange(CGFloat minimum, CGFloat maximum)
{
    return minimum + AFRandomUnit() * (maximum - minimum);
}

static NSRect AFDesktopBounds(void)
{
    NSRect result = NSZeroRect;
    BOOL first = YES;
    for (NSScreen *screen in NSScreen.screens) {
        result = first ? screen.frame : NSUnionRect(result, screen.frame);
        first = NO;
    }
    return result;
}

@interface AFEngine : NSObject

@property(nonatomic, readonly) NSMutableArray<AFPet *> *pets;
@property(nonatomic, readonly) NSArray<NSImage *> *sprites;
@property(nonatomic) BOOL paused;
@property(nonatomic) BOOL useSpanishSpeech;
@property(nonatomic, readonly) NSTimeInterval messiSpeechRemaining;

- (instancetype)initWithError:(NSError **)error;
- (BOOL)allPetsEnabled;
- (void)setAllPetsEnabled:(BOOL)enabled;
- (void)setPetEnabled:(BOOL)enabled atIndex:(NSInteger)index;
- (void)scatterPets;
- (void)setManualVelocityForIndex:(NSInteger)index x:(CGFloat)x y:(CGFloat)y;
- (void)stopManualControlForIndex:(NSInteger)index;
- (void)triggerPlayForIndex:(NSInteger)index;
- (void)tick:(NSTimeInterval)deltaTime;
- (NSString *)speechText;

@end

@interface AFEngine ()

@property(nonatomic) NSMutableArray<AFPet *> *pets;
@property(nonatomic) NSArray<NSImage *> *sprites;
@property(nonatomic) NSMutableArray<NSValue *> *obstacles;
@property(nonatomic) NSTimeInterval obstacleRefreshRemaining;
@property(nonatomic) NSTimeInterval messiSpeechRemaining;
@property(nonatomic) NSTimeInterval messiSpeechCooldown;

@end

@implementation AFEngine

- (instancetype)initWithError:(NSError **)error
{
    self = [super init];
    if (!self) return nil;

    NSURL *assetDirectory = [self findAssetDirectory];
    if (!assetDirectory) {
        if (error) {
            *error = [NSError errorWithDomain:@"ArgentinaFivePets"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Could not find the shared assets directory."}];
        }
        return nil;
    }

    NSMutableArray<AFPet *> *pets = [NSMutableArray array];
    NSMutableArray<NSImage *> *sprites = [NSMutableArray array];
    for (NSString *name in ArgentinaPetNames()) {
        NSURL *url = [assetDirectory URLByAppendingPathComponent:
                      [[name lowercaseString] stringByAppendingPathExtension:@"png"]];
        NSImage *image = [[NSImage alloc] initWithContentsOfURL:url];
        if (!image) {
            if (error) {
                *error = [NSError errorWithDomain:@"ArgentinaFivePets"
                                             code:2
                                         userInfo:@{NSLocalizedDescriptionKey:
                                                        [NSString stringWithFormat:@"Missing pet spritesheet: %@", url.path]}];
            }
            return nil;
        }
        [pets addObject:[[AFPet alloc] initWithName:name]];
        [sprites addObject:image];
    }
    self.pets = pets;
    self.sprites = sprites;
    self.obstacles = [NSMutableArray array];
    [self scatterPets];
    return self;
}

- (NSURL *)findAssetDirectory
{
    NSFileManager *manager = NSFileManager.defaultManager;
    NSMutableArray<NSURL *> *candidates = [NSMutableArray array];
    if (NSBundle.mainBundle.resourceURL) {
        [candidates addObject:[NSBundle.mainBundle.resourceURL URLByAppendingPathComponent:@"assets"]];
    }
    NSURL *executable = [NSURL fileURLWithPath:NSProcessInfo.processInfo.arguments.firstObject];
    NSURL *resources = [[[[executable URLByDeletingLastPathComponent]
                           URLByDeletingLastPathComponent]
                          URLByAppendingPathComponent:@"Resources"]
                         URLByAppendingPathComponent:@"assets"];
    [candidates addObject:resources];
    NSURL *current = [NSURL fileURLWithPath:manager.currentDirectoryPath];
    [candidates addObject:[current URLByAppendingPathComponent:@"assets"]];
    [candidates addObject:[[current URLByDeletingLastPathComponent] URLByAppendingPathComponent:@"assets"]];

    for (NSURL *candidate in candidates) {
        if ([manager fileExistsAtPath:[[candidate URLByAppendingPathComponent:@"messi.png"] path]]) {
            return candidate;
        }
    }
    return nil;
}

- (BOOL)allPetsEnabled
{
    if (self.pets.count == 0) return NO;
    for (AFPet *pet in self.pets) {
        if (!pet.enabled) return NO;
    }
    return YES;
}

- (void)setAllPetsEnabled:(BOOL)enabled
{
    for (AFPet *pet in self.pets) {
        pet.enabled = enabled;
        pet.manualControl = NO;
        pet.specialRow = -1;
        if (!enabled) pet.velocity = NSZeroPoint;
    }
    if (enabled) [self scatterPets];
}

- (void)setPetEnabled:(BOOL)enabled atIndex:(NSInteger)index
{
    if (index < 0 || index >= (NSInteger)self.pets.count) return;
    AFPet *pet = self.pets[(NSUInteger)index];
    pet.enabled = enabled;
    pet.manualControl = NO;
    pet.specialRow = -1;
    if (!enabled) {
        pet.velocity = NSZeroPoint;
        return;
    }

    NSRect bounds = AFDesktopBounds();
    pet.position = NSMakePoint(
        AFRandomRange(NSMinX(bounds), MAX(NSMinX(bounds), NSMaxX(bounds) - ArgentinaPetDisplayWidth)),
        AFRandomRange(NSMinY(bounds), MAX(NSMinY(bounds), NSMaxY(bounds) - ArgentinaPetDisplayHeight))
    );
    CGFloat angle = AFRandomRange(0, M_PI * 2);
    pet.velocity = NSMakePoint(cos(angle) * 65, sin(angle) * 65);
    pet.behaviorRemaining = 1.5;
}

- (void)scatterPets
{
    static const CGFloat anchors[5][2] = {
        {0.08, 0.16}, {0.72, 0.12}, {0.18, 0.65}, {0.74, 0.66}, {0.45, 0.40}
    };
    NSRect bounds = AFDesktopBounds();
    CGFloat width = MAX(1, bounds.size.width - ArgentinaPetDisplayWidth);
    CGFloat height = MAX(1, bounds.size.height - ArgentinaPetDisplayHeight);
    for (NSUInteger index = 0; index < self.pets.count; index++) {
        AFPet *pet = self.pets[index];
        if (!pet.enabled) continue;
        pet.position = NSMakePoint(NSMinX(bounds) + anchors[index][0] * width,
                                   NSMinY(bounds) + anchors[index][1] * height);
        CGFloat angle = AFRandomRange(0, M_PI * 2);
        CGFloat speed = AFRandomRange(45, 80);
        pet.velocity = NSMakePoint(cos(angle) * speed, sin(angle) * speed);
        pet.behaviorRemaining = AFRandomRange(1.5, 3.5);
        pet.specialRow = -1;
        pet.frame = (NSInteger)arc4random_uniform(6);
        pet.row = pet.velocity.x >= 0 ? 1 : 2;
    }
}

- (void)setManualVelocityForIndex:(NSInteger)index x:(CGFloat)x y:(CGFloat)y
{
    if (index < 0 || index >= (NSInteger)self.pets.count) return;
    AFPet *pet = self.pets[(NSUInteger)index];
    if (!pet.enabled) {
        [self setPetEnabled:YES atIndex:index];
    }
    CGFloat length = sqrt(x * x + y * y);
    pet.velocity = length > 0 ? NSMakePoint(x / length * 145, y / length * 145) : NSZeroPoint;
    pet.manualControl = YES;
    pet.specialRow = -1;
    pet.behaviorRemaining = 0.5;
    pet.row = pet.velocity.x >= 0 ? 1 : 2;
}

- (void)stopManualControlForIndex:(NSInteger)index
{
    if (index < 0 || index >= (NSInteger)self.pets.count) return;
    AFPet *pet = self.pets[(NSUInteger)index];
    pet.velocity = NSZeroPoint;
    pet.manualControl = NO;
    pet.specialRow = 0;
    pet.behaviorRemaining = 0.45;
    pet.row = 0;
}

- (void)triggerPlayForIndex:(NSInteger)index
{
    if (index < 0 || index >= (NSInteger)self.pets.count) return;
    AFPet *pet = self.pets[(NSUInteger)index];
    if (!pet.enabled) [self setPetEnabled:YES atIndex:index];
    pet.manualControl = NO;
    pet.velocity = NSZeroPoint;
    pet.specialRow = 7;
    pet.behaviorRemaining = 1.8;
    pet.frame = 0;
}

- (NSString *)speechText
{
    return self.useSpanishSpeech ? @"¿Qué mirás, bobo?" : @"给你俩窝窝";
}

- (void)tick:(NSTimeInterval)rawDeltaTime
{
    if (self.paused) return;
    NSTimeInterval deltaTime = MIN(rawDeltaTime, 0.08);
    self.messiSpeechRemaining = MAX(0, self.messiSpeechRemaining - deltaTime);
    self.messiSpeechCooldown = MAX(0, self.messiSpeechCooldown - deltaTime);
    self.obstacleRefreshRemaining -= deltaTime;
    if (self.obstacleRefreshRemaining <= 0) {
        [self refreshWindowObstacles];
        self.obstacleRefreshRemaining = 0.7;
    }

    [self updateBehaviors:deltaTime];
    [self applySeparation:deltaTime];
    for (AFPet *pet in self.pets) {
        if (!pet.enabled) continue;
        NSPoint position = NSMakePoint(pet.position.x + pet.velocity.x * deltaTime,
                                       pet.position.y + pet.velocity.y * deltaTime);
        [self resolveDesktopEdgesForPet:pet position:&position];
        [self resolveWindowObstaclesForPet:pet position:&position];
        pet.position = position;
        pet.animationAccumulator += deltaTime;
        if (pet.animationAccumulator >= 0.12) {
            pet.animationAccumulator -= 0.12;
            pet.frame = (pet.frame + 1) % ArgentinaFrameCount(pet.row);
        }
    }
    [self resolveOverlaps];
}

- (void)updateBehaviors:(NSTimeInterval)deltaTime
{
    for (AFPet *pet in self.pets) {
        if (!pet.enabled) continue;
        if (pet.manualControl) {
            pet.specialRow = -1;
            pet.row = pet.velocity.x >= 0 ? 1 : 2;
            continue;
        }
        pet.behaviorRemaining -= deltaTime;
        if (pet.behaviorRemaining <= 0) {
            NSInteger choice = arc4random_uniform(100);
            if (choice < 18) {
                pet.specialRow = 7;
                pet.velocity = NSZeroPoint;
                pet.behaviorRemaining = AFRandomRange(1.2, 2.6);
            } else if (choice < 28) {
                pet.specialRow = 3;
                pet.velocity = NSZeroPoint;
                pet.behaviorRemaining = AFRandomRange(0.9, 1.9);
            } else if (choice < 38) {
                pet.specialRow = 4;
                pet.velocity = NSZeroPoint;
                pet.behaviorRemaining = AFRandomRange(0.8, 1.5);
            } else {
                pet.specialRow = -1;
                CGFloat angle = AFRandomRange(0, M_PI * 2);
                CGFloat speed = AFRandomRange(42, 90);
                pet.velocity = NSMakePoint(cos(angle) * speed, sin(angle) * speed);
                pet.behaviorRemaining = AFRandomRange(1.8, 5.0);
            }
            pet.frame = 0;
        }
        pet.row = pet.specialRow >= 0 ? pet.specialRow : (pet.velocity.x >= 0 ? 1 : 2);
    }
}

- (void)limitSpeedForPet:(AFPet *)pet maximum:(CGFloat)maximum
{
    CGFloat speed = hypot(pet.velocity.x, pet.velocity.y);
    if (speed <= maximum) return;
    pet.velocity = NSMakePoint(pet.velocity.x * maximum / speed,
                               pet.velocity.y * maximum / speed);
}

- (void)applySeparation:(NSTimeInterval)deltaTime
{
    const CGFloat preferredDistance = 158;
    if (self.pets.count < 2) return;
    for (NSUInteger firstIndex = 0; firstIndex + 1 < self.pets.count; firstIndex++) {
        for (NSUInteger secondIndex = firstIndex + 1; secondIndex < self.pets.count; secondIndex++) {
            AFPet *first = self.pets[firstIndex];
            AFPet *second = self.pets[secondIndex];
            if (!first.enabled || !second.enabled) continue;
            CGFloat dx = first.position.x - second.position.x;
            CGFloat dy = first.position.y - second.position.y;
            CGFloat distanceSquared = dx * dx + dy * dy;
            if (distanceSquared >= preferredDistance * preferredDistance) continue;
            CGFloat distance = sqrt(MAX(1, distanceSquared));
            if (distance < 2) {
                dx = firstIndex % 2 == 0 ? 1 : -1;
                dy = secondIndex % 2 == 0 ? 0.7 : -0.7;
                distance = hypot(dx, dy);
            }
            CGFloat strength = (preferredDistance - distance) * 2.4 * deltaTime;
            CGFloat normalX = dx / distance;
            CGFloat normalY = dy / distance;
            first.velocity = NSMakePoint(first.velocity.x + normalX * strength,
                                         first.velocity.y + normalY * strength);
            second.velocity = NSMakePoint(second.velocity.x - normalX * strength,
                                          second.velocity.y - normalY * strength);
            [self limitSpeedForPet:first maximum:105];
            [self limitSpeedForPet:second maximum:105];
        }
    }
}

- (void)resolveOverlaps
{
    const CGFloat minimumDistance = 136;
    if (self.pets.count < 2) return;
    for (NSUInteger firstIndex = 0; firstIndex + 1 < self.pets.count; firstIndex++) {
        for (NSUInteger secondIndex = firstIndex + 1; secondIndex < self.pets.count; secondIndex++) {
            AFPet *first = self.pets[firstIndex];
            AFPet *second = self.pets[secondIndex];
            if (!first.enabled || !second.enabled) continue;
            CGFloat dx = first.position.x - second.position.x;
            CGFloat dy = first.position.y - second.position.y;
            CGFloat distanceSquared = dx * dx + dy * dy;
            if (distanceSquared >= minimumDistance * minimumDistance) continue;
            if (self.messiSpeechCooldown <= 0 &&
                ([first.name isEqualToString:@"Messi"] || [second.name isEqualToString:@"Messi"])) {
                self.messiSpeechRemaining = 2.4;
                self.messiSpeechCooldown = 5.5;
            }
            CGFloat distance = sqrt(MAX(1, distanceSquared));
            if (distance < 1.5) {
                dx = firstIndex % 2 == 0 ? 1 : -1;
                dy = secondIndex % 2 == 0 ? 0.7 : -0.7;
                distance = hypot(dx, dy);
            }
            CGFloat push = (minimumDistance - distance) / 2 + 1;
            first.position = NSMakePoint(first.position.x + dx / distance * push,
                                         first.position.y + dy / distance * push);
            second.position = NSMakePoint(second.position.x - dx / distance * push,
                                          second.position.y - dy / distance * push);
            [self clampPetToDesktop:first];
            [self clampPetToDesktop:second];
        }
    }
}

- (void)resolveDesktopEdgesForPet:(AFPet *)pet position:(NSPoint *)position
{
    NSRect bounds = AFDesktopBounds();
    CGFloat maximumX = NSMaxX(bounds) - ArgentinaPetDisplayWidth;
    CGFloat maximumY = NSMaxY(bounds) - ArgentinaPetDisplayHeight;
    if (position->x < NSMinX(bounds)) {
        position->x = NSMinX(bounds);
        pet.velocity = NSMakePoint(fabs(pet.velocity.x), pet.velocity.y);
        [self endSpecialForPet:pet];
    } else if (position->x > maximumX) {
        position->x = maximumX;
        pet.velocity = NSMakePoint(-fabs(pet.velocity.x), pet.velocity.y);
        [self endSpecialForPet:pet];
    }
    if (position->y < NSMinY(bounds)) {
        position->y = NSMinY(bounds);
        pet.velocity = NSMakePoint(pet.velocity.x, fabs(pet.velocity.y));
        [self endSpecialForPet:pet];
    } else if (position->y > maximumY) {
        position->y = maximumY;
        pet.velocity = NSMakePoint(pet.velocity.x, -fabs(pet.velocity.y));
        [self endSpecialForPet:pet];
    }
}

- (void)resolveWindowObstaclesForPet:(AFPet *)pet position:(NSPoint *)position
{
    NSRect proposed = NSMakeRect(position->x + 18, position->y + 16,
                                 ArgentinaPetDisplayWidth - 36, ArgentinaPetDisplayHeight - 25);
    for (NSValue *value in self.obstacles) {
        NSRect obstacle = NSInsetRect(value.rectValue, -5, -5);
        if (!NSIntersectsRect(proposed, obstacle)) continue;
        CGFloat overlapLeft = NSMaxX(proposed) - NSMinX(obstacle);
        CGFloat overlapRight = NSMaxX(obstacle) - NSMinX(proposed);
        CGFloat overlapBottom = NSMaxY(proposed) - NSMinY(obstacle);
        CGFloat overlapTop = NSMaxY(obstacle) - NSMinY(proposed);
        CGFloat minimum = MIN(MIN(overlapLeft, overlapRight), MIN(overlapBottom, overlapTop));
        if (minimum == overlapLeft) {
            position->x -= overlapLeft;
            pet.velocity = NSMakePoint(-fabs(pet.velocity.x), pet.velocity.y);
        } else if (minimum == overlapRight) {
            position->x += overlapRight;
            pet.velocity = NSMakePoint(fabs(pet.velocity.x), pet.velocity.y);
        } else if (minimum == overlapBottom) {
            position->y -= overlapBottom;
            pet.velocity = NSMakePoint(pet.velocity.x, -fabs(pet.velocity.y));
        } else {
            position->y += overlapTop;
            pet.velocity = NSMakePoint(pet.velocity.x, fabs(pet.velocity.y));
        }
        [self endSpecialForPet:pet];
        proposed.origin = NSMakePoint(position->x + 18, position->y + 16);
    }
}

- (void)endSpecialForPet:(AFPet *)pet
{
    pet.specialRow = -1;
    pet.behaviorRemaining = MIN(pet.behaviorRemaining, 0.4);
}

- (void)clampPetToDesktop:(AFPet *)pet
{
    NSRect bounds = AFDesktopBounds();
    pet.position = NSMakePoint(
        MIN(MAX(pet.position.x, NSMinX(bounds)), NSMaxX(bounds) - ArgentinaPetDisplayWidth),
        MIN(MAX(pet.position.y, NSMinY(bounds)), NSMaxY(bounds) - ArgentinaPetDisplayHeight)
    );
}

- (void)refreshWindowObstacles
{
    CFArrayRef rawWindowList = CGWindowListCopyWindowInfo(
        kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements,
        kCGNullWindowID
    );
    NSArray<NSDictionary *> *windowList = CFBridgingRelease(rawWindowList);
    NSMutableArray<NSValue *> *obstacles = [NSMutableArray array];
    pid_t ownPID = NSProcessInfo.processInfo.processIdentifier;
    NSRect desktop = AFDesktopBounds();
    CGFloat desktopArea = MAX(1, desktop.size.width * desktop.size.height);
    CGFloat mainScreenTop = NSScreen.screens.firstObject ? NSMaxY(NSScreen.screens.firstObject.frame) : NSMaxY(desktop);

    for (NSDictionary *windowInfo in windowList) {
        pid_t ownerPID = [windowInfo[(NSString *)kCGWindowOwnerPID] intValue];
        NSInteger layer = [windowInfo[(NSString *)kCGWindowLayer] integerValue];
        CGFloat alpha = [windowInfo[(NSString *)kCGWindowAlpha] doubleValue];
        if (ownerPID == ownPID || layer != 0 || alpha <= 0) continue;
        CGRect quartzRect;
        if (!CGRectMakeWithDictionaryRepresentation(
                (__bridge CFDictionaryRef)windowInfo[(NSString *)kCGWindowBounds], &quartzRect)) continue;
        NSRect appKitRect = NSMakeRect(quartzRect.origin.x,
                                      mainScreenTop - CGRectGetMaxY(quartzRect),
                                      quartzRect.size.width,
                                      quartzRect.size.height);
        if (appKitRect.size.width < 120 || appKitRect.size.height < 80) continue;
        if (appKitRect.size.width * appKitRect.size.height > desktopArea * 0.82) continue;
        if (!NSIntersectsRect(appKitRect, desktop)) continue;
        [obstacles addObject:[NSValue valueWithRect:appKitRect]];
    }
    self.obstacles = obstacles;
}

@end

@interface AFOverlayView : NSView

- (instancetype)initWithFrame:(NSRect)frame engine:(AFEngine *)engine screenFrame:(NSRect)screenFrame;

@end

@interface AFOverlayView ()

@property(nonatomic) AFEngine *engine;
@property(nonatomic) NSRect screenFrame;

@end

@implementation AFOverlayView

- (instancetype)initWithFrame:(NSRect)frame engine:(AFEngine *)engine screenFrame:(NSRect)screenFrame
{
    self = [super initWithFrame:frame];
    if (self) {
        _engine = engine;
        _screenFrame = screenFrame;
        self.wantsLayer = YES;
        self.layer.backgroundColor = NSColor.clearColor.CGColor;
    }
    return self;
}

- (BOOL)isOpaque
{
    return NO;
}

- (void)drawRect:(NSRect)dirtyRect
{
    [NSColor.clearColor setFill];
    NSRectFill(dirtyRect);
    for (NSUInteger index = 0; index < self.engine.pets.count; index++) {
        AFPet *pet = self.engine.pets[index];
        if (!pet.enabled) continue;
        NSRect globalDestination = NSMakeRect(pet.position.x, pet.position.y,
                                              ArgentinaPetDisplayWidth, ArgentinaPetDisplayHeight);
        if (!NSIntersectsRect(globalDestination, self.screenFrame)) continue;
        NSInteger column = pet.frame % ArgentinaFrameCount(pet.row);
        NSImage *image = self.engine.sprites[index];
        NSRect source = NSMakeRect(column * ArgentinaSpriteCellWidth,
                                   image.size.height - (pet.row + 1) * ArgentinaSpriteCellHeight,
                                   ArgentinaSpriteCellWidth,
                                   ArgentinaSpriteCellHeight);
        NSRect destination = NSMakeRect(pet.position.x - NSMinX(self.screenFrame),
                                        pet.position.y - NSMinY(self.screenFrame),
                                        ArgentinaPetDisplayWidth,
                                        ArgentinaPetDisplayHeight);
        [image drawInRect:destination
                 fromRect:source
                operation:NSCompositingOperationSourceOver
                 fraction:1
           respectFlipped:YES
                    hints:@{NSImageHintInterpolation: @(NSImageInterpolationNone)}];
    }
    if (self.engine.messiSpeechRemaining > 0 &&
        self.engine.pets.count > 0 &&
        self.engine.pets.firstObject.enabled) {
        [self drawMessiSpeech:self.engine.pets.firstObject];
    }
}

- (void)drawMessiSpeech:(AFPet *)messi
{
    const CGFloat bubbleWidth = 206;
    const CGFloat bubbleHeight = 42;
    CGFloat globalX = messi.position.x + ArgentinaPetDisplayWidth / 2 - bubbleWidth / 2;
    globalX = MIN(MAX(globalX, NSMinX(self.screenFrame) + 5),
                  NSMaxX(self.screenFrame) - bubbleWidth - 5);
    BOOL drawAbove = messi.position.y + ArgentinaPetDisplayHeight + bubbleHeight + 8 <= NSMaxY(self.screenFrame);
    CGFloat globalY = drawAbove
        ? messi.position.y + ArgentinaPetDisplayHeight + 8
        : messi.position.y - bubbleHeight - 7;
    globalY = MIN(MAX(globalY, NSMinY(self.screenFrame) + 5),
                  NSMaxY(self.screenFrame) - bubbleHeight - 5);
    NSRect bubble = NSMakeRect(globalX - NSMinX(self.screenFrame),
                               globalY - NSMinY(self.screenFrame),
                               bubbleWidth, bubbleHeight);

    NSBezierPath *bubblePath = [NSBezierPath bezierPathWithOvalInRect:bubble];
    [NSColor.whiteColor setFill];
    [bubblePath fill];
    [[NSColor colorWithCalibratedWhite:0.12 alpha:1] setStroke];
    bubblePath.lineWidth = 2;
    [bubblePath stroke];

    CGFloat petCenterX = messi.position.x + ArgentinaPetDisplayWidth / 2 - NSMinX(self.screenFrame);
    CGFloat tailCenter = MIN(MAX(petCenterX, NSMinX(bubble) + 25), NSMaxX(bubble) - 25);
    NSBezierPath *tail = [NSBezierPath bezierPath];
    if (drawAbove) {
        [tail moveToPoint:NSMakePoint(tailCenter - 8, NSMinY(bubble) + 5)];
        [tail lineToPoint:NSMakePoint(tailCenter + 8, NSMinY(bubble) + 5)];
        [tail lineToPoint:NSMakePoint(petCenterX,
                                      messi.position.y + ArgentinaPetDisplayHeight - 5 - NSMinY(self.screenFrame))];
    } else {
        [tail moveToPoint:NSMakePoint(tailCenter - 8, NSMaxY(bubble) - 5)];
        [tail lineToPoint:NSMakePoint(tailCenter + 8, NSMaxY(bubble) - 5)];
        [tail lineToPoint:NSMakePoint(petCenterX, messi.position.y + 5 - NSMinY(self.screenFrame))];
    }
    [tail closePath];
    [NSColor.whiteColor setFill];
    [tail fill];
    [[NSColor colorWithCalibratedWhite:0.12 alpha:1] setStroke];
    tail.lineWidth = 2;
    [tail stroke];

    NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.alignment = NSTextAlignmentCenter;
    NSDictionary *attributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:14 weight:NSFontWeightBold],
        NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.08 alpha:1],
        NSParagraphStyleAttributeName: paragraph
    };
    NSRect textRect = NSMakeRect(NSMinX(bubble) + 8, NSMinY(bubble) + 11,
                                 bubble.size.width - 16, 20);
    [[self.engine speechText] drawInRect:textRect withAttributes:attributes];
}

@end

@interface AFHoldButton : NSButton

@property(nonatomic, copy) dispatch_block_t pressBlock;
@property(nonatomic, copy) dispatch_block_t releaseBlock;

@end

@implementation AFHoldButton

- (void)mouseDown:(NSEvent *)event
{
    if (self.pressBlock) self.pressBlock();
    [super mouseDown:event];
    if (self.releaseBlock) self.releaseBlock();
}

@end

@interface AFManualController : NSWindowController <NSWindowDelegate>

- (instancetype)initWithEngine:(AFEngine *)engine;
- (void)show;
- (void)closeCompletely;

@end

@interface AFManualController ()

@property(nonatomic) AFEngine *engine;
@property(nonatomic) NSPopUpButton *playerSelector;
@property(nonatomic) NSMutableSet<NSNumber *> *pressedKeys;
@property(nonatomic) id eventMonitor;

@end

@implementation AFManualController

- (instancetype)initWithEngine:(AFEngine *)engine
{
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 380, 255)
                                                styleMask:NSWindowStyleMaskTitled |
                                                          NSWindowStyleMaskClosable |
                                                          NSWindowStyleMaskUtilityWindow
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    self = [super initWithWindow:panel];
    if (!self) return nil;

    self.engine = engine;
    self.pressedKeys = [NSMutableSet set];
    panel.title = @"Argentina Pets — Manual Control";
    panel.floatingPanel = YES;
    panel.level = NSFloatingWindowLevel;
    panel.hidesOnDeactivate = NO;
    panel.delegate = self;

    NSView *content = [[NSView alloc] initWithFrame:panel.contentView.bounds];
    panel.contentView = content;
    NSTextField *label = [NSTextField labelWithString:@"Choose player:"];
    label.frame = NSMakeRect(20, 213, 105, 20);
    [content addSubview:label];
    self.playerSelector = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(126, 208, 230, 28)];
    [self.playerSelector addItemsWithTitles:ArgentinaPetNames()];
    self.playerSelector.target = self;
    self.playerSelector.action = @selector(playerChanged:);
    [content addSubview:self.playerSelector];

    [content addSubview:[self directionButton:@"▲" frame:NSMakeRect(158, 145, 54, 42) x:0 y:1]];
    [content addSubview:[self directionButton:@"◀" frame:NSMakeRect(100, 98, 54, 42) x:-1 y:0]];
    [content addSubview:[self directionButton:@"▶" frame:NSMakeRect(216, 98, 54, 42) x:1 y:0]];
    [content addSubview:[self directionButton:@"▼" frame:NSMakeRect(158, 51, 54, 42) x:0 y:-1]];

    NSButton *stop = [NSButton buttonWithTitle:@"■" target:self action:@selector(stopSelected:)];
    stop.frame = NSMakeRect(158, 98, 54, 42);
    [content addSubview:stop];
    NSButton *play = [NSButton buttonWithTitle:@"Play" target:self action:@selector(playSelected:)];
    play.frame = NSMakeRect(284, 110, 72, 42);
    [content addSubview:play];
    NSTextField *help = [NSTextField labelWithString:@"Hold Arrow keys or W/A/S/D to move. Space plays."];
    help.alignment = NSTextAlignmentCenter;
    help.frame = NSMakeRect(18, 16, 344, 20);
    [content addSubview:help];

    __weak typeof(self) weakSelf = self;
    self.eventMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:
                         NSEventMaskKeyDown | NSEventMaskKeyUp
                                                               handler:^NSEvent *(NSEvent *event) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || !strongSelf.window.keyWindow) return event;
        return [strongSelf handleKeyEvent:event] ? nil : event;
    }];
    return self;
}

- (void)dealloc
{
    if (self.eventMonitor) [NSEvent removeMonitor:self.eventMonitor];
}

- (AFHoldButton *)directionButton:(NSString *)title frame:(NSRect)frame x:(CGFloat)x y:(CGFloat)y
{
    AFHoldButton *button = [AFHoldButton buttonWithTitle:title target:nil action:nil];
    button.frame = frame;
    __weak typeof(self) weakSelf = self;
    button.pressBlock = ^{
        typeof(self) selfReference = weakSelf;
        [selfReference.engine setManualVelocityForIndex:selfReference.playerSelector.indexOfSelectedItem x:x y:y];
    };
    button.releaseBlock = ^{ [weakSelf stopSelected:nil]; };
    return button;
}

- (void)show
{
    [self.window center];
    [NSApp activateIgnoringOtherApps:YES];
    [self.window makeKeyAndOrderFront:nil];
}

- (void)closeCompletely
{
    [self stopSelected:nil];
    [self close];
}

- (void)windowWillClose:(NSNotification *)notification
{
    [self.pressedKeys removeAllObjects];
    [self stopSelected:nil];
}

- (void)playerChanged:(id)sender
{
    [self.pressedKeys removeAllObjects];
    [self stopSelected:nil];
}

- (void)stopSelected:(id)sender
{
    [self.engine stopManualControlForIndex:self.playerSelector.indexOfSelectedItem];
}

- (void)playSelected:(id)sender
{
    [self.engine triggerPlayForIndex:self.playerSelector.indexOfSelectedItem];
}

- (BOOL)handleKeyEvent:(NSEvent *)event
{
    NSSet<NSNumber *> *movementCodes = [NSSet setWithArray:@[@0, @1, @2, @13, @123, @124, @125, @126]];
    if (event.keyCode == 49 && event.type == NSEventTypeKeyDown) {
        [self playSelected:nil];
        return YES;
    }
    NSNumber *key = @(event.keyCode);
    if (![movementCodes containsObject:key]) return NO;
    if (event.type == NSEventTypeKeyDown) {
        [self.pressedKeys addObject:key];
    } else {
        [self.pressedKeys removeObject:key];
    }
    CGFloat x = 0;
    CGFloat y = 0;
    if ([self.pressedKeys containsObject:@0] || [self.pressedKeys containsObject:@123]) x -= 1;
    if ([self.pressedKeys containsObject:@2] || [self.pressedKeys containsObject:@124]) x += 1;
    if ([self.pressedKeys containsObject:@13] || [self.pressedKeys containsObject:@126]) y += 1;
    if ([self.pressedKeys containsObject:@1] || [self.pressedKeys containsObject:@125]) y -= 1;
    if (x == 0 && y == 0) {
        [self stopSelected:nil];
    } else {
        [self.engine setManualVelocityForIndex:self.playerSelector.indexOfSelectedItem x:x y:y];
    }
    return YES;
}

@end

@interface AFAppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate>
@end

@interface AFAppDelegate ()

@property(nonatomic) AFEngine *engine;
@property(nonatomic) NSStatusItem *statusItem;
@property(nonatomic) NSMutableArray<NSWindow *> *overlayWindows;
@property(nonatomic) NSMutableArray<AFOverlayView *> *overlayViews;
@property(nonatomic) NSTimer *timer;
@property(nonatomic) NSTimeInterval previousTick;
@property(nonatomic) AFManualController *controller;
@property(nonatomic) int lockFileDescriptor;

@end

@implementation AFAppDelegate

- (instancetype)init
{
    self = [super init];
    if (self) _lockFileDescriptor = -1;
    return self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    if (![self acquireSingleInstanceLock]) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Argentina Five Pets is already running.";
        alert.informativeText = @"Use the paw icon in the menu bar to control it.";
        [alert runModal];
        [NSApp terminate:nil];
        return;
    }
    NSError *error;
    self.engine = [[AFEngine alloc] initWithError:&error];
    if (!self.engine) {
        [[NSAlert alertWithError:error] runModal];
        [NSApp terminate:nil];
        return;
    }

    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    [self configureStatusItem];
    [self rebuildOverlayWindows];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(screenParametersChanged:)
                                               name:NSApplicationDidChangeScreenParametersNotification
                                             object:nil];
    self.previousTick = NSProcessInfo.processInfo.systemUptime;
    self.timer = [NSTimer timerWithTimeInterval:1.0 / 30.0
                                        target:self
                                      selector:@selector(tick:)
                                      userInfo:nil
                                       repeats:YES];
    [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
    [self.timer invalidate];
    [self.controller closeCompletely];
    for (NSWindow *window in self.overlayWindows) [window close];
    if (self.lockFileDescriptor >= 0) {
        flock(self.lockFileDescriptor, LOCK_UN);
        close(self.lockFileDescriptor);
    }
}

- (void)configureStatusItem
{
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSSquareStatusItemLength];
    self.statusItem.button.toolTip = @"Argentina Five Pets — click or right-click for controls";
    if (@available(macOS 11.0, *)) {
        self.statusItem.button.image = [NSImage imageWithSystemSymbolName:@"pawprint.fill"
                                                accessibilityDescription:@"Argentina Five Pets"];
    } else {
        self.statusItem.button.title = @"🐾";
    }
    NSMenu *menu = [[NSMenu alloc] init];
    menu.delegate = self;
    self.statusItem.menu = menu;
}

- (void)menuNeedsUpdate:(NSMenu *)menu
{
    [menu removeAllItems];
    NSMenuItem *master = [[NSMenuItem alloc] initWithTitle:@"Start 5 Pets / 启动 5 个桌宠"
                                                   action:@selector(toggleAllPets:)
                                            keyEquivalent:@""];
    master.target = self;
    master.state = self.engine.allPetsEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:master];

    NSMenuItem *playersItem = [[NSMenuItem alloc] initWithTitle:@"Players / 单独角色"
                                                        action:nil
                                                 keyEquivalent:@""];
    NSMenu *players = [[NSMenu alloc] init];
    for (NSUInteger index = 0; index < self.engine.pets.count; index++) {
        AFPet *pet = self.engine.pets[index];
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:pet.name
                                                     action:@selector(togglePlayer:)
                                              keyEquivalent:@""];
        item.target = self;
        item.tag = (NSInteger)index;
        item.state = pet.enabled ? NSControlStateValueOn : NSControlStateValueOff;
        [players addItem:item];
    }
    playersItem.submenu = players;
    [menu addItem:playersItem];

    NSMenuItem *languageItem = [[NSMenuItem alloc] initWithTitle:@"Language / 语言"
                                                          action:nil
                                                   keyEquivalent:@""];
    NSMenu *languages = [[NSMenu alloc] init];
    NSMenuItem *chinese = [[NSMenuItem alloc] initWithTitle:@"中文"
                                                     action:@selector(selectChinese:)
                                              keyEquivalent:@""];
    chinese.target = self;
    chinese.state = self.engine.useSpanishSpeech ? NSControlStateValueOff : NSControlStateValueOn;
    [languages addItem:chinese];
    NSMenuItem *spanish = [[NSMenuItem alloc] initWithTitle:@"Español"
                                                     action:@selector(selectSpanish:)
                                              keyEquivalent:@""];
    spanish.target = self;
    spanish.state = self.engine.useSpanishSpeech ? NSControlStateValueOn : NSControlStateValueOff;
    [languages addItem:spanish];
    languageItem.submenu = languages;
    [menu addItem:languageItem];

    NSMenuItem *pause = [[NSMenuItem alloc] initWithTitle:@"Pause / Resume"
                                                   action:@selector(togglePaused:)
                                            keyEquivalent:@""];
    pause.target = self;
    pause.state = self.engine.paused ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:pause];
    NSMenuItem *controller = [[NSMenuItem alloc] initWithTitle:@"Manual Controller…"
                                                        action:@selector(showController:)
                                                 keyEquivalent:@""];
    controller.target = self;
    [menu addItem:controller];
    NSMenuItem *scatter = [[NSMenuItem alloc] initWithTitle:@"Scatter Now"
                                                     action:@selector(scatterPets:)
                                              keyEquivalent:@""];
    scatter.target = self;
    [menu addItem:scatter];
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"Exit"
                                                  action:@selector(quit:)
                                           keyEquivalent:@"q"];
    quit.target = self;
    [menu addItem:quit];
}

- (void)toggleAllPets:(id)sender
{
    [self.engine setAllPetsEnabled:!self.engine.allPetsEnabled];
    [self markOverlaysForDisplay];
}

- (void)togglePlayer:(NSMenuItem *)sender
{
    AFPet *pet = self.engine.pets[(NSUInteger)sender.tag];
    [self.engine setPetEnabled:!pet.enabled atIndex:sender.tag];
    [self markOverlaysForDisplay];
}

- (void)selectChinese:(id)sender { self.engine.useSpanishSpeech = NO; }
- (void)selectSpanish:(id)sender { self.engine.useSpanishSpeech = YES; }
- (void)togglePaused:(id)sender { self.engine.paused = !self.engine.paused; }

- (void)showController:(id)sender
{
    if (!self.controller) self.controller = [[AFManualController alloc] initWithEngine:self.engine];
    [self.controller show];
}

- (void)scatterPets:(id)sender
{
    [self.engine scatterPets];
    [self markOverlaysForDisplay];
}

- (void)quit:(id)sender
{
    [NSApp terminate:nil];
}

- (void)screenParametersChanged:(NSNotification *)notification
{
    [self rebuildOverlayWindows];
    [self.engine scatterPets];
}

- (void)tick:(NSTimer *)timer
{
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    [self.engine tick:now - self.previousTick];
    self.previousTick = now;
    [self markOverlaysForDisplay];
}

- (void)rebuildOverlayWindows
{
    for (NSWindow *window in self.overlayWindows) [window close];
    self.overlayWindows = [NSMutableArray array];
    self.overlayViews = [NSMutableArray array];
    for (NSScreen *screen in NSScreen.screens) {
        NSWindow *window = [[NSWindow alloc] initWithContentRect:screen.frame
                                                     styleMask:NSWindowStyleMaskBorderless
                                                       backing:NSBackingStoreBuffered
                                                         defer:NO
                                                        screen:screen];
        [window setFrame:screen.frame display:NO];
        window.backgroundColor = NSColor.clearColor;
        window.opaque = NO;
        window.hasShadow = NO;
        window.ignoresMouseEvents = YES;
        window.level = NSFloatingWindowLevel;
        window.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
                                    NSWindowCollectionBehaviorFullScreenAuxiliary |
                                    NSWindowCollectionBehaviorStationary;
        window.releasedWhenClosed = NO;
        AFOverlayView *view = [[AFOverlayView alloc] initWithFrame:
                               NSMakeRect(0, 0, screen.frame.size.width, screen.frame.size.height)
                                                               engine:self.engine
                                                          screenFrame:screen.frame];
        window.contentView = view;
        [window orderFrontRegardless];
        [self.overlayWindows addObject:window];
        [self.overlayViews addObject:view];
    }
}

- (void)markOverlaysForDisplay
{
    for (AFOverlayView *view in self.overlayViews) view.needsDisplay = YES;
}

- (BOOL)acquireSingleInstanceLock
{
    NSString *lockPath = [NSTemporaryDirectory()
                          stringByAppendingPathComponent:@"io.github.w3sley7.argentina-five-pets.lock"];
    self.lockFileDescriptor = open(lockPath.fileSystemRepresentation,
                                   O_CREAT | O_RDWR,
                                   S_IRUSR | S_IWUSR);
    if (self.lockFileDescriptor < 0) return NO;
    return flock(self.lockFileDescriptor, LOCK_EX | LOCK_NB) == 0;
}

@end

static BOOL AFRequire(BOOL condition, NSString *message)
{
    if (!condition) {
        fprintf(stderr, "SELF-TEST FAILURE: %s\n", message.UTF8String);
        return NO;
    }
    return YES;
}

static int AFRunIntegrationSelfTest(void)
{
    NSError *error;
    AFEngine *engine = [[AFEngine alloc] initWithError:&error];
    if (!AFRequire(engine != nil, error.localizedDescription ?: @"Engine failed to initialize.")) return 1;
    if (!AFRequire(engine.pets.count == 5, @"Expected five pets.")) return 1;
    if (!AFRequire(engine.allPetsEnabled, @"All pets should start enabled.")) return 1;

    [engine setAllPetsEnabled:NO];
    if (!AFRequire(!engine.allPetsEnabled, @"The master switch did not stop all pets.")) return 1;
    for (AFPet *pet in engine.pets) {
        if (!AFRequire(!pet.enabled, @"A pet remained enabled after the master stop.")) return 1;
    }
    [engine setAllPetsEnabled:YES];
    if (!AFRequire(engine.allPetsEnabled, @"The master switch did not start all pets.")) return 1;
    [engine setPetEnabled:NO atIndex:2];
    if (!AFRequire(!engine.pets[2].enabled, @"The individual player switch failed.")) return 1;
    [engine setManualVelocityForIndex:2 x:1 y:0];
    if (!AFRequire(engine.pets[2].enabled && engine.pets[2].manualControl,
                   @"Manual control did not enable and control the selected player.")) return 1;
    [engine stopManualControlForIndex:2];
    [engine triggerPlayForIndex:2];
    if (!AFRequire(engine.pets[2].specialRow == 7, @"The Play action did not select its animation.")) return 1;

    AFAppDelegate *delegate = [[AFAppDelegate alloc] init];
    delegate.engine = engine;
    [delegate configureStatusItem];
    NSMenu *menu = delegate.statusItem.menu;
    [delegate menuNeedsUpdate:menu];
    if (!AFRequire(menu.numberOfItems == 8, @"The status menu has an unexpected item count.")) return 1;
    if (!AFRequire([menu.itemArray.firstObject.title hasPrefix:@"Start 5 Pets"],
                   @"The master Start 5 Pets item is missing.")) return 1;
    NSMenuItem *playersItem = menu.itemArray[1];
    if (!AFRequire(playersItem.submenu.numberOfItems == 5, @"The Players menu must contain five roles.")) return 1;
    NSArray<NSString *> *menuNames = [playersItem.submenu.itemArray valueForKey:@"title"];
    if (!AFRequire([menuNames isEqualToArray:ArgentinaPetNames()],
                   @"The Players menu roster is incorrect.")) return 1;
    if (!AFRequire([menu.itemArray[3].title isEqualToString:@"Pause / Resume"],
                   @"Pause / Resume is missing from the status menu.")) return 1;
    if (!AFRequire([menu.itemArray[4].title isEqualToString:@"Manual Controller…"],
                   @"Manual Controller is missing from the status menu.")) return 1;

    fprintf(stdout, "ArgentinaFivePets integration self-test: all checks passed.\n");
    return 0;
}

int main(void)
{
    @autoreleasepool {
        NSApplication *application = NSApplication.sharedApplication;
        if ([NSProcessInfo.processInfo.arguments containsObject:@"--self-test"]) {
            return AFRunIntegrationSelfTest();
        }
        AFAppDelegate *delegate = [[AFAppDelegate alloc] init];
        application.delegate = delegate;
        [application run];
    }
    return 0;
}
