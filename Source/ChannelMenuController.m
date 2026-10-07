// ChannelMenuController.m

#import <math.h>
#import "ChannelMenuController.h"
#import "Discovery.h"
#import "PlayerController.h"
#import "ProgrammePreview.h"
#import "Settings.h"
#import "VLC.h"

// How far ahead to load the guide. Now and next are worked out from it each
// time a channel is highlighted.
static const int LTVGuideHours = 6;

// A guide older than this is reloaded in the background, when you come back
// from a channel or at the next minute while the menu is showing.
static const NSTimeInterval LTVGuideMaxAge = 30 * 60;

// HDHomeRun's picture server answers plain HTTP, which avoids 10.6's
// limited support for current HTTPS.
static NSString *LTVPlainHTTP(NSString *url)
{
    if ([url hasPrefix:@"https://img.hdhomerun.com/"])
        return [@"http://" stringByAppendingString:[url substringFromIndex:8]];
    return url;
}

@interface LTVChannelMenuController ()
- (void)findServerThenLoadCollection:(NSString *)collection;
- (void)loadChannelsInCollection:(NSString *)collection;
- (void)channelsLoaded:(NSArray *)channels failure:(NSString *)failure;
- (void)loadGuide;
- (void)loadGuideIfOld;
- (void)guideLoaded:(NSDictionary *)guide;
- (void)scheduleMinuteTick;
- (void)imageLoaded:(BRImage *)image forURL:(NSString *)url;
- (BOOL)isChannelRow:(long)row;
- (NSString *)imageURLForRow:(long)row;
@end

@implementation LTVChannelMenuController

- (id)init
{
    if ((self = [super init])) {
        [[self header] setTitle:@"Live TV"];
        [[self list] setDatasource:self];
        LTVInstallProgrammePopulator();
        // VLC takes a moment to load the first time. Start it now so it's
        // ready by the time a channel is chosen.
        [[LTVVLC sharedEngine] startInBackground];

        _images = [[NSMutableDictionary alloc] init];
        _imagesLoading = [[NSMutableSet alloc] init];

        NSString *collection = LTVReadSetting(LTVSettingChannelCollection);
        NSString *server = LTVReadSetting(LTVSettingChannelsServer);
        if (server) {
            _server = [[LTVChannelsDVR alloc] initWithServer:server];
            _message = [@"Loading channels…" retain];
            [self loadChannelsInCollection:collection];
        } else {
            _message = [@"Looking for Channels DVR…" retain];
            [self findServerThenLoadCollection:collection];
        }
    }
    return self;
}

- (void)dealloc
{
    [_server release];
    [_channels release];
    [_guide release];
    [_guideLoadedAt release];
    [_previewChangesAt release];
    [_message release];
    [_images release];
    [_imagesLoading release];
    [super dealloc];
}

// Channels that arrive during the menu's opening animation fill a list that
// has no size yet, and the list doesn't redraw afterwards. So reload once the
// menu is fully on screen.
- (void)wasPushed
{
    [super wasPushed];
    [[self list] reload];
    [self updatePreviewController];
    [self scheduleMinuteTick];
}

// A channel's player is on top of the menu.
- (void)wasBuriedByPushingController:(id)controller
{
    [super wasBuriedByPushingController:controller];
    _buried = YES;
}

// Back from a channel. What's on may have changed while it played.
- (void)wasExhumedByPoppingController:(id)controller
{
    [super wasExhumedByPoppingController:controller];
    _buried = NO;
    [self loadGuideIfOld];
    [self updatePreviewController];
}

// Leaving Live TV. The minute tick stops at its next run.
- (void)willBePopped
{
    _leaving = YES;
    [super willBePopped];
}

#pragma mark Keeping the guide current

- (void)loadGuideIfOld
{
    if (_server == nil || _channels == nil || _guideLoading)
        return;
    if (_guide == nil || -[_guideLoadedAt timeIntervalSinceNow] > LTVGuideMaxAge)
        [self loadGuide];
}

// Runs a second after each minute ticks over, while the menu is in the stack.
// Programmes change on the minute, so the highlighted preview redraws as soon
// as its programme ends. Each run keeps this controller alive for at most a
// minute after Live TV is left.
- (void)scheduleMinuteTick
{
    if (_ticking)
        return;
    _ticking = YES;
    double seconds = 61.0 - fmod([[NSDate date] timeIntervalSince1970], 60.0);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        _ticking = NO;
        // Also stop if Front Row cleared its screens without popping this one.
        if (_leaving || [self stack] == nil)
            return;
        if (!_buried) {
            [self loadGuideIfOld];
            if (_previewChangesAt && [_previewChangesAt timeIntervalSinceNow] <= 0)
                [self updatePreviewController];
        }
        [self scheduleMinuteTick];
    });
}

#pragma mark Loading

// With no address set, the Channels DVR server Bonjour finds: the one chosen
// in the preference pane when there are several, or else the first by name.
// It's looked for each time Live TV opens, so a new address is picked up.
- (void)findServerThenLoadCollection:(NSString *)collection
{
    NSString *chosen = LTVReadSetting(LTVSettingChannelsServerName);
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSArray *servers = LTVFindChannelsServers(3.0);
        NSDictionary *server = [servers count] ? [servers objectAtIndex:0] : nil;
        for (NSDictionary *candidate in servers)
            if ([[candidate objectForKey:@"name"] isEqualToString:chosen])
                server = candidate;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (server == nil) {
                NSLog(@"Live TV: no Channels DVR server found with Bonjour");
                [self channelsLoaded:nil failure:@"Channels DVR not found"];
                return;
            }
            NSLog(@"Live TV: found Channels DVR server %@ at %@", [server objectForKey:@"name"], [server objectForKey:@"address"]);
            _server = [[LTVChannelsDVR alloc] initWithServer:[server objectForKey:@"address"]];
            [_message release];
            _message = [@"Loading channels…" retain];
            [[self list] reload];
            [self loadChannelsInCollection:collection];
        });
        [pool drain];
    });
}

// Channels first, so the list appears quickly, then the guide.
- (void)loadChannelsInCollection:(NSString *)collection
{
    LTVChannelsDVR *server = _server;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSError *error = nil;
        NSArray *channels = [server channelsInCollection:collection error:&error];
        NSString *failure = channels ? nil : [error localizedDescription];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self channelsLoaded:channels failure:failure];
        });
        [pool drain];
    });
}

// The next six hours of guide, in the background. A failed load leaves the
// old guide in place and is tried again at the next minute.
- (void)loadGuide
{
    _guideLoading = YES;
    LTVChannelsDVR *server = _server;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSError *error = nil;
        NSTimeInterval started = [NSDate timeIntervalSinceReferenceDate];
        NSDictionary *guide = [server guideStarting:[NSDate date] hours:LTVGuideHours error:&error];
        if (guide)
            NSLog(@"Live TV: guide for %lu channels loaded in %.2fs", (unsigned long)[guide count],
                  [NSDate timeIntervalSinceReferenceDate] - started);
        else
            NSLog(@"Live TV: guide failed: %@", [error localizedDescription]);
        dispatch_async(dispatch_get_main_queue(), ^{
            [self guideLoaded:guide];
        });
        [pool drain];
    });
}

- (void)channelsLoaded:(NSArray *)channels failure:(NSString *)failure
{
    [_message release];
    _message = nil;
    if (channels == nil)
        _message = [failure copy];
    else if ([channels count] == 0)
        _message = [@"No channels found" retain];
    [_channels release];
    _channels = [channels count] ? [channels copy] : nil;
    NSLog(@"Live TV: %lu channels%@", (unsigned long)[_channels count], _message ? [@", " stringByAppendingString:_message] : @"");
    [[self list] reload];
    [self updatePreviewController];
    if (_channels)
        [self loadGuide];
}

- (void)guideLoaded:(NSDictionary *)guide
{
    _guideLoading = NO;
    if (guide == nil)
        return;
    [_guide release];
    _guide = [guide retain];
    [_guideLoadedAt release];
    _guideLoadedAt = [[NSDate alloc] init];
    [self updatePreviewController];
}

#pragma mark Pictures

// The cached picture, or nil while it downloads in the background. When it
// arrives, the preview is redrawn if it's still for that picture.
- (BRImage *)imageForURL:(NSString *)url
{
    if (url == nil)
        return nil;
    BRImage *image = [_images objectForKey:url];
    if (image || [_imagesLoading containsObject:url])
        return image;
    [_imagesLoading addObject:url];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:url]
                                                 cachePolicy:NSURLRequestReturnCacheDataElseLoad
                                             timeoutInterval:15.0];
        NSData *data = [NSURLConnection sendSynchronousRequest:request returningResponse:NULL error:NULL];
        BRImage *loaded = [data length] ? [BRImage imageWithData:data] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self imageLoaded:loaded forURL:url];
        });
        [pool drain];
    });
    return nil;
}

- (void)imageLoaded:(BRImage *)image forURL:(NSString *)url
{
    [_imagesLoading removeObject:url];
    if (image == nil) {
        NSLog(@"Live TV: couldn't load picture %@", url);
        return;
    }
    [_images setObject:image forKey:url];
    long row = [self selectedItem];
    if ([self isChannelRow:row] && [url isEqualToString:[self imageURLForRow:row]])
        [self updatePreviewController];
}

#pragma mark Guide

// The programme on now and the one after it, from the loaded guide.
- (void)findNow:(NSDictionary **)now next:(NSDictionary **)next forChannel:(NSDictionary *)channel
{
    NSDate *time = [NSDate date];
    *now = nil;
    *next = nil;
    for (NSDictionary *airing in [_guide objectForKey:[channel objectForKey:@"number"]]) {
        NSDate *start = [airing objectForKey:@"start"];
        NSDate *end = [airing objectForKey:@"end"];
        if ([end compare:time] != NSOrderedDescending)
            continue;                                   // already finished
        if (*now == nil && [start compare:time] != NSOrderedDescending) {
            *now = airing;
            continue;
        }
        *next = airing;
        break;
    }
}

// The programme's picture, or the channel's logo when it has none.
- (NSString *)imageURLForRow:(long)row
{
    NSDictionary *channel = [_channels objectAtIndex:row];
    NSDictionary *now, *next;
    [self findNow:&now next:&next forChannel:channel];
    NSString *url = [now objectForKey:@"image"] ? [now objectForKey:@"image"] : [channel objectForKey:@"logo"];
    return LTVPlainHTTP(url);
}

#pragma mark List datasource

- (BOOL)isChannelRow:(long)row
{
    return row >= 0 && row < (long)[_channels count];
}

- (long)itemCount
{
    return _channels ? (long)[_channels count] : 1;
}

- (NSString *)titleForRow:(long)row
{
    if (![self isChannelRow:row])
        return row == 0 ? _message : nil;
    return [[_channels objectAtIndex:row] objectForKey:@"name"];
}

- (id)itemForRow:(long)row
{
    NSString *title = [self titleForRow:row];
    if (title == nil)
        return nil;
    BRTextMenuItemLayer *item = [[[BRTextMenuItemLayer alloc] init] autorelease];
    [item setTitle:title];
    if (![self isChannelRow:row])
        [item setDimmed:YES];
    return item;
}

- (float)heightForRow:(long)row
{
    return 0.0f;
}

- (BOOL)rowSelectable:(long)row
{
    return [self isChannelRow:row];
}

- (void)itemSelected:(long)row
{
    if (![self isChannelRow:row])
        return;
    NSDictionary *channel = [_channels objectAtIndex:row];
    NSURL *url = [_server streamURLForChannel:[channel objectForKey:@"number"]];
    NSLog(@"Live TV: opening %@ from %@", [channel objectForKey:@"name"], url);
    LTVPlayerController *player = [[[LTVPlayerController alloc] initWithTitle:[channel objectForKey:@"name"]
                                                                    streamURL:url] autorelease];
    [[self stack] pushController:player];
}

#pragma mark Preview

- (id)previewControlForItem:(long)row
{
    if (![self isChannelRow:row])
        return nil;
    NSDictionary *channel = [_channels objectAtIndex:row];
    NSString *title = [channel objectForKey:@"name"];
    NSString *summary;
    NSString *next = nil;

    [_previewChangesAt release];
    _previewChangesAt = nil;
    if (_guide == nil) {
        summary = @"Loading the guide…";
    } else {
        NSDictionary *now, *following;
        [self findNow:&now next:&following forChannel:channel];
        // When this preview goes out of date: the programme on now ends, or
        // the next one starts if nothing is on.
        _previewChangesAt = [(now ? [now objectForKey:@"end"] : [following objectForKey:@"start"]) retain];
        if (now) {
            title = [now objectForKey:@"title"];
            summary = [now objectForKey:@"summary"] ? [now objectForKey:@"summary"] : @"";
        } else {
            summary = following ? @"" : @"No guide information.";
        }
        next = [following objectForKey:@"title"];
    }

    NSString *imageURL = [self imageURLForRow:row];
    LTVProgrammeAsset *asset = [[[LTVProgrammeAsset alloc] initWithTitle:title summary:summary next:next
                                                                   image:[self imageForURL:imageURL]
                                                                 imageID:imageURL] autorelease];
    // Live TV is about what's on now, so the text shows without Front Row's pause.
    BRMetadataPreviewController *preview = [[[BRMetadataPreviewController alloc] init] autorelease];
    [preview setShowsMetadataImmediately:YES];
    [preview setAsset:asset];
    return preview;
}

@end
