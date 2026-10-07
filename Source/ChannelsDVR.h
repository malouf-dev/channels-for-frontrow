// ChannelsDVR.h
//
// The parts of Channels DVR Server's HTTP API that Live TV uses. The API
// needs no login on the local network. The loading methods block, so call
// them from a background queue. Also built into the preference pane.

#import <Foundation/Foundation.h>

@interface LTVChannelsDVR : NSObject {
    NSString *_server;      // host:port, such as 192.168.0.20:8089
}

- (id)initWithServer:(NSString *)server;

// The channel's untouched MPEG-TS stream. Channels DVR doesn't convert it,
// and the first video keyframe arrives in about a second.
- (NSURL *)streamURLForChannel:(NSString *)number;

// The channels in the named collection, in the collection's order, or every
// channel by number when the name is empty. Each is an NSDictionary with
// "number", "name" and, when the server has one, "logo" (a URL string).
// Collection items the server has no channel for, such as virtual channels,
// are left out.
- (NSArray *)channelsInCollection:(NSString *)collection error:(NSError **)error;

// The names of the server's channel collections, in the server's order.
- (NSArray *)collectionNames:(NSError **)error;

// The guide from start for the given hours, as channel number to airings
// sorted by start time. Each airing is an NSDictionary with "start" and
// "end" (NSDate), "title" and, when the guide has them, "summary" and
// "image" (a URL string).
- (NSDictionary *)guideStarting:(NSDate *)start hours:(int)hours error:(NSError **)error;

@end
