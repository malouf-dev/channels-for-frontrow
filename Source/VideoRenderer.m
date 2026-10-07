// VideoRenderer.m
//
// <OpenGL/gl.h> already includes the extension constants on 10.6. Including
// <OpenGL/glext.h> again breaks the build.

#import "VideoRenderer.h"

// UYVY is Cb Y0 Cr Y1 in memory. Tested on a 2011 iMac's Radeon HD 6750M with
// a red and blue test picture: GL_UNSIGNED_SHORT_8_8_APPLE gives exact red and
// blue, while the _REV_ type turns both green.
#define LTVPictureType GL_UNSIGNED_SHORT_8_8_APPLE

// A stream is shown once both are true: at least a second has passed since
// its first picture, so VLC's timing has settled, and three pictures in a
// row have had no green blocks. If a channel never looks clean, it's shown
// after three seconds anyway.
static const CFTimeInterval LTVLeastHiddenTime = 1.0;
static const int LTVCleanPicturesToReveal = 3;
static const CFTimeInterval LTVMostHiddenTime = 3.0;

@interface LTVVideoRenderer ()
- (id)initWithWidth:(unsigned)width height:(unsigned)height;
- (void *)lockPicture:(void **)planes;
- (void)displayPicture;
@end

// VLC calls these on its video output thread.

static void *LTVLockPicture(void *opaque, void **planes)
{
    return [(LTVVideoRenderer *)opaque lockPicture:planes];
}

static void LTVUnlockPicture(void *opaque, void *picture, void *const *planes)
{
}

static void LTVDisplayPicture(void *opaque, void *picture)
{
    [(LTVVideoRenderer *)opaque displayPicture];
}

@implementation LTVVideoRenderer

+ (LTVVideoRenderer *)sharedRendererWithWidth:(unsigned)width height:(unsigned)height
{
    static LTVVideoRenderer *renderer;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ renderer = [[LTVVideoRenderer alloc] initWithWidth:width height:height]; });
    return renderer;
}

- (id)initWithWidth:(unsigned)width height:(unsigned)height
{
    if ((self = [super init])) {
        _width = width;
        _height = height;
        pthread_mutex_init(&_mutex, NULL);
        _decoding = calloc((size_t)width * height, 2);
        _shown = calloc((size_t)width * height, 2);
    }
    return self;
}

- (void)setTarget:(id)target firstPictureAction:(SEL)action
{
    pthread_mutex_lock(&_mutex);
    _target = target;
    _firstPictureAction = action;
    pthread_mutex_unlock(&_mutex);
}

- (void)waitForFirstPicture
{
    pthread_mutex_lock(&_mutex);
    _hasPicture = NO;
    _newPicture = NO;
    _picturesSeen = 0;
    _cleanRun = 0;
    _firstDecodedAt = 0;
    _shownAt = 0;
    pthread_mutex_unlock(&_mutex);
}

// Samples every 32nd pixel pair on every 8th row for zero luma and chroma,
// the decoder's green fill. Studio-range video never goes below 16, so a
// couple of near-zero samples are allowed before a picture counts as broken.
- (BOOL)pictureIsClean:(const uint8_t *)picture
{
    size_t rowBytes = (size_t)_width * 2;
    int broken = 0;
    for (unsigned y = 4; y < _height; y += 8) {
        const uint8_t *row = picture + y * rowBytes;
        for (size_t x = 0; x + 3 < rowBytes; x += 64)
            if (row[x] < 8 && row[x + 1] < 8 && row[x + 2] < 8 && ++broken > 2)
                return NO;
    }
    return YES;
}

- (void)attachToPlayer:(libvlc_media_player_t *)player
{
    LTVlibvlc.video_set_callbacks(player, LTVLockPicture, LTVUnlockPicture, LTVDisplayPicture, self);
    LTVlibvlc.video_set_format(player, "UYVY", _width, _height, _width * 2);
}

- (void *)lockPicture:(void **)planes
{
    planes[0] = _decoding;
    return NULL;
}

// VLC calls this when the picture is due on screen. Copying it means the
// renderer always draws a whole, displayed picture while VLC prepares the next.
- (void)displayPicture
{
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    pthread_mutex_lock(&_mutex);
    memcpy(_shown, _decoding, (size_t)_width * _height * 2);
    if (++_picturesSeen == 1)
        _firstDecodedAt = now;
    BOOL first = NO;
    if (!_hasPicture) {
        _cleanRun = [self pictureIsClean:_shown] ? _cleanRun + 1 : 0;
        CFTimeInterval hidden = now - _firstDecodedAt;
        BOOL clean = _cleanRun >= LTVCleanPicturesToReveal;
        if ((clean && hidden >= LTVLeastHiddenTime) || hidden >= LTVMostHiddenTime) {
            first = YES;
            _hasPicture = YES;
            _shownAt = now;
            // VLC's thread has no autorelease pool of its own.
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
            NSLog(@"Live TV: picture shown %.2fs after the first of %d decoded, %s", hidden, _picturesSeen,
                  clean ? "clean" : "gave up waiting for a clean one");
            [pool drain];
        }
    }
    if (_hasPicture)
        _newPicture = YES;
    id target = first ? _target : nil;
    SEL action = _firstPictureAction;
    pthread_mutex_unlock(&_mutex);

    if (target)
        dispatch_async(dispatch_get_main_queue(), ^{
            [target performSelector:action withObject:self];
        });
}

// How far the fade-in has got: 0 before the stream is shown, 1 once it's done.
- (float)fadeLevel
{
    if (!_hasPicture)
        return 0.0f;
    CFTimeInterval elapsed = CFAbsoluteTimeGetCurrent() - _shownAt;
    return elapsed >= LTVFadeInTime ? 1.0f : (float)(elapsed / LTVFadeInTime);
}

// Also asks for a redraw on every frame of the fade, so it animates smoothly.
- (BOOL)newFrameForTime:(const CVTimeStamp *)timeStamp
{
    pthread_mutex_lock(&_mutex);
    BOOL redraw = _newPicture || (_hasPicture && [self fadeLevel] < 1.0f);
    pthread_mutex_unlock(&_mutex);
    return redraw;
}

// Called for every frame Front Row draws, so it redraws the current picture
// even when no new one has arrived. All OpenGL state it changes is restored,
// because Front Row draws its interface into the same context afterwards.
- (void)drawFrameInBounds:(CGSize)bounds
{
    pthread_mutex_lock(&_mutex);
    BOOL hasPicture = _hasPicture;
    float fade = [self fadeLevel];
    pthread_mutex_unlock(&_mutex);
    if (!hasPicture)
        return;

    glPushAttrib(GL_ENABLE_BIT | GL_TEXTURE_BIT | GL_CURRENT_BIT | GL_COLOR_BUFFER_BIT | GL_VIEWPORT_BIT);
    glPushClientAttrib(GL_CLIENT_PIXEL_STORE_BIT);
    glMatrixMode(GL_TEXTURE);
    glPushMatrix();
    glLoadIdentity();
    glMatrixMode(GL_PROJECTION);
    glPushMatrix();
    glLoadIdentity();
    glMatrixMode(GL_MODELVIEW);
    glPushMatrix();
    glLoadIdentity();

    // A texture belongs to the context it was made in. If Front Row has a new
    // context, the old texture went with the old one.
    CGLContextObj context = CGLGetCurrentContext();
    if (context != _textureContext) {
        _texture = 0;
        _textureContext = context;
    }
    if (_texture == 0) {
        glGenTextures(1, &_texture);
        glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _texture);
        glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        glTexImage2D(GL_TEXTURE_RECTANGLE_ARB, 0, GL_RGB8, _width, _height, 0,
                     GL_YCBCR_422_APPLE, LTVPictureType, NULL);
        pthread_mutex_lock(&_mutex);
        _newPicture = YES;      // upload the current picture into the new texture
        pthread_mutex_unlock(&_mutex);
    }
    glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _texture);

    pthread_mutex_lock(&_mutex);
    if (_newPicture) {
        glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);
        glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
        glTexSubImage2D(GL_TEXTURE_RECTANGLE_ARB, 0, 0, 0, _width, _height,
                        GL_YCBCR_422_APPLE, LTVPictureType, _shown);
        _newPicture = NO;
    }
    pthread_mutex_unlock(&_mutex);

    // Rectangle textures use pixel coordinates. Row 0 of the picture is the
    // top, so the texture is flipped onto the quad.
    glViewport(0, 0, (GLsizei)bounds.width, (GLsizei)bounds.height);
    glDisable(GL_BLEND);
    glDisable(GL_DEPTH_TEST);
    glEnable(GL_TEXTURE_RECTANGLE_ARB);
    // During the fade-in, the picture is multiplied towards black.
    if (fade < 1.0f) {
        glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE);
        glColor4f(fade, fade, fade, 1.0f);
    } else {
        glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_REPLACE);
    }
    glBegin(GL_QUADS);
    glTexCoord2f(0.0f, _height);    glVertex2f(-1.0f, -1.0f);
    glTexCoord2f(_width, _height);  glVertex2f( 1.0f, -1.0f);
    glTexCoord2f(_width, 0.0f);     glVertex2f( 1.0f,  1.0f);
    glTexCoord2f(0.0f, 0.0f);       glVertex2f(-1.0f,  1.0f);
    glEnd();
    glBindTexture(GL_TEXTURE_RECTANGLE_ARB, 0);

    glMatrixMode(GL_TEXTURE);
    glPopMatrix();
    glMatrixMode(GL_PROJECTION);
    glPopMatrix();
    glMatrixMode(GL_MODELVIEW);
    glPopMatrix();
    glPopClientAttrib();
    glPopAttrib();
}

@end
