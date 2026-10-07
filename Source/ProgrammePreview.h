// ProgrammePreview.h
//
// The preview for a highlighted channel, shown with Front Row's own
// BRMetadataPreviewController: the programme's picture with a reflection,
// then its title, summary and what's on next, with Front Row's margins.
//
// BRMetadataPreviewController gets its text from a "populator" that
// BRMetadataPopulatorFactory picks by media type, and none of Front Row's
// populators fits a live programme. LTVInstallProgrammePopulator() puts a
// stand-in factory in place. It returns Live TV's populator for Live TV's
// assets and passes every other request to Front Row's own factory, so the
// Movies, TV Shows and other menus don't change.

#import "BackRow.h"

@interface LTVProgrammeAsset : BRBaseMediaAsset {
    NSString *_title;
    NSString *_summary;
    NSString *_next;
    BRImage *_image;
    NSString *_imageID;
}

// image may be nil while it downloads. imageID names it, such as its URL.
- (id)initWithTitle:(NSString *)title summary:(NSString *)summary next:(NSString *)next
              image:(BRImage *)image imageID:(NSString *)imageID;

- (NSString *)nextTitle;

@end

// Call once, before the first preview. Safe to call again.
void LTVInstallProgrammePopulator(void);
