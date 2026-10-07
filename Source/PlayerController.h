// PlayerController.h
//
// Full-screen player for one live channel. It plays the channel's untouched
// stream from Channels DVR with VLC's engine. The pictures are drawn by
// LTVVideoRenderer, which sits in Front Row's video slot while a picture is
// showing. Pressing Menu on the remote pops the screen and stops the stream.
//
// Each stream starts hidden and silent. Once the renderer shows the picture,
// with its fade-in from black, the sound fades in over the same time.
//
// + and - change the Mac's volume and show Front Row's volume bar, as in
// Front Row's own player. For the bar, this controller stands in for the
// player: it posts kBRMediaPlayerVolumeChanged and answers -volume.

#import "BackRow.h"
#import "VideoRenderer.h"
#import "VLC.h"

@interface LTVPlayerController : BRController {
    NSString *_title;
    NSURL *_streamURL;
    LTVVideoRenderer *_renderer;
    CATextLayer *_statusLayer;
    BRVolumeControl *_volumeControl;
    libvlc_media_player_t *_player;     // touched only on the VLC queue
    int _playerGeneration;              // which start made _player; VLC queue only
    int _generation;                    // counts starts; main thread only
    int _attempts;
    BOOL _closing;
    BOOL _showingVideo;
    NSTimeInterval _requestedAt;
}
- (id)initWithTitle:(NSString *)title streamURL:(NSURL *)url;
@end
