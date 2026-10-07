# Channels for Front Row

Live TV from a Channels DVR server, inside Front Row on an old Mac.

Front Row was the full-screen media app in Mac OS X 10.5 and 10.6. It works from across the room with the Apple Remote. Apple removed it in 10.7, so the Macs that still have it often sit unused. Channels for Front Row is a plugin that adds a Live TV menu to Front Row, so one of those Macs can work as a small guest TV.

Channels and Channels DVR are made by Fancy Bits. This project isn't affiliated with them.

## Status

Version 1.0 is the first release. The Live TV menu lists the channels in one Channels DVR channel collection. Highlighting a channel shows the programme on now, with its picture and summary, and what's on next. Selecting it plays it full screen inside Front Row.

## Requirements

- An Intel Mac running Mac OS X 10.6.8 with Front Row. Tested on a 2011 iMac.
- A Channels DVR server on the same network.

The plugin plays channels with the playback engine from VLC 2.0.10, VideoLAN's last version for 32-bit Intel Macs. Newer versions of VLC are 64-bit only, so they can't load into Front Row. The installer includes VLC 2.0.10, so you don't need to get it yourself.

## Installing

1. Download `ChannelsForFrontRow-VERSION.pkg` from the [Releases page](https://github.com/malouf-dev/channels-for-frontrow/releases). The old Mac's browser can't open GitHub's secure site, so download it on another computer and copy it across.
2. Open it on the old Mac and follow the steps. It asks for an administrator's password. It installs:
   - the Front Row plugin, in `/System/Library/CoreServices/Front Row.app/Contents/PlugIns/ChannelsForFrontRow.frappliance`
   - the System Preferences pane, in `/Library/PreferencePanes/ChannelsForFrontRow.prefPane`
   - VLC 2.0.10 and its licence, in `/Library/Application Support/channels-for-frontrow/`. This copy is only for the plugin. A VLC in Applications is left alone.
3. Choose your channels, as below.
4. Open Front Row with Command-Escape or the Apple Remote. Live TV is in its main menu.

### Choosing channels

Open System Preferences on the old Mac and choose Channels for Front Row, under Other. The pane finds your Channels DVR server by itself with Bonjour. If it can't, for example because the server is on another network, choose "Use this address" and type its address. Then choose a channel collection, or All Channels. The pane checks the server as you go, and the Live TV menu uses the new settings the next time you open it in Front Row.

### Disabling

The Plugin menu at the top of the pane turns Live TV off and on. Disabled, the plugin is moved out of Front Row's plugins folder into `/Library/Application Support/channels-for-frontrow/`, so Front Row doesn't load it at all. That frees its place for another plugin (see How it works). Enabling moves it back. Each change asks for an administrator's password and quits Front Row in the background, so it shows the next time you open Front Row. While the plugin is disabled, the pane's other settings can't be changed.

### Removing

Click Uninstall… at the bottom of the pane. It asks you to confirm, then for an administrator's password. It removes the plugin, the pane, VLC's copy, the installer's record and your settings, then quits System Preferences.

To remove it by hand instead, run these in Terminal on the old Mac. The first removes the plugin, the pane and VLC's copy, including a disabled plugin. The second makes the Mac forget the installer's record. The third quits Front Row, which keeps running in the background.

```bash
sudo rm -rf "/System/Library/CoreServices/Front Row.app/Contents/PlugIns/ChannelsForFrontRow.frappliance" /Library/PreferencePanes/ChannelsForFrontRow.prefPane "/Library/Application Support/channels-for-frontrow"
```

```bash
sudo pkgutil --forget channels-for-frontrow.pkg
```

```bash
killall "Front Row"
```

Your settings stay in `~/Library/Preferences/channels-for-frontrow.plist`. Delete that file too if you don't want to keep them.

## How it works

Front Row is built on BackRow, a private Apple framework with no public documentation or headers. A plugin is a bundle whose name ends in `.frappliance`, inside Front Row's own app folder.

Front Row 2.2.1 only shows a plugin that meets three rules:

- Its bundle identifier starts with `com.apple.frontrow.appliance`.
- Its main class has the name of one of Apple's own plugins. Two of those names, `RUIYTAppliance` and `RUIComputersAppliance`, belong to plugins that don't exist on 10.6, so other plugins can use them. This plugin uses `RUIYTAppliance`.
- Its main class adopts BackRow's `BRApplianceProtocol`.

Only two names are free. Another plugin that also uses `RUIYTAppliance` can't load alongside this one. Disabling Live TV in its pane frees the name, because Front Row then doesn't load it.

The plugin plays each channel's broadcast stream exactly as Channels DVR receives it. The server converts nothing, and a channel starts playing about 2.5 to 3 seconds after you choose it.

Front Row's own video player can't play these streams, so the plugin has its own player screen. It uses the playback engine from VLC 2.0.10, which decodes the picture and sound and removes interlacing. The plugin draws the picture inside Front Row's screen, so Front Row's volume bar still works over it.

The plugin finds your Channels DVR server with Bonjour, Apple's way for devices to announce themselves on a network. The channel list, collections and guide come from Channels DVR's own web interface for apps. The menu loads the channel list and the next six hours of guide when it opens, and works out what's on now and next each time you highlight a channel. While the menu is open, the guide reloads quietly once it's half an hour old, and the highlighted preview changes by itself when its programme ends. The channel list reloads the next time you open Live TV. The preview uses Front Row's own layout, the same as the Movies and TV Shows menus.

A live stream can't start cleanly. The first pictures the decoder produces depend on earlier ones that were never received, and the gaps show as green blocks. Playback also takes a moment to settle. So the plugin keeps a channel hidden and silent for at least a second after its first picture, and until the picture is clean. Then it fades the picture and sound in together over 0.8 seconds. While a channel plays, the display stays awake and Front Row's screen saver stays away.

An earlier version had Channels DVR convert each channel to HLS, Apple's streaming format, and played it with QuickTime. Each channel took about 17 seconds to start, because QuickTime holds back a live stream until it has about 10 seconds of video.

## Building

Front Row is 32-bit only, and current versions of Xcode can't build 32-bit Mac code. So the code is built on the old Mac itself, with Xcode 3.2.6. You run the build from a current Mac over SSH.

### One-time setup

1. Install Xcode 3.2.6 on the old Mac. Keep "UNIX Development" ticked in the installer.
2. On the old Mac, turn on Remote Login in System Preferences, under Sharing.
3. On your current Mac, make an RSA key for the old Mac. The SSH version in 10.6 doesn't support newer key types.

   ```bash
   ssh-keygen -t rsa -b 4096 -f ~/.ssh/old-mac
   ```

4. Add a host alias at the end of `~/.ssh/config` on your current Mac. Current macOS turns off the older algorithms that 10.6 uses, so the alias turns them back on for this host only. If you keep host settings in separate files with an `Include` line, you can put this block in one of those instead.

   SSH uses the first value it finds for each setting. If an earlier `Host *` section already sets these options, the alias won't work at the end of the file. Move it to just above that section. Don't move it above any lines at the top of the file that aren't under a `Host` line, such as `Include`. Those lines apply to every host only while they sit above the first `Host` line.

   ```
   Host old-mac
     HostName your-old-mac.local
     User your-user-name
     IdentityFile ~/.ssh/old-mac
     HostKeyAlgorithms +ssh-rsa
     PubkeyAcceptedAlgorithms +ssh-rsa
     KexAlgorithms +diffie-hellman-group-exchange-sha256,diffie-hellman-group14-sha1
   ```

5. Copy the key across.

   ```bash
   ssh-copy-id -i ~/.ssh/old-mac.pub old-mac
   ```

6. Create the plugin folder inside Front Row and make your user its owner. After this, builds install without an admin password.

   ```bash
   ssh -t old-mac 'sudo mkdir -p "/System/Library/CoreServices/Front Row.app/Contents/PlugIns/ChannelsForFrontRow.frappliance" && sudo chown "$USER":staff "/System/Library/CoreServices/Front Row.app/Contents/PlugIns/ChannelsForFrontRow.frappliance"'
   ```

7. If you named the alias something other than `old-mac`, create a file called `local.mk` in the repository folder with your alias in it. Git ignores this file, so your alias stays out of the repository.

   ```
   IMAC = your-alias
   ```

8. Give the plugin its own copy of VLC 2.0.10. Run this from the repository folder on your current Mac.

   ```bash
   make vlc
   ```

   It downloads `vlc-2.0.10-intel32.dmg` (33.6 MB) from [VideoLAN's archive](https://download.videolan.org/pub/videolan/vlc/2.0.10/macosx/) into `downloads/`, on your current Mac because the old Mac's browser can't open VideoLAN's secure site. It checks the file against VideoLAN's published checksum, copies it to the old Mac, and puts `VLC.app` in `~/Library/Application Support/channels-for-frontrow/` there. If a copy is already there, it's left alone. A newer VLC in Applications can stay where it is.

   To do it by hand instead, download that disk image from the link, copy it to the old Mac and open it, then drag `VLC.app` into `~/Library/Application Support/channels-for-frontrow/`.

### Each build

Run this from the repository folder on your current Mac.

```bash
make imac
```

It copies the source to the old Mac, builds the Front Row plugin and the System Preferences pane there, installs both and quits Front Row and System Preferences. Then open Front Row on the old Mac with Command-Escape or the remote, and it loads the new build.

Open Front Row from the old Mac itself. If it's opened over SSH, it starts hidden and can't use the remote.

After the first build, choose your channels in System Preferences, as in Choosing channels above.

### The installer

```bash
make package
```

It builds the installer on the old Mac and copies it to `build/ChannelsForFrontRow-VERSION.pkg` on your current Mac. The version comes from `Info.plist`. The package includes the plugin, the pane, and VLC 2.0.10 from the disk image that `make vlc` downloads. It downloads the disk image first if it isn't in `downloads/` yet.

Disabling a development build moves your plugin folder from step 6 out of Front Row, so enable it again before the next `make imac`. Uninstalling removes that folder, the development pane and your settings, but not the copy of VLC in your own Library.

To test the package on your development Mac, first remove the development copies: the plugin folder from step 6, `~/Library/PreferencePanes/ChannelsForFrontRow.prefPane` and `~/Library/Application Support/channels-for-frontrow/`. The plugin uses a copy of VLC in your own Library before the installed one. After testing, follow Removing above and repeat steps 6 and 8 to go back to development builds.

## Folders

- `Source/`: the Front Row plugin. `Source/BackRow.h` declares the parts of BackRow that the plugin uses, and `Source/VLC.h` the parts of VLC's engine.
- `Info.plist` and `English.lproj/`: the plugin's bundle settings, and the Live TV name in Front Row's main menu.
- `Artwork/`: the icon. `Icon.png` is the original, and the other three are made from it for Front Row's main menu and the pane.
- `Pane/`: the System Preferences pane. It shares the server and settings code in `Source/`. `Pane/manage` is the script the pane runs with an administrator's password to enable, disable or uninstall.
- `Installer/`: the installer's title and checks (`Distribution.xml`), the script it runs after installing (`postinstall`), and a small program that builds VLC's list of plugins (`vlc-cache.c`).
- `tools/backrow/`: scripts for reading BackRow's classes and code.
- `tools/hlscheck/`: a small program that tests whether the old Mac can play a stream with QuickTime, outside Front Row.
- `tools/vlccheck/`: the same kind of test with VLC's playback engine. It reports the time to the first picture, frames per second and processor use.
- `Makefile`: builds the plugin, the pane and the installer on the old Mac, and starts those builds from your current Mac. It also downloads VLC.

## Licence

The project's own code is under the MIT licence. See `LICENSE`.

VLC 2.0.10 is VideoLAN's work, under the GNU General Public License, version 2. The installer includes it unchanged, with its licence. Its source code is attached to each release here, and is also in [VideoLAN's archive](https://download.videolan.org/pub/videolan/vlc/2.0.10/).
