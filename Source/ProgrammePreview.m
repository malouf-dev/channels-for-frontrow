// ProgrammePreview.m

#import <objc/runtime.h>
#import <objc/message.h>
#import "ProgrammePreview.h"

@implementation LTVProgrammeAsset

- (id)initWithTitle:(NSString *)title summary:(NSString *)summary next:(NSString *)next
              image:(BRImage *)image imageID:(NSString *)imageID
{
    if ((self = [super initWithMediaProvider:nil])) {
        _title = [title copy];
        _summary = [summary copy];
        _next = [next copy];
        _image = [image retain];
        _imageID = [imageID copy];
    }
    return self;
}

- (void)dealloc
{
    [_title release];
    [_summary release];
    [_next release];
    [_image release];
    [_imageID release];
    [super dealloc];
}

// Read by BRMetadataPreviewController and its BRCoverArtImageLayer.
- (NSString *)title             { return _title; }
- (NSString *)mediaSummary      { return _summary; }
- (NSString *)assetID           { return _imageID ? _imageID : _title; }
- (NSString *)coverArtID        { return _imageID; }
- (BRImage *)coverArt           { return _image; }
- (BRImage *)coverArtNoDefault  { return _image; }
- (BOOL)hasCoverArt             { return _image != nil; }
- (NSString *)nextTitle         { return _next; }

@end

// Fills the preview's text: the title, the summary and a "Next" line.
// BRMetadataPreviewController calls this after the text's short pause.
@interface LTVProgrammePopulator : NSObject
@end

@implementation LTVProgrammePopulator

- (void)populateLayer:(BRMetadataLayer *)layer fromAsset:(LTVProgrammeAsset *)asset
{
    [layer setTitle:[asset title]];
    [layer setSummary:[asset mediaSummary] ? [asset mediaSummary] : @""];
    if ([asset nextTitle])
        [layer setMetadata:[NSArray arrayWithObject:[asset nextTitle]] withLabels:[NSArray arrayWithObject:@"Next"]];
}

@end

// Stands in for Front Row's BRMetadataPopulatorFactory singleton. Front Row's
// callers don't release the populator they get, and the real factory keeps
// its own, so this one keeps a single populator for its whole life.
@interface LTVPopulatorFactory : NSObject {
    id _original;
    LTVProgrammePopulator *_populator;
}
@end

@implementation LTVPopulatorFactory

- (id)initWithOriginal:(id)original
{
    if ((self = [super init])) {
        _original = [original retain];
        _populator = [[LTVProgrammePopulator alloc] init];
    }
    return self;
}

- (id)populatorForAsset:(id)asset
{
    if ([asset isKindOfClass:[LTVProgrammeAsset class]])
        return _populator;
    return [_original populatorForAsset:asset];
}

// Everything else goes to Front Row's own factory.
- (id)forwardingTargetForSelector:(SEL)selector
{
    return _original;
}

@end

void LTVInstallProgrammePopulator(void)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // BRMetadataPopulatorFactory isn't exported, so it can't be named in code.
        Class factoryClass = objc_getClass("BRMetadataPopulatorFactory");
        id original = factoryClass ? objc_msgSend(factoryClass, @selector(sharedInstance)) : nil;
        if (original == nil) {
            NSLog(@"Live TV: no BRMetadataPopulatorFactory, so previews will have no text");
            return;
        }
        LTVPopulatorFactory *standIn = [[LTVPopulatorFactory alloc] initWithOriginal:original];
        objc_msgSend(factoryClass, @selector(setSingleton:), standIn);
    });
}
