// PreferencePane.m
//
// Layout follows the approved mockups (scratch/mockups/live-tv-pane.html and
// channels-pane-toggle-uninstall.html): right-aligned labels in a 160-point
// column, controls from x = 180, and a status line under whichever server
// choice is on. Status lines that are empty take no space. Uninstall sits at
// the bottom right, beside the footer.

#import "PreferencePane.h"
#import "ChannelsDVR.h"
#import "Discovery.h"
#import "Settings.h"

static const CGFloat LTVPaneWidth = 668.0;
static const CGFloat LTVPaneHeight = 390.0;
static const CGFloat LTVLabelWidth = 170.0;
static const CGFloat LTVControlsX = 180.0;
static const CGFloat LTVIndent = 20.0;
static const CGFloat LTVPopUpWidth = 264.0;
static const CGFloat LTVPluginPopUpWidth = 130.0;

// Where Front Row loads the plugin from. The manage script moves it out to
// /Library/Application Support/channels-for-frontrow while it's disabled.
static NSString *const LTVPluginPath =
    @"/System/Library/CoreServices/Front Row.app/Contents/PlugIns/ChannelsForFrontRow.frappliance";

static NSString *const LTVFooterEnabled = @"Changes apply the next time you open Live TV in Front Row.";
static NSString *const LTVFooterDisabled = @"Front Row doesn't load Live TV while it's disabled.";

typedef enum {
    LTVStatusNone,
    LTVStatusWorking,
    LTVStatusGood,
    LTVStatusBad,
} LTVStatus;

// Lays subviews out from the top down.
@interface LTVFlippedView : NSView
@end

@implementation LTVFlippedView
- (BOOL)isFlipped { return YES; }
@end

static NSTextField *LTVText(NSString *text, BOOL small, NSTextAlignment alignment)
{
    NSTextField *field = [[[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 100, 17)] autorelease];
    [field setStringValue:text];
    [field setBezeled:NO];
    [field setDrawsBackground:NO];
    [field setEditable:NO];
    [field setSelectable:NO];
    [field setAlignment:alignment];
    [field setFont:[NSFont systemFontOfSize:small ? [NSFont smallSystemFontSize] : [NSFont systemFontSize]]];
    if (small)
        [field setTextColor:[NSColor colorWithCalibratedWhite:0.3 alpha:1.0]];
    return field;
}

static NSButton *LTVRadio(NSString *title, id target, SEL action)
{
    NSButton *radio = [[[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 200, 18)] autorelease];
    [radio setButtonType:NSRadioButton];
    [radio setTitle:title];
    [radio setTarget:target];
    [radio setAction:action];
    [radio sizeToFit];
    return radio;
}

static NSPopUpButton *LTVPopUp(id target, SEL action)
{
    NSPopUpButton *popUp = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, LTVPopUpWidth, 26) pullsDown:NO] autorelease];
    [popUp setTarget:target];
    [popUp setAction:action];
    return popUp;
}

static NSBox *LTVSeparator(void)
{
    NSBox *separator = [[[NSBox alloc] initWithFrame:NSMakeRect(0, 0, 100, 1)] autorelease];
    [separator setBoxType:NSBoxSeparator];
    return separator;
}

// A string literal for AppleScript source.
static NSString *LTVAppleScriptString(NSString *text)
{
    text = [text stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    text = [text stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    return [NSString stringWithFormat:@"\"%@\"", text];
}

static NSImageView *LTVBead(void)
{
    NSImageView *bead = [[[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, 12, 12)] autorelease];
    [bead setImageScaling:NSImageScaleProportionallyUpOrDown];
    return bead;
}

static NSProgressIndicator *LTVSpinner(void)
{
    NSProgressIndicator *spinner = [[[NSProgressIndicator alloc] initWithFrame:NSMakeRect(0, 0, 16, 16)] autorelease];
    [spinner setStyle:NSProgressIndicatorSpinningStyle];
    [spinner setControlSize:NSSmallControlSize];
    [spinner setDisplayedWhenStopped:NO];
    return spinner;
}

@interface LTVPreferencePane ()
- (void)layoutView;
- (void)findServers;
- (void)checkSelectedServer;
- (void)checkAddress;
@end

@implementation LTVPreferencePane

- (void)dealloc
{
    [_alert release];
    [_servers release];
    [super dealloc];
}

#pragma mark Building the view

- (NSView *)loadMainView
{
    NSView *view = [[[LTVFlippedView alloc] initWithFrame:NSMakeRect(0, 0, LTVPaneWidth, LTVPaneHeight)] autorelease];

    _pluginLabel = LTVText(@"Plugin:", NO, NSRightTextAlignment);
    _pluginPopUp = LTVPopUp(self, @selector(pluginChosen:));
    [_pluginPopUp addItemWithTitle:@"Enabled"];
    [_pluginPopUp addItemWithTitle:@"Disabled"];
    _pluginSeparator = LTVSeparator();

    _serverLabel = LTVText(@"Channels DVR server:", NO, NSRightTextAlignment);
    _automaticRadio = LTVRadio(@"Find automatically", self, @selector(radioChanged:));
    _serverPopUp = LTVPopUp(self, @selector(serverChosen:));
    _automaticBead = LTVBead();
    _automaticSpinner = LTVSpinner();
    _automaticStatus = LTVText(@"", YES, NSLeftTextAlignment);
    _lookAgainButton = [[[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 90, 19)] autorelease];
    [_lookAgainButton setBezelStyle:NSRoundedBezelStyle];
    [[_lookAgainButton cell] setControlSize:NSSmallControlSize];
    [_lookAgainButton setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
    [_lookAgainButton setTitle:@"Look Again"];
    [_lookAgainButton setTarget:self];
    [_lookAgainButton setAction:@selector(lookAgain:)];
    [_lookAgainButton sizeToFit];

    _addressRadio = LTVRadio(@"Use this address:", self, @selector(radioChanged:));
    _addressField = [[[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, LTVPopUpWidth - 6, 22)] autorelease];
    [[_addressField cell] setPlaceholderString:@"such as 192.168.0.20:8089"];
    [[_addressField cell] setSendsActionOnEndEditing:YES];
    [_addressField setTarget:self];
    [_addressField setAction:@selector(addressEntered:)];
    _addressBead = LTVBead();
    _addressSpinner = LTVSpinner();
    _addressStatus = LTVText(@"", YES, NSLeftTextAlignment);

    _separator = LTVSeparator();

    _channelsLabel = LTVText(@"Channels:", NO, NSRightTextAlignment);
    _collectionPopUp = LTVPopUp(self, @selector(collectionChosen:));
    _note = LTVText(@"Live TV shows the channels in this collection, in the order set in Channels DVR. "
                    @"Choose All Channels to show every channel.", YES, NSLeftTextAlignment);
    [[_note cell] setWraps:YES];
    _footer = LTVText(LTVFooterEnabled, YES, NSLeftTextAlignment);
    _uninstallButton = [[[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 100, 32)] autorelease];
    [_uninstallButton setBezelStyle:NSRoundedBezelStyle];
    [_uninstallButton setTitle:@"Uninstall…"];
    [_uninstallButton setTarget:self];
    [_uninstallButton setAction:@selector(uninstall:)];
    [_uninstallButton sizeToFit];

    NSView *views[] = {
        _pluginLabel, _pluginPopUp, _pluginSeparator, _serverLabel, _automaticRadio, _serverPopUp, _automaticBead, _automaticSpinner, _automaticStatus,
        _lookAgainButton, _addressRadio, _addressField, _addressBead, _addressSpinner, _addressStatus,
        _separator, _channelsLabel, _collectionPopUp, _note, _footer, _uninstallButton,
    };
    for (size_t i = 0; i < sizeof views / sizeof views[0]; i++)
        [view addSubview:views[i]];

    [self setMainView:view];
    [self mainViewDidLoad];
    return view;
}

// Places one status line: a bead or spinner, then its text, then any button.
- (CGFloat)placeStatusWithBead:(NSImageView *)bead spinner:(NSProgressIndicator *)spinner
                          text:(NSTextField *)text button:(NSButton *)button atY:(CGFloat)y
{
    BOOL shown = [[text stringValue] length] > 0;
    [bead setHidden:!shown || [bead image] == nil];
    [text setHidden:!shown];
    if (!shown) {
        [button setHidden:YES];
        return y;
    }
    CGFloat x = LTVControlsX + LTVIndent + 3;
    [bead setFrame:NSMakeRect(x, y + 2, 12, 12)];
    [spinner setFrame:NSMakeRect(x - 2, y, 16, 16)];
    [text sizeToFit];
    NSRect frame = [text frame];
    frame.origin = NSMakePoint(x + 16, y + 1);
    [text setFrame:frame];
    if (button && ![button isHidden])
        [button setFrameOrigin:NSMakePoint(NSMaxX(frame) + 8, y - 2)];
    return y + 24;
}

- (void)layoutView
{
    CGFloat y = 26;
    [_pluginLabel setFrame:NSMakeRect(0, y + 4, LTVLabelWidth, 17)];
    [_pluginPopUp setFrame:NSMakeRect(LTVControlsX - 3, y, LTVPluginPopUpWidth, 26)];
    y += 38;
    [_pluginSeparator setFrame:NSMakeRect(40, y, LTVPaneWidth - 80, 1)];
    y += 22;
    [_serverLabel setFrame:NSMakeRect(0, y + 1, LTVLabelWidth, 17)];
    [_automaticRadio setFrameOrigin:NSMakePoint(LTVControlsX, y)];
    y += 26;
    [_serverPopUp setFrame:NSMakeRect(LTVControlsX + LTVIndent - 3, y, LTVPopUpWidth, 26)];
    y += 32;
    y = [self placeStatusWithBead:_automaticBead spinner:_automaticSpinner text:_automaticStatus
                           button:_lookAgainButton atY:y];
    [_addressRadio setFrameOrigin:NSMakePoint(LTVControlsX, y)];
    y += 26;
    [_addressField setFrame:NSMakeRect(LTVControlsX + LTVIndent, y, LTVPopUpWidth - 6, 22)];
    y += 30;
    y = [self placeStatusWithBead:_addressBead spinner:_addressSpinner text:_addressStatus button:nil atY:y];
    y += 12;
    [_separator setFrame:NSMakeRect(40, y, LTVPaneWidth - 80, 1)];
    y += 22;
    [_channelsLabel setFrame:NSMakeRect(0, y + 4, LTVLabelWidth, 17)];
    [_collectionPopUp setFrame:NSMakeRect(LTVControlsX - 3, y, LTVPopUpWidth, 26)];
    y += 32;
    [_note setFrame:NSMakeRect(LTVControlsX, y, 380, 30)];

    // A rounded button's frame is 6 points wider than its bezel on each side.
    NSRect button = [_uninstallButton frame];
    [_uninstallButton setFrameOrigin:NSMakePoint(LTVPaneWidth - 40 + 6 - button.size.width, LTVPaneHeight - 43)];
    [_footer setFrame:NSMakeRect(40, LTVPaneHeight - 34, LTVPaneWidth - 80 - button.size.width, 14)];
}

#pragma mark Status lines

- (void)showStatus:(LTVStatus)status text:(NSString *)text automatic:(BOOL)automatic
{
    NSImageView *bead = automatic ? _automaticBead : _addressBead;
    NSProgressIndicator *spinner = automatic ? _automaticSpinner : _addressSpinner;
    NSTextField *field = automatic ? _automaticStatus : _addressStatus;

    // Only the chosen option has a status line.
    [(automatic ? _addressStatus : _automaticStatus) setStringValue:@""];
    [(automatic ? _addressSpinner : _automaticSpinner) stopAnimation:nil];
    [_lookAgainButton setHidden:YES];

    if (status == LTVStatusGood)
        [bead setImage:[NSImage imageNamed:NSImageNameStatusAvailable]];
    else if (status == LTVStatusBad)
        [bead setImage:[NSImage imageNamed:NSImageNameStatusUnavailable]];
    else
        [bead setImage:nil];
    if (status == LTVStatusWorking)
        [spinner startAnimation:nil];
    else
        [spinner stopAnimation:nil];
    [field setStringValue:text ? text : @""];
    [self layoutView];
}

#pragma mark Collections

// All Channels, a divider, then the server's collections. A chosen
// collection the server doesn't have stays listed, so it isn't changed
// without asking.
- (void)fillCollections:(NSArray *)names chosen:(NSString *)chosen
{
    [_collectionPopUp removeAllItems];
    [_collectionPopUp addItemWithTitle:@"All Channels"];
    [[_collectionPopUp menu] addItem:[NSMenuItem separatorItem]];
    for (NSString *name in names)
        [_collectionPopUp addItemWithTitle:name];
    if (chosen && [_collectionPopUp itemWithTitle:chosen] == nil)
        [_collectionPopUp addItemWithTitle:chosen];
    [_collectionPopUp selectItemWithTitle:chosen ? chosen : @"All Channels"];
    [_collectionPopUp setEnabled:YES];
}

// While there's no server to ask, show the saved choice, greyed out.
- (void)disableCollections
{
    NSString *chosen = LTVReadSetting(LTVSettingChannelCollection);
    [_collectionPopUp removeAllItems];
    [_collectionPopUp addItemWithTitle:chosen ? chosen : @"All Channels"];
    [_collectionPopUp setEnabled:NO];
}

#pragma mark Checking a server

- (NSString *)typedAddress
{
    NSString *address = [[_addressField stringValue] stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([address length] == 0)
        return nil;
    if ([address rangeOfString:@":"].location == NSNotFound)
        address = [address stringByAppendingString:@":8089"];    // Channels DVR's usual port
    return address;
}

- (void)server:(NSString *)name automatic:(BOOL)automatic collections:(NSArray *)collections
      channels:(NSArray *)channels collection:(NSString *)collection
{
    if (collections == nil) {
        [self showStatus:LTVStatusBad
                    text:automatic ? [NSString stringWithFormat:@"Can't connect to %@.", name]
                                   : @"Can't reach a Channels DVR server at this address."
               automatic:automatic];
        [self disableCollections];
        return;
    }
    [self fillCollections:collections chosen:collection];

    NSString *connected = automatic ? [NSString stringWithFormat:@"Connected to %@.", name] : @"Connected.";
    NSUInteger count = [channels count];
    NSString *what;
    if (channels == nil)
        what = [NSString stringWithFormat:@"%@ isn't a collection on this server.", collection];
    else if (collection)
        what = [NSString stringWithFormat:@"%lu %@ in %@.", (unsigned long)count, count == 1 ? @"channel" : @"channels", collection];
    else
        what = [NSString stringWithFormat:@"%lu %@.", (unsigned long)count, count == 1 ? @"channel" : @"channels"];
    [self showStatus:channels ? LTVStatusGood : LTVStatusBad
                text:[NSString stringWithFormat:@"%@ %@", connected, what]
           automatic:automatic];
}

// Lists the server's collections and counts the channels the chosen one shows.
- (void)checkServerAt:(NSString *)address name:(NSString *)name automatic:(BOOL)automatic
{
    int generation = ++_generation;
    NSString *collection = LTVReadSetting(LTVSettingChannelCollection);
    [self showStatus:LTVStatusWorking
                text:name ? [NSString stringWithFormat:@"Connecting to %@…", name] : @"Connecting…"
           automatic:automatic];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        LTVChannelsDVR *server = [[[LTVChannelsDVR alloc] initWithServer:address] autorelease];
        NSArray *collections = [server collectionNames:NULL];
        NSArray *channels = collections ? [server channelsInCollection:collection error:NULL] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation == _generation)
                [self server:name automatic:automatic collections:collections channels:channels collection:collection];
        });
        [pool drain];
    });
}

- (void)checkSelectedServer
{
    NSInteger index = [_serverPopUp indexOfSelectedItem];
    if (index < 0 || index >= (NSInteger)[_servers count])
        return;
    NSDictionary *server = [_servers objectAtIndex:index];
    [self checkServerAt:[server objectForKey:@"address"] name:[server objectForKey:@"name"] automatic:YES];
}

- (void)checkAddress
{
    NSString *address = [self typedAddress];
    if (address == nil) {
        ++_generation;
        [self showStatus:LTVStatusNone text:nil automatic:NO];
        [self disableCollections];
        return;
    }
    [self checkServerAt:address name:nil automatic:NO];
}

#pragma mark Finding servers

- (void)serversFound:(NSArray *)servers
{
    [_servers release];
    _servers = [servers copy];
    [_serverPopUp removeAllItems];
    if ([servers count] == 0) {
        [_serverPopUp addItemWithTitle:@"No servers found"];
        [_serverPopUp setEnabled:NO];
        [self showStatus:LTVStatusBad text:@"No Channels DVR server found on this network." automatic:YES];
        [_lookAgainButton setHidden:NO];
        [self layoutView];
        [self disableCollections];
        return;
    }
    for (NSDictionary *server in servers)
        [_serverPopUp addItemWithTitle:[server objectForKey:@"name"]];
    NSString *chosen = LTVReadSetting(LTVSettingChannelsServerName);
    if (chosen && [_serverPopUp itemWithTitle:chosen])
        [_serverPopUp selectItemWithTitle:chosen];
    [_serverPopUp setEnabled:YES];
    [self checkSelectedServer];
}

- (void)findServers
{
    int generation = ++_generation;
    [_serverPopUp removeAllItems];
    [_serverPopUp addItemWithTitle:@"Looking…"];
    [_serverPopUp setEnabled:NO];
    [self showStatus:LTVStatusWorking text:@"Looking for Channels DVR servers on this network…" automatic:YES];
    [self disableCollections];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSArray *servers = LTVFindChannelsServers(3.0);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation == _generation)
                [self serversFound:servers];
        });
        [pool drain];
    });
}

#pragma mark Choices

- (void)useAutomatic:(BOOL)automatic
{
    [_automaticRadio setState:automatic ? NSOnState : NSOffState];
    [_addressRadio setState:automatic ? NSOffState : NSOnState];
    [_addressField setEnabled:!automatic];
    if (automatic) {
        [self findServers];
    } else {
        [_serverPopUp setEnabled:NO];
        [self checkAddress];
    }
}

// While the plugin is disabled: the saved choices, greyed out, without
// contacting the server.
- (void)showSettingsDisabled
{
    ++_generation;      // a search or check still running is ignored
    NSString *address = LTVReadSetting(LTVSettingChannelsServer);
    NSString *name = LTVReadSetting(LTVSettingChannelsServerName);
    [_automaticRadio setState:address ? NSOffState : NSOnState];
    [_addressRadio setState:address ? NSOnState : NSOffState];
    [_serverPopUp removeAllItems];
    if (name)
        [_serverPopUp addItemWithTitle:name];
    [_serverPopUp setEnabled:NO];
    [_addressField setEnabled:NO];
    [_automaticSpinner stopAnimation:nil];
    [_addressSpinner stopAnimation:nil];
    [_automaticStatus setStringValue:@""];
    [_addressStatus setStringValue:@""];
    [self disableCollections];
    [self layoutView];
}

// Each time the pane is shown, and after the plugin is enabled or disabled,
// start from what's on disk and the saved settings.
- (void)didSelect
{
    _pluginEnabled = [[NSFileManager defaultManager] fileExistsAtPath:LTVPluginPath];
    [_pluginPopUp selectItemAtIndex:_pluginEnabled ? 0 : 1];
    [_automaticRadio setEnabled:_pluginEnabled];
    [_addressRadio setEnabled:_pluginEnabled];
    NSColor *label = _pluginEnabled ? [NSColor controlTextColor] : [NSColor disabledControlTextColor];
    [_serverLabel setTextColor:label];
    [_channelsLabel setTextColor:label];
    [_note setTextColor:_pluginEnabled ? [NSColor colorWithCalibratedWhite:0.3 alpha:1.0] : label];
    [_footer setStringValue:_pluginEnabled ? LTVFooterEnabled : LTVFooterDisabled];

    NSString *address = LTVReadSetting(LTVSettingChannelsServer);
    [_addressField setStringValue:address ? address : @""];
    if (_pluginEnabled)
        [self useAutomatic:address == nil];
    else
        [self showSettingsDisabled];
}

- (void)radioChanged:(id)sender
{
    BOOL automatic = (sender == _automaticRadio);
    LTVWriteSetting(LTVSettingChannelsServer, automatic ? nil : [self typedAddress]);
    [self useAutomatic:automatic];
    if (!automatic)
        [[_addressField window] makeFirstResponder:_addressField];
}

- (void)serverChosen:(id)sender
{
    LTVWriteSetting(LTVSettingChannelsServerName, [_serverPopUp titleOfSelectedItem]);
    [self checkSelectedServer];
}

- (void)addressEntered:(id)sender
{
    if ([_addressRadio state] != NSOnState)
        return;
    LTVWriteSetting(LTVSettingChannelsServer, [self typedAddress]);
    [self checkAddress];
}

- (void)collectionChosen:(id)sender
{
    BOOL all = [_collectionPopUp indexOfSelectedItem] == 0;
    LTVWriteSetting(LTVSettingChannelCollection, all ? nil : [_collectionPopUp titleOfSelectedItem]);
    if ([_automaticRadio state] == NSOnState)
        [self checkSelectedServer];
    else
        [self checkAddress];
}

- (void)lookAgain:(id)sender
{
    [self findServers];
}

#pragma mark Enabling, disabling and uninstalling

// Runs Resources/manage as root. AppleScript asks for an administrator's
// password, in a window that Mac OS X draws. Returns nil when it worked, an
// empty string when the password was cancelled, or what went wrong.
- (NSString *)runManage:(NSString *)action pane:(NSString *)pane
{
    NSString *script = [[self bundle] pathForResource:@"manage" ofType:nil];
    if (script == nil)
        return @"The pane is missing its manage script.";
    NSMutableString *source = [NSMutableString stringWithFormat:@"do shell script \"/bin/sh \" & quoted form of %@ & \" %@\"",
                               LTVAppleScriptString(script), action];
    if (pane)
        [source appendFormat:@" & \" \" & quoted form of %@", LTVAppleScriptString(pane)];
    [source appendString:@" with administrator privileges"];

    NSDictionary *error = nil;
    NSAppleScript *appleScript = [[[NSAppleScript alloc] initWithSource:source] autorelease];
    if ([appleScript executeAndReturnError:&error])
        return nil;
    if ([[error objectForKey:NSAppleScriptErrorNumber] intValue] == userCanceledErr)
        return @"";
    NSString *message = [error objectForKey:NSAppleScriptErrorMessage];
    return [message length] ? message : @"No reason was given.";
}

// One sheet at a time. didEnd, if any, is sent as
// -sheetDidEnd:returnCode:contextInfo: is, after the sheet has gone.
- (void)showSheet:(NSString *)title text:(NSString *)text buttons:(NSArray *)buttons didEnd:(SEL)didEnd
{
    [_alert release];
    _alert = [[NSAlert alloc] init];
    [_alert setMessageText:title];
    [_alert setInformativeText:text];
    for (NSString *button in buttons)
        [_alert addButtonWithTitle:button];
    NSString *icon = [[self bundle] pathForImageResource:@"ChannelsForFrontRow"];
    if (icon)
        [_alert setIcon:[[[NSImage alloc] initWithContentsOfFile:icon] autorelease]];
    [_alert beginSheetModalForWindow:[[self mainView] window] modalDelegate:self didEndSelector:didEnd contextInfo:NULL];
}

- (void)pluginChosen:(id)sender
{
    BOOL enable = ([_pluginPopUp indexOfSelectedItem] == 0);
    if (enable == _pluginEnabled)
        return;
    NSString *failure = [self runManage:enable ? @"enable" : @"disable" pane:nil];
    if ([failure length])
        [self showSheet:enable ? @"Live TV couldn't be enabled." : @"Live TV couldn't be disabled."
                   text:failure buttons:[NSArray arrayWithObject:@"OK"] didEnd:NULL];
    [self didSelect];
}

// Cancel is the first button, so Return and Escape both cancel.
- (void)uninstall:(id)sender
{
    [self showSheet:@"Uninstall Channels for Front Row?"
               text:@"This removes Live TV from Front Row, this preference pane and the copy of VLC that "
                    @"Live TV uses. Your settings are removed too.\n\nYou'll be asked for an administrator's password."
            buttons:[NSArray arrayWithObjects:@"Cancel", @"Uninstall", nil]
             didEnd:@selector(uninstallSheetDidEnd:returnCode:contextInfo:)];
}

// A sheet is still attached while its didEnd runs, and System Preferences
// ignores -terminate: while a sheet is up. So each didEnd orders its sheet
// out and does the rest on the next turn of the run loop.
- (void)uninstallSheetDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
    [[alert window] orderOut:nil];
    if (returnCode == NSAlertSecondButtonReturn)
        [self performSelector:@selector(finishUninstall) withObject:nil afterDelay:0.0];
}

- (void)finishUninstall
{
    ++_generation;
    NSString *failure = [self runManage:@"uninstall" pane:[[self bundle] bundlePath]];
    if (failure && [failure length] == 0)
        return;
    if (failure) {
        [self showSheet:@"Channels for Front Row couldn't be uninstalled." text:failure
                buttons:[NSArray arrayWithObject:@"OK"] didEnd:NULL];
        return;
    }

    // The settings are this user's own, so they need no password.
    LTVWriteSetting(LTVSettingChannelsServer, nil);
    LTVWriteSetting(LTVSettingChannelsServerName, nil);
    LTVWriteSetting(LTVSettingChannelCollection, nil);
    [[NSFileManager defaultManager] removeItemAtPath:[NSHomeDirectory() stringByAppendingPathComponent:
                                                      @"Library/Preferences/channels-for-frontrow.plist"] error:NULL];

    [self showSheet:@"Channels for Front Row is uninstalled."
               text:@"System Preferences will quit, so the pane disappears from it."
            buttons:[NSArray arrayWithObject:@"Quit"]
             didEnd:@selector(uninstalledSheetDidEnd:returnCode:contextInfo:)];
}

- (void)uninstalledSheetDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
    [[alert window] orderOut:nil];
    [NSApp performSelector:@selector(terminate:) withObject:nil afterDelay:0.0];
}

@end
