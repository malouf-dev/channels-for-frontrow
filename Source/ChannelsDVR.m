// ChannelsDVR.m
//
// Endpoints, confirmed against Channels DVR 2026.08.07:
//   /api/v1/channels              id, name, number, logo_url for each channel
//   /dvr/collections/channels     collections: slug, name, items (channel numbers)
//   /devices/ANY/guide            per channel: Channel {Number, ...} and Airings
//                                 {Time, Duration, Title, Summary, Raw, ...}
//   /devices/ANY/channels/N/stream.mpg   the untouched stream

#import "ChannelsDVR.h"
#import "JSON.h"

// Error descriptions appear as a menu row in Front Row, which fits about 26
// characters, so they're short. The details go to the log.

static NSError *LTVError(NSString *message)
{
    return [NSError errorWithDomain:@"LTVChannelsDVR" code:1
                           userInfo:[NSDictionary dictionaryWithObject:message forKey:NSLocalizedDescriptionKey]];
}

// Channel numbers come as strings, but tolerate numbers.
static NSString *LTVString(id value)
{
    if ([value isKindOfClass:[NSString class]])
        return value;
    if ([value isKindOfClass:[NSNumber class]])
        return [value stringValue];
    return nil;
}

static id LTVObjectOfClass(id object, Class expected)
{
    return [object isKindOfClass:expected] ? object : nil;
}

@implementation LTVChannelsDVR

- (id)initWithServer:(NSString *)server
{
    if ((self = [super init]))
        _server = [server copy];
    return self;
}

- (void)dealloc
{
    [_server release];
    [super dealloc];
}

- (NSURL *)streamURLForChannel:(NSString *)number
{
    return [NSURL URLWithString:[NSString stringWithFormat:@"http://%@/devices/ANY/channels/%@/stream.mpg", _server, number]];
}

- (id)JSONAtPath:(NSString *)path error:(NSError **)error
{
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://%@%@", _server, path]];
    NSURLRequest *request = [NSURLRequest requestWithURL:url
                                             cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                         timeoutInterval:15.0];
    NSHTTPURLResponse *response = nil;
    NSError *failure = nil;
    NSData *data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&failure];
    if (data == nil) {
        if (error)
            *error = LTVError(@"Can't reach Channels DVR");
        NSLog(@"Live TV: %@ failed: %@", url, failure);
        return nil;
    }
    if ([response statusCode] != 200) {
        if (error)
            *error = LTVError(@"Channels DVR error");
        NSLog(@"Live TV: %@ answered %ld", url, (long)[response statusCode]);
        return nil;
    }
    NSError *parseError = nil;
    id value = LTVJSONParse(data, &parseError);
    if (value == nil) {
        if (error)
            *error = LTVError(@"Channels DVR error");
        NSLog(@"Live TV: %@: %@", url, [parseError localizedDescription]);
    }
    return value;
}

- (NSArray *)channelsInCollection:(NSString *)collection error:(NSError **)error
{
    NSArray *all = LTVObjectOfClass([self JSONAtPath:@"/api/v1/channels" error:error], [NSArray class]);
    if (all == nil)
        return nil;

    NSMutableDictionary *byNumber = [NSMutableDictionary dictionary];
    NSMutableArray *ordered = [NSMutableArray array];
    for (NSDictionary *item in all) {
        if (![item isKindOfClass:[NSDictionary class]] || [[item objectForKey:@"hidden"] boolValue])
            continue;
        NSString *number = LTVString([item objectForKey:@"number"]);
        NSString *name = LTVString([item objectForKey:@"name"]);
        NSString *logo = LTVString([item objectForKey:@"logo_url"]);
        if (number == nil || [byNumber objectForKey:number])
            continue;
        NSDictionary *channel = [NSDictionary dictionaryWithObjectsAndKeys:
                                 number, @"number", name ? name : number, @"name", logo, @"logo", nil];
        [byNumber setObject:channel forKey:number];
        [ordered addObject:channel];
    }

    if ([collection length] == 0) {
        [ordered sortUsingComparator:^NSComparisonResult(id a, id b) {
            return [[a objectForKey:@"number"] compare:[b objectForKey:@"number"] options:NSNumericSearch];
        }];
        return ordered;
    }

    NSArray *collections = LTVObjectOfClass([self JSONAtPath:@"/dvr/collections/channels" error:error], [NSArray class]);
    if (collections == nil)
        return nil;
    for (NSDictionary *candidate in collections) {
        if (![candidate isKindOfClass:[NSDictionary class]])
            continue;
        NSString *name = LTVString([candidate objectForKey:@"name"]);
        if (name == nil || [name caseInsensitiveCompare:collection] != NSOrderedSame)
            continue;
        NSMutableArray *channels = [NSMutableArray array];
        for (id item in LTVObjectOfClass([candidate objectForKey:@"items"], [NSArray class])) {
            NSDictionary *channel = [byNumber objectForKey:LTVString(item)];
            if (channel)
                [channels addObject:channel];
        }
        return channels;
    }
    if (error)
        *error = LTVError(@"Collection not found");
    NSLog(@"Live TV: Channels DVR has no collection called %@", collection);
    return nil;
}

- (NSArray *)collectionNames:(NSError **)error
{
    NSArray *collections = LTVObjectOfClass([self JSONAtPath:@"/dvr/collections/channels" error:error], [NSArray class]);
    if (collections == nil)
        return nil;
    NSMutableArray *names = [NSMutableArray array];
    for (NSDictionary *collection in collections) {
        if (![collection isKindOfClass:[NSDictionary class]])
            continue;
        NSString *name = LTVString([collection objectForKey:@"name"]);
        if ([name length])
            [names addObject:name];
    }
    return names;
}

- (NSDictionary *)guideStarting:(NSDate *)start hours:(int)hours error:(NSError **)error
{
    NSString *path = [NSString stringWithFormat:@"/devices/ANY/guide?time=%lld&duration=%d",
                      (long long)[start timeIntervalSince1970], hours * 3600];
    NSArray *guide = LTVObjectOfClass([self JSONAtPath:path error:error], [NSArray class]);
    if (guide == nil)
        return nil;

    NSMutableDictionary *byNumber = [NSMutableDictionary dictionary];
    for (NSDictionary *entry in guide) {
        if (![entry isKindOfClass:[NSDictionary class]])
            continue;
        NSDictionary *channel = LTVObjectOfClass([entry objectForKey:@"Channel"], [NSDictionary class]);
        NSString *number = LTVString([channel objectForKey:@"Number"]);
        if (number == nil || [[byNumber objectForKey:number] count] > 0)
            continue;
        NSMutableArray *airings = [NSMutableArray array];
        for (NSDictionary *airing in LTVObjectOfClass([entry objectForKey:@"Airings"], [NSArray class])) {
            if (![airing isKindOfClass:[NSDictionary class]])
                continue;
            NSNumber *time = LTVObjectOfClass([airing objectForKey:@"Time"], [NSNumber class]);
            NSNumber *duration = LTVObjectOfClass([airing objectForKey:@"Duration"], [NSNumber class]);
            NSString *title = LTVObjectOfClass([airing objectForKey:@"Title"], [NSString class]);
            if (time == nil || duration == nil || title == nil)
                continue;
            NSDate *begins = [NSDate dateWithTimeIntervalSince1970:[time doubleValue]];
            NSDate *ends = [begins dateByAddingTimeInterval:[duration doubleValue]];
            NSMutableDictionary *kept = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                         begins, @"start", ends, @"end", title, @"title", nil];
            NSString *summary = LTVObjectOfClass([airing objectForKey:@"Summary"], [NSString class]);
            if ([summary length])
                [kept setObject:summary forKey:@"summary"];
            NSString *image = LTVObjectOfClass([airing objectForKey:@"Image"], [NSString class]);
            if ([image length])
                [kept setObject:image forKey:@"image"];
            [airings addObject:kept];
        }
        [airings sortUsingComparator:^NSComparisonResult(id a, id b) {
            return [[a objectForKey:@"start"] compare:[b objectForKey:@"start"]];
        }];
        [byNumber setObject:airings forKey:number];
    }
    return byNumber;
}

@end
