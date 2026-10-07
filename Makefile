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
#
# On the old Mac:
#   make                   build both into build/
#   make install           copy the plugin into Front Row and the pane into
#                          ~/Library/PreferencePanes
#   make run               install, then quit Front Row and System Preferences
#                          so they load the new builds
#
# local.mk isn't in the repository. Put your own alias in it, for example:
#   IMAC = living-room-imac

-include local.mk
IMAC       ?= old-mac
REMOTE_DIR  = channels-for-frontrow

NAME     = ChannelsForFrontRow
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
             -framework ApplicationServices -framework Foundation

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
TV_RESOURCES = $(PLUGINS)/TV.frappliance/Contents/Resources
PANES        = $(HOME)/Library/PreferencePanes

all: $(EXECUTABLE) $(PANE_EXECUTABLE)

# Each target is the executable, not the bundle folder, so a failed compile
# leaves nothing that make would mistake for a finished build.
$(EXECUTABLE): $(SOURCES) $(HEADERS) Info.plist English.lproj/InfoPlist.strings
	rm -rf $(BUNDLE) build/$(NAME).dSYM
	mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources
	cp Info.plist $(BUNDLE)/Contents/
	cp -R English.lproj $(BUNDLE)/Contents/Resources/
	$(CC) $(CFLAGS) $(LDFLAGS) -o $(EXECUTABLE) $(SOURCES)
	mv $(EXECUTABLE).dSYM build/

$(PANE_EXECUTABLE): $(PANE_SOURCES) $(PANE_HEADERS) Pane/Info.plist
	rm -rf $(PANE)
	mkdir -p $(PANE)/Contents/MacOS $(PANE)/Contents/Resources
	cp Pane/Info.plist $(PANE)/Contents/
	$(CC) $(PANE_CFLAGS) $(PANE_LDFLAGS) -o $(PANE_EXECUTABLE) $(PANE_SOURCES)

# The plugin folder must already exist and belong to the build user (see
# README), so installing needs no admin password. Both use this Mac's TV Shows
# icon as a placeholder until the project has its own.
install: $(EXECUTABLE) $(PANE_EXECUTABLE)
	rm -rf "$(PLUGINS)/$(NAME).frappliance/Contents"
	cp -R $(BUNDLE)/Contents "$(PLUGINS)/$(NAME).frappliance/"
	cp "$(TV_RESOURCES)/ApplianceIcon.png" "$(PLUGINS)/$(NAME).frappliance/Contents/Resources/ApplianceIcon.png"
	cp "$(TV_RESOURCES)/TVIconReflection.png" "$(PLUGINS)/$(NAME).frappliance/Contents/Resources/ApplianceIconReflection.png"
	cp "$(TV_RESOURCES)/BlurredTVIcon.png" "$(PLUGINS)/$(NAME).frappliance/Contents/Resources/BlurredApplianceIcon.png"
	cp "$(TV_RESOURCES)/BlurredTVIconReflection.png" "$(PLUGINS)/$(NAME).frappliance/Contents/Resources/BlurredApplianceIconReflection.png"
	mkdir -p "$(PANES)"
	rm -rf "$(PANES)/$(NAME).prefPane"
	cp -R $(PANE) "$(PANES)/"
	cp "$(TV_RESOURCES)/ApplianceIcon.png" "$(PANES)/$(NAME).prefPane/Contents/Resources/$(NAME).png"

# Front Row has to be opened from the old Mac's own session (Command-Escape or the
# Apple Remote). Opened from SSH, it starts hidden and can't claim the remote.
run: install
	@killall "Front Row" 2>/dev/null || true
	@killall "System Preferences" 2>/dev/null || true
	@echo "Installed. Open Front Row with Command-Escape or the remote, and Channels for Front Row in System Preferences."

clean:
	rm -rf build

.PHONY: all install run clean

# Runs on your current Mac.
imac:
	rsync -a --delete --exclude build --exclude .git --exclude .DS_Store ./ $(IMAC):$(REMOTE_DIR)/
	ssh $(IMAC) 'make -C $(REMOTE_DIR) run'

.PHONY: imac
