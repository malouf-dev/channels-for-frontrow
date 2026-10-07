# Builds Channels for Front Row: the Front Row plugin
# (ChannelsForFrontRow.frappliance) and its System Preferences pane
# (ChannelsForFrontRow.prefPane).
#
# Front Row is 32-bit only, and current Xcode can't build 32-bit Mac code, so
# the build runs on the old Mac itself, with Mac OS X 10.6.8 and Xcode 3.2.6.
#
# On your current Mac:
#   make imac              copy the source to the old Mac over SSH, then run
#                          make run there. Uses the SSH host alias set in
#                          local.mk, or old-mac
#   make imac IMAC=other   use another alias
#   make vlc               download VLC 2.0.10, then put a copy in
#                          ~/Library/Application Support/channels-for-frontrow
#                          on the old Mac
#   make package           build the installer on the old Mac and copy it to
#                          build/ here
#
# On the old Mac:
#   make                   build both into build/
#   make install           copy the plugin into Front Row and the pane into
#                          ~/Library/PreferencePanes
#   make run               install, then quit Front Row and System Preferences
#                          so they load the new builds
#   make install-vlc       copy VLC from the downloaded disk image into
#                          ~/Library/Application Support/channels-for-frontrow
#   make pkg               build the installer, with VLC included
#
# local.mk isn't in the repository. Put your own alias in it, for example:
#   IMAC = living-room-imac

-include local.mk
IMAC       ?= old-mac
REMOTE_DIR  = channels-for-frontrow
SYNC        = rsync -a --delete --exclude build --exclude .git --exclude .DS_Store ./ $(IMAC):$(REMOTE_DIR)/

# VLC 2.0.10 is VideoLAN's last 32-bit Intel build. The checksum matches the
# one VideoLAN publishes for this file.
VLC_VERSION = 2.0.10
VLC_DMG     = downloads/vlc-$(VLC_VERSION)-intel32.dmg
VLC_URL     = https://download.videolan.org/pub/videolan/vlc/$(VLC_VERSION)/macosx/vlc-$(VLC_VERSION)-intel32.dmg
VLC_SHA256  = 510516d2cb85538844113a581c49d9b8aff459c3de9669eeddd2bc7229908a1f
VLC_HOME    = $(HOME)/Library/Application Support/channels-for-frontrow

# Fails unless the file matches VLC_SHA256. The old Mac's shasum can't read
# a checksum list from a pipe, so this compares the digest itself.
CHECK_VLC = test "`shasum -a 256 < $(1) | cut -c1-64`" = $(VLC_SHA256) || \
	{ echo "$(1) doesn't match VLC $(VLC_VERSION)'s checksum."; exit 1; }

NAME     = ChannelsForFrontRow
VERSION  = $(shell /usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)
PKG      = build/$(NAME)-$(VERSION).pkg
SDK      = /Developer/SDKs/MacOSX10.6.sdk
CC       = gcc-4.2
WARNINGS = -std=gnu99 -O2 -g -Wall -Wextra -Wno-unused-parameter

# The plugin: 32-bit Intel only, like Front Row.
BUNDLE     = build/$(NAME).frappliance
EXECUTABLE = $(BUNDLE)/Contents/MacOS/$(NAME)
SOURCES    = $(wildcard Source/*.m)
HEADERS    = $(wildcard Source/*.h)
ARCH       = -arch i386 -isysroot $(SDK) -mmacosx-version-min=10.6
CFLAGS     = $(ARCH) $(WARNINGS)
LDFLAGS    = $(ARCH) -bundle -F/System/Library/PrivateFrameworks \
             -framework BackRow -framework QuartzCore -framework OpenGL \
             -framework ApplicationServices -framework IOKit -framework Foundation

# The pane: 32- and 64-bit Intel. The 64-bit System Preferences runs with
# garbage collection, so the pane supports it (-fobjc-gc) and also works
# without it in the 32-bit one. It shares the server and settings code.
PANE            = build/$(NAME).prefPane
PANE_EXECUTABLE = $(PANE)/Contents/MacOS/$(NAME)
PANE_SOURCES    = $(wildcard Pane/Source/*.m) Source/Settings.m Source/Discovery.m \
                  Source/ChannelsDVR.m Source/JSON.m
PANE_HEADERS    = $(wildcard Pane/Source/*.h) $(HEADERS)
PANE_ARCH       = -arch i386 -arch x86_64 -isysroot $(SDK) -mmacosx-version-min=10.6 -fobjc-gc
PANE_CFLAGS     = $(PANE_ARCH) $(WARNINGS) -ISource
PANE_LDFLAGS    = $(PANE_ARCH) -bundle -framework PreferencePanes -framework Cocoa

FRONTROW     = /System/Library/CoreServices/Front Row.app
PLUGINS      = $(FRONTROW)/Contents/PlugIns
PANES        = $(HOME)/Library/PreferencePanes

all: $(EXECUTABLE) $(PANE_EXECUTABLE)

# Each target is the executable, not the bundle folder, so a failed compile
# leaves nothing that make would mistake for a finished build.
$(EXECUTABLE): $(SOURCES) $(HEADERS) Info.plist English.lproj/InfoPlist.strings \
              Artwork/ApplianceIcon.png Artwork/BlurredApplianceIcon.png
	rm -rf $(BUNDLE) build/$(NAME).dSYM
	mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources
	cp Info.plist $(BUNDLE)/Contents/
	cp -R English.lproj $(BUNDLE)/Contents/Resources/
	cp Artwork/ApplianceIcon.png Artwork/BlurredApplianceIcon.png $(BUNDLE)/Contents/Resources/
	$(CC) $(CFLAGS) $(LDFLAGS) -o $(EXECUTABLE) $(SOURCES)
	mv $(EXECUTABLE).dSYM build/

$(PANE_EXECUTABLE): $(PANE_SOURCES) $(PANE_HEADERS) Pane/Info.plist Pane/manage Artwork/ChannelsForFrontRow.png
	rm -rf $(PANE)
	mkdir -p $(PANE)/Contents/MacOS $(PANE)/Contents/Resources
	cp Pane/Info.plist $(PANE)/Contents/
	cp Pane/manage Artwork/ChannelsForFrontRow.png $(PANE)/Contents/Resources/
	$(CC) $(PANE_CFLAGS) $(PANE_LDFLAGS) -o $(PANE_EXECUTABLE) $(PANE_SOURCES)

# The plugin folder must already exist and belong to the build user (see
# README), so installing needs no admin password.
install: $(EXECUTABLE) $(PANE_EXECUTABLE)
	rm -rf "$(PLUGINS)/$(NAME).frappliance/Contents"
	cp -R $(BUNDLE)/Contents "$(PLUGINS)/$(NAME).frappliance/"
	mkdir -p "$(PANES)"
	rm -rf "$(PANES)/$(NAME).prefPane"
	cp -R $(PANE) "$(PANES)/"

# Front Row has to be opened from the old Mac's own session (Command-Escape or the
# Apple Remote). Opened from SSH, it starts hidden and can't claim the remote.
run: install
	@killall "Front Row" 2>/dev/null || true
	@killall "System Preferences" 2>/dev/null || true
	@echo "Installed. Open Front Row with Command-Escape or the remote, and Channels for Front Row in System Preferences."

# VLC.app and its licence, taken from VideoLAN's disk image. VLC.app is
# touched so make doesn't think the 2014 copy is older than the download.
build/vlc/VLC.app: $(VLC_DMG)
	@$(call CHECK_VLC,$(VLC_DMG))
	rm -rf build/vlc build/vlc.tmp build/vlc-mount
	mkdir -p build/vlc.tmp build/vlc-mount
	hdiutil attach -quiet -nobrowse -readonly -noautoopen -mountpoint "$(CURDIR)/build/vlc-mount" $(VLC_DMG)
	ditto build/vlc-mount/VLC.app build/vlc.tmp/VLC.app && cp build/vlc-mount/Goodies/COPYING build/vlc.tmp/COPYING; \
		status=$$?; hdiutil detach -quiet "$(CURDIR)/build/vlc-mount"; exit $$status
	rmdir build/vlc-mount
	touch build/vlc.tmp/VLC.app
	mv build/vlc.tmp build/vlc

# A developer's own copy of VLC. The plugin looks in ~/Library first, then in
# /Library, where the installer puts its copy. An existing copy is kept.
install-vlc: build/vlc/VLC.app
	@if [ -e "$(VLC_HOME)/VLC.app" ]; then \
		echo "VLC is already in $(VLC_HOME). Remove that copy first to replace it."; \
	else \
		mkdir -p "$(VLC_HOME)" && ditto build/vlc/VLC.app "$(VLC_HOME)/VLC.app" && \
		echo "Installed VLC $(VLC_VERSION) in $(VLC_HOME)."; \
	fi

# The installer. Its payload is laid out from the startup disk's root. Every
# bundle is marked as not relocatable, so Installer never puts this VLC over
# another copy of VLC that it finds elsewhere, such as in Applications.
# pkgbuild also marks the package to overwrite permissions, which would reset
# / and /Library to the payload's root:wheel 755 and take away admin users'
# write access. pkgbuild has no option for it, so PackageInfo is edited.
pkg: $(EXECUTABLE) $(PANE_EXECUTABLE) build/vlc/VLC.app Installer/postinstall Installer/vlc-cache.c Installer/Distribution.xml
	rm -rf build/pkg $(PKG)
	mkdir -p "build/pkg/root$(PLUGINS)" build/pkg/root/Library/PreferencePanes \
		"build/pkg/root/Library/Application Support/channels-for-frontrow" build/pkg/scripts
	ditto $(BUNDLE) "build/pkg/root$(PLUGINS)/$(NAME).frappliance"
	ditto $(PANE) build/pkg/root/Library/PreferencePanes/$(NAME).prefPane
	ditto build/vlc "build/pkg/root/Library/Application Support/channels-for-frontrow"
	cp Installer/postinstall build/pkg/scripts/
	$(CC) $(ARCH) -std=gnu99 -O2 -Wall -Wextra -o build/pkg/scripts/vlc-cache Installer/vlc-cache.c
	pkgbuild --analyze --root build/pkg/root build/pkg/components.plist
	i=0; while /usr/libexec/PlistBuddy -c "Print :$$i" build/pkg/components.plist >/dev/null 2>&1; do \
		/usr/libexec/PlistBuddy -c "Set :$$i:BundleIsRelocatable false" build/pkg/components.plist 2>/dev/null || \
		/usr/libexec/PlistBuddy -c "Add :$$i:BundleIsRelocatable bool false" build/pkg/components.plist; \
		i=$$((i+1)); done; echo "$$i bundles marked as not relocatable"
	pkgbuild --root build/pkg/root --component-plist build/pkg/components.plist --scripts build/pkg/scripts \
		--identifier channels-for-frontrow.pkg --version $(VERSION) --install-location / --ownership recommended \
		build/pkg/$(NAME).pkg
	pkgutil --expand build/pkg/$(NAME).pkg build/pkg/expanded
	sed -i '' 's/overwrite-permissions="true"/overwrite-permissions="false"/' build/pkg/expanded/PackageInfo
	grep -q 'overwrite-permissions="false"' build/pkg/expanded/PackageInfo
	rm build/pkg/$(NAME).pkg
	pkgutil --flatten build/pkg/expanded build/pkg/$(NAME).pkg
	productbuild --distribution Installer/Distribution.xml --package-path build/pkg $(PKG)

clean:
	rm -rf build

.PHONY: all install run install-vlc pkg clean

# These run on your current Mac.
imac:
	$(SYNC)
	ssh $(IMAC) 'make -C $(REMOTE_DIR) run'

# The old Mac can't open VideoLAN's secure site, so VLC is downloaded here and
# copied across with the source. Git ignores downloads/.
$(VLC_DMG):
	mkdir -p downloads
	curl -fL -o $@.part $(VLC_URL)
	@$(call CHECK_VLC,$@.part)
	mv $@.part $@

vlc: $(VLC_DMG)
	$(SYNC)
	ssh $(IMAC) 'make -C $(REMOTE_DIR) install-vlc'

package: $(VLC_DMG)
	$(SYNC)
	ssh $(IMAC) 'make -C $(REMOTE_DIR) pkg'
	mkdir -p build
	scp $(IMAC):$(REMOTE_DIR)/$(PKG) build/

.PHONY: imac vlc package
