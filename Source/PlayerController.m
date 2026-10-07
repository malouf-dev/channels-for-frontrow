// PlayerController.m

#import <math.h>
#import <objc/runtime.h>
#import "PlayerController.h"

// A stream that fails or ends is opened again after a second, up to this many
// times in a row. Showing a picture resets the count.
static const int LTVMaxAttempts = 3;

// Measured with tools/vlccheck on the iMac: a 500 ms network buffer gives a
// first picture 0.7 to 1.7 seconds after play on a cold channel.
static const char *LTVNetworkCaching = ":network-caching=500";

// Doubles 1080i50 to 50 frames a second, like a TV. About 78% of one core.
static const char *LTVDeinterlaceMode = "yadif2x";

// Steps in the sound's fade-in, which runs alongside the picture's.
static const int LTVSoundFadeSteps = 10;

@interface LTVPlayerController ()
- (void)playerReportedEvent:(int)type;
@end

// VLC calls this on one of its own threads.
static void LTVPlayerEvent(const libvlc_event_t *event, void *userData)
{
    LTVPlayerController *controller = userData;
    int type = event->type;
    dispatch_async(dispatch_get_main_queue(), ^{
        [controller playerReportedEvent:type];
    });
}

@implementation LTVPlayerController

- (id)initWithTitle:(NSString *)title streamURL:(NSURL *)url
{
    if ((self = [super init])) {
        _title = [title copy];
        _streamURL = [url retain];

        // Same layout and volume bar as -[BRVideoPlayerController init] and
        // -_addVolumeControl. The player is attached while the screen is up.
        [self setLayoutManager:[[[objc_getClass("BRVideoPlayerLayoutManager") alloc] init] autorelease]];
        if ([[BRSettingsFacade sharedInstance] volumeEnabled]) {
            _volumeControl = [[objc_getClass("BRVolumeControl") alloc] init];
            [_volumeControl setName:@"volume"];
            [_volumeControl setHidden:YES];
            [self addControl:_volumeControl];
        }
    }
    return self;
}

// Runs after the VLC queue has stopped the player, because every block on
// that queue keeps this controller alive until it finishes.
- (void)dealloc
{
    [_statusLayer release];
    [_volumeControl setPlayer:nil];
    [_volumeControl release];
    [_title release];
    [_streamURL release];
    [super dealloc];
}

#pragma mark Status text

// One line of centred text, used while the stream loads or after it fails.
- (void)showStatus:(NSString *)text
{
    if (_statusLayer == nil) {
        CGRect bounds = [[self layer] bounds];
        _statusLayer = [[CATextLayer alloc] init];
        [_statusLayer setFont:@"LucidaGrande"];
        [_statusLayer setFontSize:36.0f];
        [_statusLayer setForegroundColor:CGColorGetConstantColor(kCGColorWhite)];
        [_statusLayer setAlignmentMode:kCAAlignmentCenter];
        [_statusLayer setFrame:CGRectMake(0.0f, CGRectGetMidY(bounds) - 30.0f, bounds.size.width, 60.0f)];
        [[self layer] addSublayer:_statusLayer];
    }
    [_statusLayer setString:text];
}

- (void)hideStatus
{
    [_statusLayer removeFromSuperlayer];
    [_statusLayer release];
    _statusLayer = nil;
}

#pragma mark Playback

- (void)startPlayer
{
    _attempts++;
    _requestedAt = [NSDate timeIntervalSinceReferenceDate];
    [_renderer waitForFirstPicture];
    int generation = ++_generation;

    LTVVLC *engine = [LTVVLC sharedEngine];
    [engine startInBackground];
    const char *location = [[_streamURL absoluteString] UTF8String];
    char *locationCopy = strdup(location);
    dispatch_async([engine queue], ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        if ([engine instance] == NULL) {
            NSString *reason = [engine failure];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self showStatus:reason];
            });
        } else if (_player == NULL) {
            libvlc_media_t *media = LTVlibvlc.media_new_location([engine instance], locationCopy);
            LTVlibvlc.media_add_option(media, LTVNetworkCaching);
            _player = LTVlibvlc.media_player_new_from_media(media);
            _playerGeneration = generation;
            LTVlibvlc.media_release(media);
            // Silent until the picture is shown, then faded in with it.
            LTVlibvlc.audio_set_volume(_player, 0);
            [_renderer attachToPlayer:_player];
            LTVlibvlc.video_set_deinterlace(_player, LTVDeinterlaceMode);
            libvlc_event_manager_t *events = LTVlibvlc.media_player_event_manager(_player);
            LTVlibvlc.event_attach(events, libvlc_MediaPlayerEncounteredError, LTVPlayerEvent, self);
            LTVlibvlc.event_attach(events, libvlc_MediaPlayerEndReached, LTVPlayerEvent, self);
            LTVlibvlc.media_player_play(_player);
        }
        free(locationCopy);
        [pool drain];
    });
}

- (void)stopPlayer
{
    dispatch_async([[LTVVLC sharedEngine] queue], ^{
        if (_player == NULL)
            return;
        libvlc_event_manager_t *events = LTVlibvlc.media_player_event_manager(_player);
        LTVlibvlc.event_detach(events, libvlc_MediaPlayerEncounteredError, LTVPlayerEvent, self);
        LTVlibvlc.event_detach(events, libvlc_MediaPlayerEndReached, LTVPlayerEvent, self);
        NSTimeInterval started = [NSDate timeIntervalSinceReferenceDate];
        LTVlibvlc.media_player_stop(_player);
        LTVlibvlc.media_player_release(_player);
        _player = NULL;
        NSLog(@"Live TV: %@ stopped in %.2fs", _title, [NSDate timeIntervalSinceReferenceDate] - started);
    });
}

// Ramps VLC's own volume from silent to normal over the picture's fade-in.
// The Mac's volume, which + and - change, isn't touched. A step that arrives
// after the player has been replaced, by a retry, does nothing.
- (void)fadeInSound
{
    int generation = _generation;
    for (int step = 1; step <= LTVSoundFadeSteps; step++) {
        int volume = 100 * step / LTVSoundFadeSteps;
        dispatch_time_t when = dispatch_time(DISPATCH_TIME_NOW,
                                             (int64_t)(LTVFadeInTime * NSEC_PER_SEC * step / LTVSoundFadeSteps));
        dispatch_after(when, [[LTVVLC sharedEngine] queue], ^{
            if (_player && _playerGeneration == generation)
                LTVlibvlc.audio_set_volume(_player, volume);
        });
    }
}

// Front Row's own video screens do the same: put their drawer in the
// renderer's video slot and remove Front Row's background behind it.
- (void)rendererShowedFirstPicture:(LTVVideoRenderer *)renderer
{
    if (_closing)
        return;
    NSLog(@"Live TV: %@ shown after %.2fs", _title, [NSDate timeIntervalSinceReferenceDate] - _requestedAt);
    _attempts = 0;
    if (!_showingVideo) {
        _showingVideo = YES;
        [[BRRenderScene sharedInstance] setPlaybackDelegate:_renderer];
        [[BRRenderScene sharedInstance] setBackgroundRemoved:YES];
    }
    [self hideStatus];
    [self fadeInSound];
}

- (void)playerReportedEvent:(int)type
{
    if (_closing)
        return;
    NSLog(@"Live TV: %@ %s (attempt %d)", _title,
          type == libvlc_MediaPlayerEndReached ? "stream ended" : "couldn't be played", _attempts);
    [self stopPlayer];
    if (_attempts < LTVMaxAttempts) {
        [self showStatus:[NSString stringWithFormat:@"Loading %@", _title]];
        [self performSelector:@selector(startPlayer) withObject:nil afterDelay:1.0];
    } else {
        [self showStatus:@"This channel couldn't be played."];
    }
}

#pragma mark Screen

- (void)wasPushed
{
    [super wasPushed];
    // The volume control retains its player, so attach only while on screen.
    [_volumeControl setPlayer:self];

    // Pictures are made at the screen's size.
    CGRect bounds = [[self layer] bounds];
    if (bounds.size.width < 2.0f || bounds.size.height < 2.0f)
        bounds = CGRectMake(0.0f, 0.0f, 1920.0f, 1080.0f);
    _renderer = [LTVVideoRenderer sharedRendererWithWidth:(unsigned)bounds.size.width & ~1u
                                                   height:(unsigned)bounds.size.height];
    [_renderer setTarget:self firstPictureAction:@selector(rendererShowedFirstPicture:)];

    [self showStatus:[NSString stringWithFormat:@"Loading %@", _title]];
    [self startPlayer];
}

- (void)willBePopped
{
    _closing = YES;
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [_volumeControl setPlayer:nil];
    [_renderer setTarget:nil firstPictureAction:NULL];
    if (_showingVideo) {
        [[BRRenderScene sharedInstance] setPlaybackDelegate:nil];
        [[BRRenderScene sharedInstance] setBackgroundRemoved:NO];
    }
    [self stopPlayer];
    [self hideStatus];
    [super willBePopped];
}

#pragma mark Volume

// Read by the volume control when it shows its bar.
- (float)volume
{
    return [[BRSettingsFacade sharedInstance] systemVolume];
}

// Same 1/16 steps as -[BRMediaPlayer volumeUp] and -volumeDown.
- (void)changeVolumeBy:(int)steps
{
    BRSettingsFacade *settings = [BRSettingsFacade sharedInstance];
    if (![settings volumeEnabled])
        return;
    float sixteenths = [settings systemVolume] * 16.0f;
    sixteenths = (steps > 0) ? floorf(sixteenths) + 1.0f : ceilf(sixteenths) - 1.0f;
    [settings setSystemVolume:fmaxf(0.0f, fminf(1.0f, sixteenths / 16.0f))];
    [[NSNotificationCenter defaultCenter] postNotificationName:kBRMediaPlayerVolumeChanged object:self];
}

- (BOOL)brEventAction:(BREvent *)event
{
    int action = [event remoteAction];
    if (action == BRRemoteActionVolumeUp || action == BRRemoteActionVolumeDown) {
        if ([event value] == 1) {
            [self changeVolumeBy:(action == BRRemoteActionVolumeUp) ? 1 : -1];
            [[BREventManager sharedManager] retriggerCurrentEvent];
        }
        return YES;
    }
    return [super brEventAction:event];
}

@end
