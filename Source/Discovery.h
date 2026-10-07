// Discovery.h
//
// Finds Channels DVR servers on the local network with Bonjour. Channels DVR
// Server announces itself as _channels_dvr._tcp. The Channels apps announce
// _channels_app._tcp, which is ignored.
//
// Uses the DNS-SD C API on the calling thread, so it doesn't depend on a run
// loop. It blocks, so call it from a background queue.

#import <Foundation/Foundation.h>

// Each server is an NSDictionary with "name" (the name set in Channels DVR),
// "host" (its Bonjour host name, such as dvr-server.local.) and "address"
// (IPv4 address and port, such as 192.168.0.20:8089). Sorted by name. Empty
// if none answer within timeout seconds.
NSArray *LTVFindChannelsServers(NSTimeInterval timeout);
