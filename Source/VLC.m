// VLC.m

#import <dlfcn.h>
#import "VLC.h"

LTVLibVLC LTVlibvlc;

// Where Live TV looks for its copy of VLC 2.0.10, in order.
static NSArray *LTVVLCLocations(void)
{
    return [NSArray arrayWithObjects:
            [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/channels-for-frontrow/VLC.app"],
            @"/Library/Application Support/channels-for-frontrow/VLC.app",
            nil];
}

@implementation LTVVLC

+ (LTVVLC *)sharedEngine
{
    static LTVVLC *engine;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ engine = [[LTVVLC alloc] init]; });
    return engine;
}

- (id)init
{
    if ((self = [super init]))
        _queue = dispatch_queue_create("channels-for-frontrow.vlc", NULL);
    return self;
}

- (dispatch_queue_t)queue
{
    return _queue;
}

- (libvlc_instance_t *)instance
{
    return _instance;
}

- (NSString *)failure
{
    return _failure;
}

- (void)fail:(NSString *)reason
{
    NSLog(@"Live TV: VLC unavailable: %@", reason);
    [_failure release];
    _failure = [reason copy];
}

// Runs on the queue.
- (void)load
{
    NSString *app = nil;
    for (NSString *candidate in LTVVLCLocations()) {
        NSString *library = [candidate stringByAppendingPathComponent:@"Contents/MacOS/lib/libvlc.5.dylib"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:library]) {
            app = candidate;
            break;
        }
    }
    if (app == nil) {
        [self fail:@"Channels for Front Row needs VLC 2.0.10. Its README explains where to put it."];
        return;
    }

    // VLC's libraries find each other with @loader_path, so loading by full
    // path works. The plugins folder has to be given separately.
    NSString *macOS = [app stringByAppendingPathComponent:@"Contents/MacOS"];
    setenv("VLC_PLUGIN_PATH", [[macOS stringByAppendingPathComponent:@"plugins"] fileSystemRepresentation], 1);
    void *library = dlopen([[macOS stringByAppendingPathComponent:@"lib/libvlc.5.dylib"] fileSystemRepresentation],
                           RTLD_NOW | RTLD_LOCAL);
    if (library == NULL) {
        [self fail:[NSString stringWithFormat:@"VLC couldn't be loaded: %s", dlerror()]];
        return;
    }

    struct { void **slot; const char *name; } symbols[] = {
        { (void **)&LTVlibvlc.get_version, "libvlc_get_version" },
        { (void **)&LTVlibvlc.errmsg, "libvlc_errmsg" },
        { (void **)&LTVlibvlc.new_instance, "libvlc_new" },
        { (void **)&LTVlibvlc.media_new_location, "libvlc_media_new_location" },
        { (void **)&LTVlibvlc.media_add_option, "libvlc_media_add_option" },
        { (void **)&LTVlibvlc.media_release, "libvlc_media_release" },
        { (void **)&LTVlibvlc.media_player_new_from_media, "libvlc_media_player_new_from_media" },
        { (void **)&LTVlibvlc.media_player_release, "libvlc_media_player_release" },
        { (void **)&LTVlibvlc.media_player_play, "libvlc_media_player_play" },
        { (void **)&LTVlibvlc.media_player_stop, "libvlc_media_player_stop" },
        { (void **)&LTVlibvlc.media_player_event_manager, "libvlc_media_player_event_manager" },
        { (void **)&LTVlibvlc.event_attach, "libvlc_event_attach" },
        { (void **)&LTVlibvlc.event_detach, "libvlc_event_detach" },
        { (void **)&LTVlibvlc.video_set_callbacks, "libvlc_video_set_callbacks" },
        { (void **)&LTVlibvlc.video_set_format, "libvlc_video_set_format" },
        { (void **)&LTVlibvlc.video_set_deinterlace, "libvlc_video_set_deinterlace" },
        { (void **)&LTVlibvlc.audio_set_volume, "libvlc_audio_set_volume" },
    };
    for (size_t i = 0; i < sizeof symbols / sizeof symbols[0]; i++) {
        *symbols[i].slot = dlsym(library, symbols[i].name);
        if (*symbols[i].slot == NULL) {
            [self fail:[NSString stringWithFormat:@"This VLC has no %s. Channels for Front Row needs VLC 2.0.10.", symbols[i].name]];
            return;
        }
    }

    // --ignore-config keeps a user's own VLC preferences out of Live TV.
    const char *arguments[] = {
        "--ignore-config", "--quiet", "--intf=dummy", "--no-video-title-show",
        "--no-stats", "--no-sub-autodetect-file", "--no-snapshot-preview",
    };
    NSTimeInterval started = [NSDate timeIntervalSinceReferenceDate];
    _instance = LTVlibvlc.new_instance(sizeof arguments / sizeof arguments[0], arguments);
    if (_instance == NULL) {
        const char *error = LTVlibvlc.errmsg();
        [self fail:[NSString stringWithFormat:@"VLC didn't start: %s", error ? error : "no reason given"]];
        return;
    }
    NSLog(@"Live TV: VLC %s ready in %.2fs, from %@", LTVlibvlc.get_version(),
          [NSDate timeIntervalSinceReferenceDate] - started, app);
}

- (void)startInBackground
{
    dispatch_async(_queue, ^{
        if (_started)
            return;
        _started = YES;
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        [self load];
        [pool drain];
    });
}

@end
