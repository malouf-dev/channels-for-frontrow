// vlc-cache.c
//
// Builds VLC's plugin cache (plugins.dat) inside an installed VLC.app. The
// installer's postinstall script runs it as root. The installed copy belongs
// to root, so Front Row can't save the cache there itself, and without it
// VLC's engine opens all 283 plugins at every start. From a cold disk on a
// 2011 iMac, a read-only copy started in 0.57 seconds without the cache and
// 0.05 to 0.07 seconds with it.
//
//   vlc-cache "/Library/Application Support/channels-for-frontrow/VLC.app"
//
// Built on the old Mac by the Makefile's pkg target. 32-bit Intel only, like
// VLC 2.0.10. No VLC headers are needed for the three calls it makes.

#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/time.h>

typedef void *(*NewInstance)(int, const char *const *);
typedef void (*Release)(void *);
typedef const char *(*ErrorMessage)(void);

static double now(void)
{
    struct timeval t;
    gettimeofday(&t, NULL);
    return t.tv_sec + t.tv_usec / 1e6;
}

int main(int argc, char **argv)
{
    if (argc != 2) {
        fprintf(stderr, "usage: vlc-cache VLC.app\n");
        return 2;
    }

    // Same loading as the plugin's VLC.m: the libraries find each other with
    // @loader_path, and the plugins folder is given separately.
    char path[2048];
    snprintf(path, sizeof path, "%s/Contents/MacOS/plugins", argv[1]);
    setenv("VLC_PLUGIN_PATH", path, 1);
    snprintf(path, sizeof path, "%s/Contents/MacOS/lib/libvlc.5.dylib", argv[1]);
    void *library = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    if (library == NULL) {
        fprintf(stderr, "vlc-cache: %s\n", dlerror());
        return 1;
    }
    NewInstance newInstance = (NewInstance)dlsym(library, "libvlc_new");
    Release release = (Release)dlsym(library, "libvlc_release");
    ErrorMessage errorMessage = (ErrorMessage)dlsym(library, "libvlc_errmsg");
    if (newInstance == NULL || release == NULL || errorMessage == NULL) {
        fprintf(stderr, "vlc-cache: this isn't VLC 2.0.10's engine\n");
        return 1;
    }

    // --reset-plugins-cache scans every plugin and saves a new cache.
    const char *arguments[] = { "--ignore-config", "--quiet", "--intf=dummy", "--reset-plugins-cache" };
    double started = now();
    void *instance = newInstance(sizeof arguments / sizeof arguments[0], arguments);
    if (instance == NULL) {
        const char *error = errorMessage();
        fprintf(stderr, "vlc-cache: VLC didn't start: %s\n", error ? error : "no reason given");
        return 1;
    }
    printf("vlc-cache: scanned VLC's plugins in %.2fs\n", now() - started);
    release(instance);
    return 0;
}
