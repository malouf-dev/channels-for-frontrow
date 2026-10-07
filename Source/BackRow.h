// BackRow.h
//
// Declarations for the parts of Apple's private BackRow framework that Live TV
// uses. BackRow is Front Row's UI and playback framework (Front Row 2.2.1 on
// Mac OS X 10.6.8). It ships no headers; everything here was read from the
// framework's Objective-C metadata with the scripts in tools/backrow.
//
// Classes Live TV subclasses are declared as direct NSObject subclasses with a
// padding ivar sized to the real class. The i386 runtime has fragile ivars: the
// compiler places a subclass's ivars straight after the superclass size it was
// told about, so that size must match the real one. Appliance.m checks the
// sizes at load time and refuses to run if Front Row's BackRow differs.

#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>

// Front Row only loads appliances that adopt this protocol. It adds nothing to
// NSObject's protocol.
@protocol BRApplianceProtocol <NSObject>
@end

// Real instance sizes in bytes, including isa, from `otool -ov` on BackRow.
#define BRApplianceSize            8
#define BRBaseMediaAssetSize       8
#define BRControllerSize          36
#define BRMediaMenuControllerSize 76

#define BR_PADDING(size) char _brPadding[(size) - sizeof(Class)]

// Classes Live TV only sends messages to.

@interface BRListControl : NSObject
- (void)setDatasource:(id)datasource;
- (void)reload;
@end

@interface BRHeaderControl : NSObject
- (void)setTitle:(NSString *)title;
@end

// Really a CALayer subclass. Used as a menu row.
@interface BRTextMenuItemLayer : NSObject
- (void)setTitle:(NSString *)title;
- (void)setRightJustifiedText:(NSString *)text;
- (void)setDimmed:(BOOL)dimmed;
@end

// Front Row's picture object.
@interface BRImage : NSObject
+ (BRImage *)imageWithData:(NSData *)data;
@end

// The native preview for a menu row: the asset's cover art with a reflection,
// and text below it, laid out by BRMetadataPreviewLayoutManager with Front
// Row's own margins. BRMediaMenuController shows whatever control
// -previewControlForItem: returns, and only calls -setName: on it first.
// By default the text appears after a short pause, as in Front Row's other
// menus. -setShowsMetadataImmediately: shows it straight away.
@interface BRMetadataPreviewController : NSObject
- (void)setAsset:(id)asset;
- (void)setShowsMetadataImmediately:(BOOL)immediately;
@end

// The preview's text layer. A populator fills it with -populateLayer:fromAsset:.
@interface BRMetadataLayer : NSObject
- (void)setTitle:(NSString *)title;
- (void)setSummary:(NSString *)summary;
- (void)setMetadata:(NSArray *)values withLabels:(NSArray *)labels;
@end

// The stack of screens. Pressing Menu on the remote pops the top one.
@interface BRControllerStack : NSObject
- (void)pushController:(id)controller;
- (void)popController;
- (void)swapController:(id)controller;
@end

@interface BRAlertController : NSObject
+ (id)alertOfType:(int)type titled:(NSString *)title primaryText:(NSString *)primaryText secondaryText:(NSString *)secondaryText;
@end

// A remote button press or release. -remoteAction numbers come from the jump
// table in -[BRMediaPlayerController brEventAction:].
@interface BREvent : NSObject
- (int)remoteAction;
- (int)value;      // 1 when pressed, 0 when released
@end

enum {
    BRRemoteActionVolumeUp   = 2,   // + on the Apple Remote
    BRRemoteActionVolumeDown = 3,   // - on the Apple Remote
};

@interface BREventManager : NSObject
+ (BREventManager *)sharedManager;
- (void)retriggerCurrentEvent;      // repeats the event while the button is held
@end

// Front Row's settings, including the Mac's output volume (0 to 1).
@interface BRSettingsFacade : NSObject
+ (BRSettingsFacade *)sharedInstance;
- (BOOL)volumeEnabled;
- (float)systemVolume;
- (void)setSystemVolume:(float)volume;
@end

// Posted by a player (the object) after it changes the volume. A
// BRVolumeControl attached to that player then shows its bar.
extern NSString *const kBRMediaPlayerVolumeChanged;

// Posted when the user does something. Front Row's idle timer starts again,
// so its screen saver doesn't appear. -[BRVideoPlayerController
// _suppressScreenSaver] posts it, object nil, while the player is the first
// responder, each time playback progresses.
extern NSString *const kBRUserActionNotification;

// Front Row's renderer. Each frame it asks the playback delegate
// -newFrameForTime:, calls its -drawFrameInBounds: in the renderer's OpenGL
// context, then draws the interface layers on top. Video screens also remove
// Front Row's background while video shows, and put it back when they leave.
@interface BRRenderScene : NSObject
+ (BRRenderScene *)sharedInstance;
- (void)setPlaybackDelegate:(id)delegate;
- (void)setBackgroundRemoved:(BOOL)removed;
@end

// BRVolumeControl and BRVideoPlayerLayoutManager aren't exported, so the
// linker can't resolve them. Get the classes with objc_getClass() and use
// these declarations only for the methods.

// Front Row's volume bar. -setPlayer: makes it observe the player's volume
// notifications and read -volume from it when it shows the bar.
// BRVideoPlayerLayoutManager places a control named @"volume".
@interface BRVolumeControl : NSObject
- (void)setName:(NSString *)name;
- (void)setPlayer:(id)player;
- (void)setHidden:(BOOL)hidden;
@end

// Lays out the named controls of Front Row's video screen: @"resume",
// @"transport", @"volume" and @"warning". Other sublayers are left alone.
@interface BRVideoPlayerLayoutManager : NSObject
@end

// Classes Live TV subclasses.

@interface BRAppliance : NSObject {
    BR_PADDING(BRApplianceSize);
}
- (id)applianceController;
@end

// One full screen in Front Row. It owns a Core Animation layer, which the
// controller stack sizes to the screen. BackRow draws the whole layer tree
// with CARenderer on its own render thread.
@interface BRController : NSObject {
    BR_PADDING(BRControllerSize);
}
- (id)init;
- (CALayer *)layer;
- (BRControllerStack *)stack;
- (void)addControl:(id)control;
- (void)setLayoutManager:(id)layoutManager;
- (BOOL)brEventAction:(BREvent *)event;
- (BOOL)firstResponder;             // whether this screen gets the remote's events
- (void)wasPushed;
- (void)willBePopped;
- (void)wasPopped;
@end

// A Front Row menu screen: a header, a list on the right and a preview area on
// the left. The list asks its datasource (the controller itself) for rows.
@interface BRMediaMenuController : NSObject {
    BR_PADDING(BRMediaMenuControllerSize);
}
- (id)init;
- (BRListControl *)list;
- (BRHeaderControl *)header;
- (BRControllerStack *)stack;
- (void)updatePreviewController;    // asks -previewControlForItem: again
- (long)selectedItem;
- (void)wasPushed;
- (void)willBePopped;
- (void)wasBuriedByPushingController:(id)controller;   // another screen went on top
- (void)wasExhumedByPoppingController:(id)controller;  // and came off again
@end

// A media item, as BackRow's menus and previews see it. Its defaults answer
// every question with nothing, so a subclass overrides only what it has.
@interface BRBaseMediaAsset : NSObject {
    BR_PADDING(BRBaseMediaAssetSize);
}
- (id)initWithMediaProvider:(id)provider;
@end
