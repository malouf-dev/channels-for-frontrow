# CLAUDE.md for channels-for-frontrow

Read README.md first. It covers the aim, Front Row's three plugin rules and the build setup.

If `CLAUDE.local.md` exists, read it too. It holds the developer's own machines, server and test notes, and it isn't in the repository. Keep personal details there, never in this file, the README or the code.

## Names

- The project is Channels for Front Row. The bundles are `ChannelsForFrontRow.frappliance` and `ChannelsForFrontRow.prefPane`, and System Preferences shows the pane as Channels for Front Row.
- Front Row's main menu item is Live TV. The code's class prefix `LTV` and log prefix `Live TV:` come from it, and these notes and the code comments call the plugin Live TV.
- Internal identifiers use `channels-for-frontrow`: the settings domain, the VLC folder in Application Support, and both bundle identifiers.

## Build and check

- Build, install and quit Front Row: `make imac` from the repository folder. It builds on the old Mac whose SSH alias is set in `local.mk` (not in the repository). Then the developer opens Front Row on the old Mac with Command-Escape or the remote. Never open Front Row over SSH. It starts hidden and takes the remote's service away from the real session.
- The old Mac runs Mac OS X 10.6.8 with Xcode 3.2.6. Its copy of VLC 2.0.10 is at `~/Library/Application Support/channels-for-frontrow/VLC.app`.
- SSH to a `.local` name needs Claude Code's sandbox turned off, because the sandbox blocks those lookups.
- To see the old Mac's screen: `ssh ALIAS 'screencapture -x /tmp/live-tv.png'`, then copy it back with `scp`. This works over SSH.
- To read Live TV's log: `ssh ALIAS 'syslog -k Time ge -5m' | grep "Live TV:"`. Every Live TV log line starts with `Live TV:`.

## Code style

- Objective-C 2.0 with manual retain and release. 32-bit Mac code on 10.6 can't use ARC.
- gcc 4.2, i386 only, 10.6 SDK. One plain Makefile, no Xcode projects.
- No properties. Declare ivars explicitly, with an underscore prefix. Class extensions can declare methods but not ivars on this runtime.
- Blocks and Grand Central Dispatch are available on 10.6. A copied block retains the objects it uses, which the player relies on.
- Live TV's own classes use the `LTV` prefix. The principal class must be named `RUIYTAppliance`.
- Before you add a subclass of a BackRow class, add the class to `BackRow.h` with a padding ivar of its real size, and add a size check to `Appliance.m`. The i386 runtime has fragile ivars, so a wrong size corrupts memory. Read real sizes from `instance_size` in `otool -ov` output.
- BackRow classes that aren't exported (`nm` shows no `.objc_class_name_` symbol) can't be named in code. Get them with `objc_getClass()`.

## Player

- `LTVPlayerController` is a `BRController` subclass. It plays `/devices/ANY/channels/NUMBER/stream.mpg`, the untouched MPEG-TS stream, with VLC's engine.
- `LTVVLC` (VLC.m) finds VLC.app in `~/Library/Application Support/channels-for-frontrow/` or `/Library/Application Support/channels-for-frontrow/`, opens `libvlc.5.dylib` with `dlopen()` and creates one VLC instance for the life of Front Row. The channel menu starts it in the background.
- Every libvlc call goes through `LTVVLC`'s serial queue, never Front Row's main thread. The blocks on that queue keep the player controller alive, so stopping finishes before the controller can go away.
- `LTVVideoRenderer` draws the pictures. VLC's memory output writes UYVY pictures at the screen's size. On display, the renderer copies the picture under a mutex. There's one renderer for the life of Front Row, so its texture is made once per OpenGL context.
- The renderer sits in Front Row's video slot: `[[BRRenderScene sharedInstance] setPlaybackDelegate:]`. Each frame, BRRenderScene asks it `-newFrameForTime:`, then calls `-drawFrameInBounds:` in Front Row's own OpenGL context, before it draws the interface layers on top. The player also calls `setBackgroundRemoved:YES` while video shows. Front Row's own `BRVideoPlayerController` and `BRPhotoPlayerController` do the same with their host layers, and reverse both when they leave.
- `-drawFrameInBounds:` saves and restores every bit of OpenGL state it changes, because Front Row draws its interface into the same context next.
- UYVY uploads with `GL_YCBCR_422_APPLE` and `GL_UNSIGNED_SHORT_8_8_APPLE`. A red and blue test picture on a 2011 iMac's Radeon HD 6750M confirmed it. The `_REV_` type turns both colours green.
- A `CAOpenGLLayer` can't be used. It never gets an OpenGL context inside Front Row: creating its pixel format fails with "invalid display", because Front Row has captured the displays. Sound played but no picture showed. `QTMovieLayer` worked only because it's a plain `CALayer` subclass, not an OpenGL layer.
- Options: `:network-caching=500` and `libvlc_video_set_deinterlace(player, "yadif2x")`. Instance arguments include `--ignore-config`, so a user's own VLC preferences don't apply.
- libvlc events: `libvlc_MediaPlayerEndReached` is 0x109 and `libvlc_MediaPlayerEncounteredError` is 0x10A. Either one stops the player and opens it again after a second, up to three times in a row. A picture on screen resets the count.
- From the writable copy in `~/Library`, VLC starts in 0.07 seconds.
- A stream starts mid-packet, so the decoder's first pictures refer to frames that were never sent. It fills those gaps with zeros, which show as green blocks. VLC's timing also takes a moment to settle, which shows as a stall, and the sound used to start before the picture.
- So each stream starts hidden and silent. The renderer shows it once at least 1 second has passed since its first picture and three pictures in a row have had no zero-luma, zero-chroma samples (every 32nd pixel pair on every 8th row; studio-range video never goes below 16). After 3 seconds it shows it anyway. Then the picture fades in from black over 0.8 seconds (`LTVFadeInTime`, drawn with `GL_MODULATE` and a grey level), and the player ramps VLC's own volume from 0 to 100 in 10 steps over the same 0.8 seconds. 0.5 seconds felt abrupt. The Mac's volume isn't touched.
- Measured with `vlccheck`: on one channel the first 21 pictures were heavily green, and the green was gone from picture 33, about two-thirds of a second at 50 a second. Two other channels had none from the first picture. Turning off `--ffmpeg-hurry-up` didn't help.
- `libvlc_audio_set_volume(player, 0)` before `play` does keep the start silent. Tested by capturing VLC's decoded sound with `libvlc_audio_set_callbacks`: silent from the first sound at 0.75 seconds, normal loudness once the volume went to 100.
- The sound's fade steps run on the VLC queue with `dispatch_after`. Each start of a player gets a new generation number, so a step left over from a stream that was retried does nothing.

## Menu and guide

- Settings are in the preferences domain `channels-for-frontrow`: `ChannelsServer` (host:port, optional) and `ChannelCollection` (a collection name; every channel if not set). The menu re-reads them each time it opens, because Front Row keeps running in the background.
- With no `ChannelsServer`, the menu finds the server with Bonjour each time it opens (Discovery.m). Channels DVR Server announces `_channels_dvr._tcp`; the Channels apps announce `_channels_app._tcp`, which is ignored. Discovery uses the DNS-SD C API with `select()` on a background queue, so it doesn't depend on Front Row's run loop. It resolves the server to its IPv4 address, because `.local` names can resolve to IPv6 link-local addresses first. In testing it found the server in 0.3 seconds. With several servers, it takes the one named in `ChannelsServerName`, or else the first by name.
- `LTVChannelsDVR` (ChannelsDVR.m) does the HTTP calls with blocking `NSURLConnection` requests on a background queue. `JSON.m` is a small JSON reader, because 10.6 has none.
- The menu loads the channels first, then six hours of guide. Now and next are worked out from the cached guide each time a row is highlighted. After the guide arrives, the menu calls `-updatePreviewController` to redraw the current preview.
- The channel list reloads only when Live TV opens, so rows never move while you browse. The guide reloads in the background once it's over 30 minutes old. That's checked when you come back from a channel (`-wasExhumedByPoppingController:`) and by a check that runs a second after each minute while the menu is on screen. A failed reload keeps the old guide and is tried again at the next minute.
- The minute check also redraws the highlighted preview once its programme ends, or once the next one starts when nothing is on. It skips its work while a channel plays on top (`-wasBuriedByPushingController:`), and stops when the menu is popped or is no longer in a stack. It uses `dispatch_after` on the main queue, which BackRow's run loop serves.
- Each channel row's preview is Front Row's own `BRMetadataPreviewController`, given an `LTVProgrammeAsset` (a `BRBaseMediaAsset` subclass, ProgrammePreview.m). It shows the programme's picture with a reflection, then the programme on now as the title, its summary and a "Next" line with the next programme's title. Front Row lays it out with its own margins. `setShowsMetadataImmediately:YES` shows the text straight away, without the pause Front Row's other menus have.
- The preview's text comes from a populator. `BRMetadataPopulatorFactory` picks populators by media type, and none fits a live programme. `LTVInstallProgrammePopulator()` replaces the factory's singleton (`+setSingleton:`) with a stand-in that returns Live TV's populator for `LTVProgrammeAsset` and forwards everything else to the original factory. Callers don't release the populator they get.
- The picture is the programme's `Image` from the guide, or the channel's `logo_url` when there's none. HDHomeRun's picture server (`img.hdhomerun.com`) answers plain HTTP, which Live TV uses. Pictures are 480x270 and download in the background into a cache. When one arrives, the preview is redrawn if that row is still highlighted. `BRCoverArtImageLayer` reads the picture from the asset's `-coverArt`.
- Channels that arrive during the menu's opening animation fill a list with no size yet, and the list doesn't redraw afterwards. The menu reloads the list in `-wasPushed`, once it's fully on screen.
- Error messages from `LTVChannelsDVR` appear as a menu row, which fits about 26 characters, so they're short ("Can't reach Channels DVR", "Collection not found"). The details go to the log. An empty collection shows "No channels found".
- Hidden channels are left out. So are collection items that aren't real channel numbers, such as `virtual-68`, because `/api/v1/channels` doesn't list them.
- Measured on a 2011 iMac: a 25-channel collection loads in 0.06 seconds, and a six-hour guide (1.9 MB, 105 channels) in 0.15 seconds, including the JSON parsing.
- Apple's gcc 4.2 needs sort blocks typed exactly as `NSComparator`: `^NSComparisonResult(id a, id b)`.

## Preference pane

- `Pane/` builds `ChannelsForFrontRow.prefPane` for i386 and x86_64. The 64-bit System Preferences on 10.6 runs with garbage collection (its image flags are 0x6), and Apple's panes support it, so the pane is built with `-fobjc-gc` and its code works with or without collection. CF objects from `CFPreferencesCopyAppValue` go through `NSMakeCollectable`.
- The view is built in code (no nib), in a flipped view, following the approved mockup at `scratch/mockups/live-tv-pane.html`. Status lines that are empty take no space. The beads are 10.6's `NSImageNameStatusAvailable` and `NSImageNameStatusUnavailable`.
- It shares Settings.m, Discovery.m, ChannelsDVR.m and JSON.m with the plugin. Settings: `ChannelsServer` (typed address; a missing port becomes 8089), `ChannelsServerName` (which Bonjour server, when there are several; the plugin honours it) and `ChannelCollection`.
- The pane's label in System Preferences is `Channels for&#10;Front Row` in `Pane/Info.plist`. Without the line break, System Preferences cuts it to "Channe…nt Row". Apple's own panes break their labels the same way, such as "Parental\nControls".
- During development, `make install` puts the pane in `~/Library/PreferencePanes` with this Mac's TV Shows icon as `ChannelsForFrontRow.png`. The installer will use `/Library/PreferencePanes`.
- To see it from here: `osascript -e 'tell application "System Preferences" to set current pane to pane id "channels-for-frontrow.pane"'` over SSH, then `screencapture`. That works without access for assistive devices. Clicking controls from a script would need that access, which is usually off.
- Checked: finding and connecting to a server automatically, a typed working address, a wrong address (the error shows after the 15-second timeout), and changing the collection. Not checked: no server found, and several servers.

## BackRow facts confirmed so far

- Front Row on 10.6 runs 32-bit only. BackRow lives at `/System/Library/PrivateFrameworks/BackRow.framework`.
- Plugin loading is in `-[BRApplianceManager _loadApplianceInfoAtPath:]`, which holds the class-name list. The identifier rule is in `-[BRFeatureManager isFeatureEnabled:]`.
- An appliance subclasses `BRAppliance` and returns its root controller from `-applianceController`. The main menu name comes from `CFBundleName` in `English.lproj/InfoPlist.strings`.
- A menu subclasses `BRMediaMenuController` and acts as its list's datasource: `itemCount`, `itemForRow:`, `titleForRow:`, `heightForRow:`, `rowSelectable:`, `itemSelected:` and `previewControlForItem:`. Rows are `BRTextMenuItemLayer`.
- BackRow draws the whole screen with `CARenderer` into an OpenGL context, on its own render thread, and captures the displays. Video isn't a layer: `BRRenderScene` calls a playback delegate to draw it straight into that context (see the Player section).
- To play with Front Row's own player: make a `BRSimpleMediaAsset`, get a player from `+[BRMediaPlayerManager playerForMediaAsset:error:]`, call `-setMedia:error:`, hand the player to a `BRVideoPlayerController` and push that onto `[self stack]`.
- `-[BRSimpleMediaAsset initWithMediaURL:]` takes an NSURL. `-mediaURL` returns it as a string with `absoluteString`, and `BRVideo` turns that back into a URL with `+[NSURL URLWithString:]`. Passing a string to the init method crashes Front Row as soon as playback starts.
- For movies, the player manager returns `FRVideoPlayer`. It's a `BRQTKitVideoPlayer` subclass inside the Front Row app. It allows all movie types and turns off QuickTime's persistent cache. Plain `BRQTKitVideoPlayer` allows neither.
- `-[BRQTKitVideoPlayer movieAttributes]` returns nil. It's a hook for subclasses. `-[BRVideo _createMovieWithAttributes:error:]` merges it into the QTMovie attributes, then uses the movie's QuickTime 7 handles.
- The Front Row app is built without position-independent code, and its method names are stripped. `tools/backrow/annotate.py` handles both, but finding a method means matching addresses against `method_imp` in `otool -ov` output.
- Crash reports are in `~/Library/Logs/DiagnosticReports/Front Row_*.crash` on the old Mac. An Objective-C exception shows up as a crash inside a Core Animation callback. The useful line is the exception message in the system log, just before the crash.

## Reading BackRow

BackRow has no headers. Copy it from the old Mac and use the scripts in `tools/backrow`. Each script's docstring shows how to run it.

```bash
scp ALIAS:/System/Library/PrivateFrameworks/BackRow.framework/Versions/A/BackRow "$TMPDIR/BackRow"
```

## Remote

- `-[BREvent remoteAction]` numbers, from the jump table in `-[BRMediaPlayerController brEventAction:]`: 2 is volume up, 3 volume down, 5 left, 6 right, 10 skip ahead, 11 skip back, 12 pause, 13 play, 14 stop, 17 next chapter, 18 previous chapter. `-value` is 1 on press and 0 on release.
- Front Row's player changes volume through `BRSettingsFacade` `systemVolume` in steps of 1/16, then calls `-[BREventManager retriggerCurrentEvent]` so a held button repeats. It then posts `kBRMediaPlayerVolumeChanged` (`@"BRMPVolumeChanged"`) with the player as the object.
- The volume bar is `BRVolumeControl`. `-[BRVideoPlayerController _addVolumeControl]` creates one, names it `@"volume"`, calls `-setPlayer:` and adds it as a control. `-setPlayer:` observes that player's volume notification. When the bar shows, it reads `-volume` from the player. `BRVideoPlayerLayoutManager` positions the control by its name.
- `LTVPlayerController` does the same, with itself as the player.

## Channels DVR

- The API needs no login on the local network. These endpoints are confirmed:
  - `/dvr/collections/channels`: collections. Each item is a channel number.
  - `/api/v1/channels`: id, name, number and logo URL for each channel.
  - `/devices/ANY/guide?time=UNIXTIME&duration=SECONDS`: an array with one entry per channel, `Channel` (`Number`, `Name`, `CallSign`, ...) and `Airings` (`Time`, `Duration`, `Title`, `Summary`, `Image`, `Genres`, ...). Each airing also carries a large `Raw` XMLTV field. `/devices/ANY/guide/now` gives only what's on now.
  - `/devices/ANY/channels/NUMBER/stream.mpg`: the untouched stream that Live TV plays. On a cold channel the first bytes arrived after 0.8 seconds and the first video keyframe after 0.93 seconds. It's MPEG-TS with 1080i50 H.264 High video, AC3 5.1 audio, teletext and data streams, at about 4 Mbit/s.
  - `/devices/ANY/channels/NUMBER/hls/stream.m3u8`: a converted HLS stream. Live TV no longer uses it.
- `/devices` includes the tuner's `DeviceAuth` code. Never print it. Filter that endpoint with `jq` if you need it.
- Every stream uses one tuner. With an HDHomeRun DVB-T tuner, most channels were H.264 with AC3, AAC or MPEG audio, and one was MPEG-2.
- Performance figures in this file come from a 21.5-inch mid-2011 iMac: Core i5-2400S (4 cores at 2.5 GHz), 8 GB of memory, AMD Radeon HD 6750M, 1920x1080 screen.

## VLC engine test

Tested with `tools/vlccheck`, outside Front Row, over SSH. VLC 2.0.10 is VideoLAN's last 32-bit Intel build (`vlc-2.0.10-intel32.dmg`, 33.6 MB, SHA-256 `510516d2…08a1f`).

- `libvlc.5.dylib` loads with `dlopen()` straight from `VLC.app/Contents/MacOS/lib`. The libraries find each other with `@loader_path`. Set `VLC_PLUGIN_PATH` to `VLC.app/Contents/MacOS/plugins` first. `VLC.app/Contents/MacOS/include` has the libvlc headers.
- Pictures go to memory with `libvlc_video_set_callbacks` and `libvlc_video_set_format` (RV32 or UYVY). RV32 is B, G, R, X in memory.
- Starting the engine from the read-only disk image took 3.1 seconds, while it scanned its plugins.
- First picture after `play`, on cold channels with a 500 ms network buffer: 0.7 to 1.7 seconds. With 1000 ms, 1.06 seconds.
- Processor use, out of 400% for four cores: MPEG-2 SD 20%; 1080i H.264 without deinterlacing 38 to 44%, with yadif 49 to 57%, with yadif2x 78% at about 45 frames a second.
- `--deinterlace` on the command line does nothing with memory output. `libvlc_video_set_deinterlace(player, "yadif2x")` works.

## Why not QuickTime and HLS

Live TV first had Channels DVR convert channels to HLS and played them with QuickTime. These findings explain the switch to VLC.

- Front Row's standard player can't play HLS. It shows "The selected video could not be played. The format was not recognized." Its QuickTime 7 engine has no HLS support.
- Front Row's player can't use playback mode (`QTMovieOpenForPlaybackAttribute`). `BRVideo` calls `-[QTMovie quickTimeMovie]`, which raises `QTDisallowedForInitializationPurposeException` in that mode, and Front Row crashes.
- A playback-mode QTMovie in a `QTMovieLayer` did play inside Front Row, at 1920x1080. But a cold channel took 16 to 17 seconds to start:
  - Channels DVR lists its first segment about 3 seconds after the request, then adds about one 1.1-second segment each second.
  - QuickTime X downloads nothing until the playlist holds about 5 segments, around 7 seconds in. It starts from the first segment.
  - It reports "playthrough OK" (load state 20000) once it holds about 10 seconds of video.
  - Calling `play` early, rewriting `#EXTINF` durations, and marking the playlist `#EXT-X-PLAYLIST-TYPE:EVENT` changed nothing. The `ssize` option didn't shorten segments.
  - With the server's session already running, it started in about 2.5 seconds. Channels DVR stops a session after about 35 seconds without requests.
- OSStatus -12641 is what QuickTime X reports for a playlist that's marked finished (`#EXT-X-ENDLIST`) while it holds almost nothing.
- QuickTime X decodes in software on a 2011 iMac. Its AMD graphics has no hardware decoding on 10.6.
- `tools/hlscheck` tests a stream with QuickTime outside Front Row.

## Open questions

- Whether the display sleeps during long playback. Live TV doesn't tell the system it's playing video yet. Front Row's player does this in `-[BRVideoPlayerController _suppressScreenSaver]`.
- VLC scales every source to the screen size. That suits 16:9 broadcasts, but a 4:3 source would stretch.
- The graphics card converts colour with the standard-definition matrix (BT.601). HD broadcasts use BT.709, so colours may be slightly off.
- Start-up artefacts that aren't green, such as grey or smeared blocks, aren't detected. None have been reported.
