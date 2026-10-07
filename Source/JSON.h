// JSON.h
//
// A small JSON reader. Mac OS X 10.6 has none built in: NSJSONSerialization
// arrived in 10.7. Returns autoreleased NSDictionary, NSArray, NSString,
// NSNumber and NSNull objects, or nil with an error.

#import <Foundation/Foundation.h>

id LTVJSONParse(NSData *data, NSError **error);
