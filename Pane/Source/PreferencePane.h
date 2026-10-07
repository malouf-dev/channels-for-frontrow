// PreferencePane.h
//
// The Channels for Front Row pane in System Preferences: which Channels DVR
// server to use, found with Bonjour or typed in, and which channel collection
// to show. Each change is saved straight away (Settings.h). The plugin reads
// the settings the next time the Live TV menu opens.
//
// The pane checks the chosen server as you go: it lists the server's
// collections and counts the channels the chosen one would show.
//
// Plugin: Enabled or Disabled moves the plugin into or out of Front Row's
// plugins folder, and Uninstall removes everything. Both run the script in
// the pane's Resources (manage) as root, after an administrator's password.
// While the plugin is disabled, the other settings can't be changed and the
// pane doesn't contact the server.
//
// The view is built in code, so there's no nib to edit. The 64-bit System
// Preferences on 10.6 runs with garbage collection, so the pane is built
// with -fobjc-gc and works with or without it.

#import <PreferencePanes/PreferencePanes.h>

@interface LTVPreferencePane : NSPreferencePane {
    NSTextField *_pluginLabel;
    NSPopUpButton *_pluginPopUp;
    NSBox *_pluginSeparator;
    NSTextField *_serverLabel;
    NSButton *_automaticRadio;
    NSPopUpButton *_serverPopUp;
    NSImageView *_automaticBead;
    NSProgressIndicator *_automaticSpinner;
    NSTextField *_automaticStatus;
    NSButton *_lookAgainButton;
    NSButton *_addressRadio;
    NSTextField *_addressField;
    NSImageView *_addressBead;
    NSProgressIndicator *_addressSpinner;
    NSTextField *_addressStatus;
    NSBox *_separator;
    NSTextField *_channelsLabel;
    NSPopUpButton *_collectionPopUp;
    NSTextField *_note;
    NSTextField *_footer;
    NSButton *_uninstallButton;
    NSAlert *_alert;            // the sheet on screen, kept alive while it's up
    BOOL _pluginEnabled;        // the plugin is in Front Row's plugins folder
    NSArray *_servers;          // found with Bonjour: NSDictionary name, host, address
    int _generation;            // replies from a superseded search or check are ignored
}
@end
