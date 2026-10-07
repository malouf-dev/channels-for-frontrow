// VLC.h
//
// Live TV plays channels with VLC's engine, libvlc, from a separate copy of
// VLC 2.0.10. That's VideoLAN's last 32-bit Intel build, and Front Row only
// runs 32-bit code. libvlc is opened with dlopen() at run time, so nothing
// links against VLC. The declarations below match libvlc 2.0's own headers
// for the few calls Live TV makes.
//
// LTVVLC finds VLC.app, loads libvlc and creates one VLC instance for the
// life of Front Row. Every libvlc call goes through its serial queue, so
// starting and stopping players never blocks Front Row's main thread.

#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>

typedef struct libvlc_instance_t libvlc_instance_t;
typedef struct libvlc_media_t libvlc_media_t;
typedef struct libvlc_media_player_t libvlc_media_player_t;
typedef struct libvlc_event_manager_t libvlc_event_manager_t;

// A union of event details follows these fields. Live TV only reads the type.
typedef struct libvlc_event_t {
    int type;
    void *p_obj;
} libvlc_event_t;

enum {
    libvlc_MediaPlayerEndReached       = 0x109,
    libvlc_MediaPlayerEncounteredError = 0x10A,
};

typedef void *(*libvlc_video_lock_cb)(void *opaque, void **planes);
typedef void (*libvlc_video_unlock_cb)(void *opaque, void *picture, void *const *planes);
typedef void (*libvlc_video_display_cb)(void *opaque, void *picture);
typedef void (*libvlc_callback_t)(const libvlc_event_t *event, void *userData);

// The libvlc functions Live TV calls, filled in when VLC loads.
typedef struct {
    const char *(*get_version)(void);
    const char *(*errmsg)(void);
    libvlc_instance_t *(*new_instance)(int argc, const char *const *argv);
    libvlc_media_t *(*media_new_location)(libvlc_instance_t *instance, const char *location);
    void (*media_add_option)(libvlc_media_t *media, const char *option);
    void (*media_release)(libvlc_media_t *media);
    libvlc_media_player_t *(*media_player_new_from_media)(libvlc_media_t *media);
    void (*media_player_release)(libvlc_media_player_t *player);
    int (*media_player_play)(libvlc_media_player_t *player);
    void (*media_player_stop)(libvlc_media_player_t *player);
    libvlc_event_manager_t *(*media_player_event_manager)(libvlc_media_player_t *player);
    int (*event_attach)(libvlc_event_manager_t *manager, int type, libvlc_callback_t callback, void *userData);
    void (*event_detach)(libvlc_event_manager_t *manager, int type, libvlc_callback_t callback, void *userData);
    void (*video_set_callbacks)(libvlc_media_player_t *player, libvlc_video_lock_cb lock,
                                libvlc_video_unlock_cb unlock, libvlc_video_display_cb display, void *opaque);
    void (*video_set_format)(libvlc_media_player_t *player, const char *chroma,
                             unsigned width, unsigned height, unsigned pitch);
    void (*video_set_deinterlace)(libvlc_media_player_t *player, const char *mode);
    int (*audio_set_volume)(libvlc_media_player_t *player, int volume);    // 0 silent, 100 normal
} LTVLibVLC;

extern LTVLibVLC LTVlibvlc;

@interface LTVVLC : NSObject {
    dispatch_queue_t _queue;
    BOOL _started;
    libvlc_instance_t *_instance;
    NSString *_failure;
}

+ (LTVVLC *)sharedEngine;

// Serial queue for every libvlc call.
- (dispatch_queue_t)queue;

// Loads VLC on the queue, the first time only. The channel menu calls this
// so VLC is ready by the time a channel is chosen.
- (void)startInBackground;

// Read these on the queue, after -startInBackground.
- (libvlc_instance_t *)instance;    // NULL if VLC couldn't be loaded
- (NSString *)failure;              // why not, worded for the screen

@end
