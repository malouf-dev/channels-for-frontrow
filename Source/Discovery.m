// Discovery.m
//
// Browse for the service type, resolve each server to a host name and port,
// then look up the host's IPv4 address. An IPv4 address avoids the IPv6
// link-local addresses that .local names can resolve to first.

#import <dns_sd.h>
#import <arpa/inet.h>
#import <errno.h>
#import <sys/select.h>
#import "Discovery.h"

// Waits for one reply on ref and handles it. NO on timeout or error.
static BOOL LTVHandleReply(DNSServiceRef ref, CFAbsoluteTime deadline)
{
    int socket = DNSServiceRefSockFD(ref);
    for (;;) {
        CFTimeInterval left = deadline - CFAbsoluteTimeGetCurrent();
        if (left <= 0)
            return NO;
        fd_set readable;
        FD_ZERO(&readable);
        FD_SET(socket, &readable);
        struct timeval wait = { (time_t)left, (suseconds_t)((left - (time_t)left) * 1e6) };
        int ready = select(socket + 1, &readable, NULL, NULL, &wait);
        if (ready > 0)
            return DNSServiceProcessResult(ref) == kDNSServiceErr_NoError;
        if (ready == 0 || errno != EINTR)
            return NO;
    }
}

static void DNSSD_API LTVBrowseReply(DNSServiceRef ref, DNSServiceFlags flags, uint32_t interface,
                                     DNSServiceErrorType error, const char *name, const char *type,
                                     const char *domain, void *context)
{
    if (error != kDNSServiceErr_NoError || !(flags & kDNSServiceFlagsAdd))
        return;
    [(NSMutableArray *)context addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                                          [NSString stringWithUTF8String:name], @"name",
                                          [NSString stringWithUTF8String:type], @"type",
                                          [NSString stringWithUTF8String:domain], @"domain",
                                          [NSNumber numberWithUnsignedInt:interface], @"interface",
                                          nil]];
}

typedef struct {
    char host[1025];
    uint16_t port;
    BOOL done;
} LTVResolved;

static void DNSSD_API LTVResolveReply(DNSServiceRef ref, DNSServiceFlags flags, uint32_t interface,
                                      DNSServiceErrorType error, const char *fullName, const char *host,
                                      uint16_t port, uint16_t txtLength, const unsigned char *txt, void *context)
{
    LTVResolved *resolved = context;
    if (error != kDNSServiceErr_NoError)
        return;
    strlcpy(resolved->host, host, sizeof resolved->host);
    resolved->port = ntohs(port);
    resolved->done = YES;
}

typedef struct {
    char address[INET_ADDRSTRLEN];
    BOOL done;
} LTVAddress;

static void DNSSD_API LTVAddressReply(DNSServiceRef ref, DNSServiceFlags flags, uint32_t interface,
                                      DNSServiceErrorType error, const char *host,
                                      const struct sockaddr *address, uint32_t ttl, void *context)
{
    LTVAddress *found = context;
    if (error != kDNSServiceErr_NoError || address == NULL || address->sa_family != AF_INET)
        return;
    inet_ntop(AF_INET, &((const struct sockaddr_in *)address)->sin_addr, found->address, sizeof found->address);
    found->done = YES;
}

NSArray *LTVFindChannelsServers(NSTimeInterval timeout)
{
    // Browse until the timeout, or a moment after the first answer so any
    // other servers can answer too.
    NSMutableArray *services = [NSMutableArray array];
    DNSServiceRef browse = NULL;
    if (DNSServiceBrowse(&browse, 0, 0, "_channels_dvr._tcp", "local.", LTVBrowseReply, services) != kDNSServiceErr_NoError)
        return services;
    CFAbsoluteTime deadline = CFAbsoluteTimeGetCurrent() + timeout;
    while (LTVHandleReply(browse, deadline))
        if ([services count] && deadline > CFAbsoluteTimeGetCurrent() + 0.3)
            deadline = CFAbsoluteTimeGetCurrent() + 0.3;
    DNSServiceRefDeallocate(browse);

    NSMutableArray *servers = [NSMutableArray array];
    NSMutableSet *names = [NSMutableSet set];
    for (NSDictionary *service in services) {
        // The same server can answer on more than one network interface.
        NSString *name = [service objectForKey:@"name"];
        if ([names containsObject:name])
            continue;
        uint32_t interface = [[service objectForKey:@"interface"] unsignedIntValue];

        LTVResolved resolved = { "", 0, NO };
        DNSServiceRef ref = NULL;
        if (DNSServiceResolve(&ref, 0, interface, [name UTF8String], [[service objectForKey:@"type"] UTF8String],
                              [[service objectForKey:@"domain"] UTF8String], LTVResolveReply, &resolved) == kDNSServiceErr_NoError) {
            CFAbsoluteTime until = CFAbsoluteTimeGetCurrent() + 2.0;
            while (!resolved.done && LTVHandleReply(ref, until))
                ;
            DNSServiceRefDeallocate(ref);
        }
        if (!resolved.done)
            continue;

        LTVAddress address = { "", NO };
        if (DNSServiceGetAddrInfo(&ref, 0, interface, kDNSServiceProtocol_IPv4, resolved.host,
                                  LTVAddressReply, &address) == kDNSServiceErr_NoError) {
            CFAbsoluteTime until = CFAbsoluteTimeGetCurrent() + 2.0;
            while (!address.done && LTVHandleReply(ref, until))
                ;
            DNSServiceRefDeallocate(ref);
        }

        NSString *host = [NSString stringWithUTF8String:resolved.host];
        NSString *reachable = address.done ? [NSString stringWithUTF8String:address.address] : host;
        [servers addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                            name, @"name",
                            host, @"host",
                            [NSString stringWithFormat:@"%@:%u", reachable, resolved.port], @"address",
                            nil]];
        [names addObject:name];
    }
    [servers sortUsingComparator:^NSComparisonResult(id a, id b) {
        return [[a objectForKey:@"name"] localizedCaseInsensitiveCompare:[b objectForKey:@"name"]];
    }];
    return servers;
}
