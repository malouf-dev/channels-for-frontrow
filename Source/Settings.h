// Settings.h
//
// Live TV's settings, shared by the Front Row plugin and the preference pane.
// They live in the preferences domain channels-for-frontrow, in the user's own
// preferences. The pane writes them and the plugin reads them each time the
// Live TV menu opens.
//
// This file is also built into the preference pane, whose 64-bit version
// runs with garbage collection, so the code works with or without it.

#import <Foundation/Foundation.h>

// host:port typed in the pane. When it isn't set, Bonjour finds the server.
extern NSString *const LTVSettingChannelsServer;

// The name of the Bonjour server to use when there are several.
extern NSString *const LTVSettingChannelsServerName;

// The channel collection to show. Every channel when it isn't set.
extern NSString *const LTVSettingChannelCollection;

// Reads the preferences file again each time, so changes made by the other
// process apply straight away.
NSString *LTVReadSetting(NSString *key);

// Saves straight away. nil removes the setting.
void LTVWriteSetting(NSString *key, NSString *value);
