// vlccheck.c
//
// Plays a stream with VLC's engine (libvlc from an unmodified VLC.app) in a
// 32-bit process, decoding the picture into memory the way a Front Row plugin
// would, with no window. Reports the time to the first picture, frames per
// second and processor use. Runs over SSH on the old Mac.
//
//   vlccheck VLC.app URL [seconds] [chroma] [caching-ms] [deinterlace-mode] [frame]
//
//   seconds           how long to play after the first picture (default 20)
//   chroma            RV32 (RGB) or UYVY (YUV 4:2:2), at 1920x1080 (default RV32)
//   caching-ms        VLC's network buffer (default 1000)
//   deinterlace-mode  yadif, yadif2x, blend, linear, ... or "off" (default yadif)
//   frame             saves pictures 1, 5, 10, 20, 30, 50 and 100 as frame-NNN.ppm,
//                     RV32 only. They're kept in memory and written at the end.
//
// With UYVY, it also counts the green-block samples in each of the first 80
// pictures, using the same test as Live TV's renderer, and prints the counts.
//
// Extra VLC options can be given in the environment, separated by spaces:
//   VLCCHECK_ARGS="--no-avcodec-hurry-up" vlccheck ...
//
// Build on the old Mac, against the headers inside VLC.app:
//   gcc-4.2 -arch i386 -std=gnu99 -O2 -I VLC.app/Contents/MacOS/include -o vlccheck vlccheck.c
//
// VLC 2.0.10 is the last 32-bit Intel build. Its libraries find each other
// with @loader_path, so dlopen() by full path works from anywhere.

#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <sys/time.h>
#include <unistd.h>
#include <vlc/libvlc.h>
#include <vlc/libvlc_media.h>
#include <vlc/libvlc_media_player.h>

#define WIDTH  1920
#define HEIGHT 1080

static uint8_t *pixels;
static int bytesPerPixel;
static volatile int frames;
static volatile double firstPicture;
static const char *framePath;
static const int savedFrames[] = { 1, 5, 10, 20, 30, 50, 100 };
#define SAVED_COUNT (int)(sizeof savedFrames / sizeof savedFrames[0])
static uint8_t *saved[SAVED_COUNT];
static int greenCounts[80];

// Same sampling as LTVVideoRenderer: every 32nd pixel pair on every 8th row,
// counting zero luma and chroma (the decoder's green fill).
static int greenSamples(const uint8_t *picture)
{
    int count = 0;
    for (int y = 4; y < HEIGHT; y += 8) {
        const uint8_t *row = picture + y * WIDTH * 2;
        for (int x = 0; x + 3 < WIDTH * 2; x += 64)
            if (row[x] < 8 && row[x + 1] < 8 && row[x + 2] < 8)
                count++;
    }
    return count;
}

static double now(void)
{
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return tv.tv_sec + tv.tv_usec / 1e6;
}

static double cpuSeconds(void)
{
    struct rusage usage;
    getrusage(RUSAGE_SELF, &usage);
    return usage.ru_utime.tv_sec + usage.ru_utime.tv_usec / 1e6
         + usage.ru_stime.tv_sec + usage.ru_stime.tv_usec / 1e6;
}

static void *lockPicture(void *opaque, void **planes)
{
    planes[0] = pixels;
    return NULL;
}

static void unlockPicture(void *opaque, void *picture, void *const *planes)
{
}

// RV32 from vmem is B, G, R, X in memory on Intel.
static void writeFrames(void)
{
    for (int k = 0; k < SAVED_COUNT; k++) {
        if (!saved[k])
            continue;
        char name[1024];
        snprintf(name, sizeof name, "%s-%03d.ppm", framePath, savedFrames[k]);
        FILE *f = fopen(name, "wb");
        if (!f)
            continue;
        fprintf(f, "P6\n%d %d\n255\n", WIDTH, HEIGHT);
        for (int i = 0; i < WIDTH * HEIGHT; i++) {
            uint8_t rgb[3] = { saved[k][i * 4 + 2], saved[k][i * 4 + 1], saved[k][i * 4] };
            fwrite(rgb, 1, 3, f);
        }
        fclose(f);
    }
}

static void displayPicture(void *opaque, void *picture)
{
    if (frames == 0)
        firstPicture = now();
    frames++;
    if (bytesPerPixel == 2 && frames <= 80)
        greenCounts[frames - 1] = greenSamples(pixels);
    if (framePath && bytesPerPixel == 4)
        for (int k = 0; k < SAVED_COUNT; k++)
            if (frames == savedFrames[k]) {
                saved[k] = malloc(WIDTH * HEIGHT * 4);
                memcpy(saved[k], pixels, WIDTH * HEIGHT * 4);
            }
}

#define LOAD(name) typeof(&name) p_##name = dlsym(lib, #name); \
    if (!p_##name) { printf("missing %s\n", #name); return 1; }

int main(int argc, char **argv)
{
    if (argc < 3) {
        fprintf(stderr, "usage: vlccheck VLC.app URL [seconds] [chroma] [caching-ms] [deinterlace-mode] [frame]\n");
        return 2;
    }
    const char *app = argv[1];
    const char *url = argv[2];
    int seconds = argc > 3 ? atoi(argv[3]) : 20;
    const char *chroma = argc > 4 ? argv[4] : "RV32";
    const char *caching = argc > 5 ? argv[5] : "1000";
    const char *deinterlace = argc > 6 ? argv[6] : "yadif";
    framePath = argc > 7 ? argv[7] : NULL;
    bytesPerPixel = strcmp(chroma, "UYVY") == 0 ? 2 : 4;
    pixels = calloc(WIDTH * HEIGHT, 4);

    char path[2048];
    snprintf(path, sizeof path, "%s/Contents/MacOS/plugins", app);
    setenv("VLC_PLUGIN_PATH", path, 1);
    snprintf(path, sizeof path, "%s/Contents/MacOS/lib/libvlc.5.dylib", app);
    void *lib = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    if (!lib) {
        printf("dlopen failed: %s\n", dlerror());
        return 1;
    }
    LOAD(libvlc_get_version);
    LOAD(libvlc_new);
    LOAD(libvlc_media_new_location);
    LOAD(libvlc_media_add_option);
    LOAD(libvlc_media_player_new_from_media);
    LOAD(libvlc_media_release);
    LOAD(libvlc_video_set_callbacks);
    LOAD(libvlc_video_set_format);
    LOAD(libvlc_video_set_deinterlace);
    LOAD(libvlc_media_player_play);
    LOAD(libvlc_media_player_stop);
    LOAD(libvlc_media_player_release);
    LOAD(libvlc_release);
    LOAD(libvlc_errmsg);

    char deinterlaceOn[32], deinterlaceMode[64];
    snprintf(deinterlaceOn, sizeof deinterlaceOn, "--deinterlace=%d", strcmp(deinterlace, "off") ? 1 : 0);
    snprintf(deinterlaceMode, sizeof deinterlaceMode, "--deinterlace-mode=%s", deinterlace);
    const char *vlcArgs[32] = {
        "--intf=dummy", "--no-video-title-show", "--no-stats", "--no-sub-autodetect-file",
        "--aout=adummy",            // decode the sound but don't play it
        deinterlaceOn, deinterlaceMode,
    };
    int vlcArgCount = 7;
    char *extra = getenv("VLCCHECK_ARGS") ? strdup(getenv("VLCCHECK_ARGS")) : NULL;
    for (char *arg = extra ? strtok(extra, " ") : NULL; arg && vlcArgCount < 32; arg = strtok(NULL, " "))
        vlcArgs[vlcArgCount++] = arg;
    double started = now();
    libvlc_instance_t *vlc = p_libvlc_new(vlcArgCount, vlcArgs);
    if (!vlc) {
        printf("libvlc_new failed: %s\n", p_libvlc_errmsg());
        return 1;
    }
    printf("libvlc %s ready in %.2fs\n", p_libvlc_get_version(), now() - started);

    char cachingOption[64];
    snprintf(cachingOption, sizeof cachingOption, ":network-caching=%s", caching);
    libvlc_media_t *media = p_libvlc_media_new_location(vlc, url);
    p_libvlc_media_add_option(media, cachingOption);
    libvlc_media_player_t *player = p_libvlc_media_player_new_from_media(media);
    p_libvlc_media_release(media);
    p_libvlc_video_set_callbacks(player, lockPicture, unlockPicture, displayPicture, NULL);
    p_libvlc_video_set_format(player, chroma, WIDTH, HEIGHT, WIDTH * bytesPerPixel);
    // With memory output, --deinterlace on the command line has no effect
    // (yadif2x stays at 25 frames a second). The player-level call works.
    p_libvlc_video_set_deinterlace(player, strcmp(deinterlace, "off") ? deinterlace : NULL);

    double playCalled = now();
    p_libvlc_media_player_play(player);
    while (frames == 0 && now() - playCalled < 30)
        usleep(10000);
    if (frames == 0) {
        printf("no picture after 30s\n");
        return 1;
    }
    printf("first picture after %.2fs (chroma %s, caching %sms, deinterlace %s)\n",
           firstPicture - playCalled, chroma, caching, deinterlace);

    int framesAtStart = frames;
    double cpuAtStart = cpuSeconds(), wallAtStart = now();
    for (int s = 1; s <= seconds; s++) {
        sleep(1);
        if (s % 5 == 0)
            printf("  %2ds: %d frames so far\n", s, frames - framesAtStart);
    }
    double wall = now() - wallAtStart;
    printf("%.1f frames per second, processor %.0f%% of one core (4 cores = 400%%)\n",
           (frames - framesAtStart) / wall, 100.0 * (cpuSeconds() - cpuAtStart) / wall);

    p_libvlc_media_player_stop(player);
    p_libvlc_media_player_release(player);
    p_libvlc_release(vlc);
    if (framePath)
        writeFrames();
    if (bytesPerPixel == 2) {
        printf("green samples in pictures 1-80:");
        for (int i = 0; i < 80; i++)
            printf(" %d", greenCounts[i]);
        printf("\n");
    }
    return 0;
}
