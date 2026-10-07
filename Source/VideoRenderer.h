// VideoRenderer.h
//
// Draws the pictures VLC decodes, inside Front Row's own OpenGL context.
//
// Front Row doesn't draw video through Core Animation. Its renderer
// (BRRenderScene) has one "playback delegate" slot. Each frame it asks the
// delegate -newFrameForTime:, then calls -drawFrameInBounds: in its OpenGL
// context, and then draws the interface layers on top. Front Row's own
// players put a BRVideoPlayerHostLayer there. Live TV puts this object there.
// A CAOpenGLLayer can't be used: it can't create an OpenGL context while Front
// Row has captured the displays ("invalid display").
//
// VLC writes each picture into memory through its "vmem" callbacks, as UYVY
// (YCbCr 4:2:2) at the screen's size, so the graphics card does the colour
// conversion (GL_APPLE_ycbcr_422) and VLC only scales and packs. VLC scales
// every source to that size, which suits the 16:9 broadcasts this is for.
//
// A stream starts mid-packet, so the decoder's first pictures refer to frames
// that were never sent. It fills those gaps with zeros, which show as green
// blocks. Zero luma and chroma together can't occur in broadcast video. VLC's
// timing also takes a moment to settle, which shows as a stall. So the
// renderer keeps pictures hidden for at least a second after the first one,
// and until a few in a row have no green blocks (or three seconds have
// passed). Then it fades the picture in from black over LTVFadeInTime. The
// player fades the sound in over the same time.
//
// There's one renderer for the life of Front Row, so its texture is made once.

#import <Foundation/Foundation.h>
#import <OpenGL/OpenGL.h>
#import <OpenGL/gl.h>
#import <CoreVideo/CoreVideo.h>
#import <pthread.h>
#import "VLC.h"

// How long the picture takes to fade in once it's shown. 0.5 seconds felt
// abrupt; 0.8 is closer to Apple's own fades.
#define LTVFadeInTime 0.8

@interface LTVVideoRenderer : NSObject {
    pthread_mutex_t _mutex;
    unsigned _width;
    unsigned _height;
    uint8_t *_decoding;     // VLC writes here between its lock and unlock calls
    uint8_t *_shown;        // copy of the newest picture VLC has displayed
    BOOL _newPicture;
    BOOL _hasPicture;           // a picture has been revealed since the stream started
    int _picturesSeen;          // since the stream started, shown or not
    int _cleanRun;              // pictures in a row with no green blocks
    CFAbsoluteTime _firstDecodedAt;
    CFAbsoluteTime _shownAt;
    GLuint _texture;
    CGLContextObj _textureContext;
    id _target;
    SEL _firstPictureAction;
}

// Created on first use, with pictures of the given size.
+ (LTVVideoRenderer *)sharedRendererWithWidth:(unsigned)width height:(unsigned)height;

// Sends action, with this renderer, to target on the main thread when the
// stream is shown and its fade-in starts. The target isn't retained. Clear it
// before it goes.
- (void)setTarget:(id)target firstPictureAction:(SEL)action;

// Forgets the last picture and reports the next one as a first picture.
// Call before each new stream starts.
- (void)waitForFirstPicture;

// Points a player's memory output at this renderer. Call on the VLC queue,
// before playing.
- (void)attachToPlayer:(libvlc_media_player_t *)player;

// BRRenderScene playback delegate methods, called on Front Row's render
// thread with its OpenGL context current.
- (BOOL)newFrameForTime:(const CVTimeStamp *)timeStamp;
- (void)drawFrameInBounds:(CGSize)bounds;

@end
