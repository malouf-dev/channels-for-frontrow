// Opens a URL with QTKit in a 32-bit process, muted, and reports load state
// and playback progress every half second for about 20 seconds. Runs over
// SSH on the old Mac, with no window.
//
//   hlscheck URL                    QuickTime 7 engine (Front Row's player)
//   hlscheck URL playback           QuickTime X engine (Live TV's player)
//   hlscheck URL playback-early     QuickTime X, and play before it's playable
//
// Build on the old Mac:
//   gcc-4.2 -arch i386 -isysroot /Developer/SDKs/MacOSX10.6.sdk \
//       -mmacosx-version-min=10.6 -std=gnu99 -o hlscheck hlscheck.m \
//       -framework Cocoa -framework QTKit
#import <Cocoa/Cocoa.h>
#import <QTKit/QTKit.h>

int main(int argc, char **argv)
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [NSApplication sharedApplication];
    NSURL *url = [NSURL URLWithString:[NSString stringWithUTF8String:argv[1]]];
    BOOL playback = argc > 2 && strncmp(argv[2], "playback", 8) == 0;
    BOOL early = argc > 2 && strcmp(argv[2], "playback-early") == 0;
    NSMutableDictionary *attrs = [NSMutableDictionary dictionaryWithObjectsAndKeys:
        url, QTMovieURLAttribute,
        [NSNumber numberWithBool:YES], QTMovieOpenAsyncOKAttribute, nil];
    if (playback)
        [attrs setObject:[NSNumber numberWithBool:YES] forKey:QTMovieOpenForPlaybackAttribute];
    NSError *error = nil;
    QTMovie *movie = [QTMovie movieWithAttributes:attrs error:&error];
    if (!movie) {
        printf("open failed: %s\n", [[error description] UTF8String]);
        return 1;
    }
    [movie setMuted:YES];
    if (early)
        [movie play];
    printf("opened, playback=%d\n", playback);
    BOOL started = NO;
    for (int i = 0; i < 40; i++) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
        long state = [[movie attributeForKey:QTMovieLoadStateAttribute] longValue];
        NSSize size = [[movie attributeForKey:QTMovieNaturalSizeAttribute] sizeValue];
        printf("t=%4.1f state=%6ld size=%gx%g time=%s rate=%g\n", i * 0.5, state, size.width, size.height,
               [QTStringFromTime([movie currentTime]) UTF8String], [movie rate]);
        if (state < 0) {
            printf("error: %s\n", [[[movie attributeForKey:QTMovieLoadStateErrorAttribute] description] UTF8String]);
            break;
        }
        if (!started && !early && state >= QTMovieLoadStatePlayable) {
            [movie play];
            started = YES;
        }
    }
    [pool drain];
    return 0;
}
