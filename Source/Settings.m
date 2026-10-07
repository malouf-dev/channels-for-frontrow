// Settings.m

#import "Settings.h"

static NSString *const LTVSettingsDomain = @"channels-for-frontrow";

NSString *const LTVSettingChannelsServer = @"ChannelsServer";
NSString *const LTVSettingChannelsServerName = @"ChannelsServerName";
NSString *const LTVSettingChannelCollection = @"ChannelCollection";

NSString *LTVReadSetting(NSString *key)
{
    CFPreferencesAppSynchronize((CFStringRef)LTVSettingsDomain);
    id value = [NSMakeCollectable(CFPreferencesCopyAppValue((CFStringRef)key, (CFStringRef)LTVSettingsDomain)) autorelease];
    return ([value isKindOfClass:[NSString class]] && [value length]) ? value : nil;
}

void LTVWriteSetting(NSString *key, NSString *value)
{
    CFPreferencesSetAppValue((CFStringRef)key, (CFPropertyListRef)([value length] ? value : nil), (CFStringRef)LTVSettingsDomain);
    CFPreferencesAppSynchronize((CFStringRef)LTVSettingsDomain);
}
