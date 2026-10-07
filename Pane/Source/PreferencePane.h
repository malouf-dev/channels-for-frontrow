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
// The view is built in code, so there's no nib to edit. The 64-bit System
// Preferences on 10.6 runs with garbage collection, so the pane is built
// with -fobjc-gc and works with or without it.

#import <PreferencePanes/PreferencePanes.h>

@interface LTVPreferencePane : NSPreferencePane {
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
    NSArray *_servers;          // found with Bonjour: NSDictionary name, host, address
    int _generation;            // replies from a superseded search or check are ignored
}
@end
