// ChannelMenuController.h
//
// The Live TV menu: one row per channel in the chosen Channels DVR channel
// collection, in the collection's order. Highlighting a channel previews the
// programme on now, with its picture, summary and what's on next. Selecting
// it plays it.
//
// The channel list loads each time Live TV opens. The guide loads after it,
// and reloads in the background once it's over 30 minutes old: checked when
// you come back from a channel and a second after each minute. The minute
// check also redraws the highlighted preview when its programme ends.
//
// Settings come from Live TV's preference pane (Settings.h).

#import "BackRow.h"
#import "ChannelsDVR.h"

@interface LTVChannelMenuController : BRMediaMenuController {
    LTVChannelsDVR *_server;
    NSArray *_channels;             // NSDictionary: number, name, logo. nil until loaded
    NSDictionary *_guide;           // channel number to airings. nil until loaded
    NSString *_message;             // the only row when there are no channels to show
    NSMutableDictionary *_images;   // picture URL to BRImage
    NSMutableSet *_imagesLoading;   // picture URLs being downloaded
    NSDate *_guideLoadedAt;
    BOOL _guideLoading;
    NSDate *_previewChangesAt;      // when the shown preview goes out of date
    BOOL _ticking;                  // a minute check is scheduled
    BOOL _buried;                   // a channel's player is on top
    BOOL _leaving;                  // Live TV is being left
}
@end
