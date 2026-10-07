// Appliance.m
//
// The bundle's principal class: Front Row creates one and asks it for the root
// controller each time the user opens Live TV from the main menu.
//
// Front Row 2.2.1 only loads an appliance whose principal class name is on a
// hard-coded list of Apple's own appliances (-[BRApplianceManager
// _loadApplianceInfoAtPath:]). RUIYTAppliance is on that list, and Front Row on
// 10.6 ships no appliance with that name, so Live TV borrows it.

#import <objc/runtime.h>
#import "BackRow.h"
#import "ChannelMenuController.h"

@interface RUIYTAppliance : BRAppliance <BRApplianceProtocol>
@end

static BOOL LTVBackRowMatches = YES;

static void LTVCheckSize(const char *className, size_t assumedSize)
{
    size_t realSize = class_getInstanceSize(objc_getClass(className));
    if (realSize != assumedSize) {
        NSLog(@"Live TV: %s is %lu bytes but BackRow.h assumes %lu. Live TV is disabled.",
              className, (unsigned long)realSize, (unsigned long)assumedSize);
        LTVBackRowMatches = NO;
    }
}

@implementation RUIYTAppliance

+ (void)initialize
{
    if (self != [RUIYTAppliance class])
        return;
    LTVCheckSize("BRAppliance", BRApplianceSize);
    LTVCheckSize("BRBaseMediaAsset", BRBaseMediaAssetSize);
    LTVCheckSize("BRController", BRControllerSize);
    LTVCheckSize("BRMediaMenuController", BRMediaMenuControllerSize);
    NSLog(@"Live TV: loaded");
}

- (id)applianceController
{
    if (!LTVBackRowMatches)
        return [BRAlertController alertOfType:0
                                       titled:@"Live TV"
                                  primaryText:@"Channels for Front Row doesn't support this version of Front Row."
                                secondaryText:nil];
    return [[[LTVChannelMenuController alloc] init] autorelease];
}

@end
