# Monitr: [![Build Status](https://travis-ci.org/Ponyboy47/Plex-Monitr.svg?branch=master)](https://travis-ci.org/Ponyboy47/Plex-Monitr)

<p align="center"><img src="https://github.com/Ponyboy47/Plex-Monitr/blob/master/img/monitr.jpg" width=100 /></p>

Let's be honest. Managing your Plex media can be a pain. Especially when you have a ton of new stuff you want to add all at once or if you are just constantly adding new stuff! That's where Monitr comes in.

Downloading movies or tv shows or ripping cds/dvds/blu-rays is now the hardest part of getting new media onto your plex server. No more manually placing files or hacking together the proper metadata for your media. Monitr makes adding new media to your Plex server much easier. Just make sure you add new files to a designated "downloads" directory and that's all! Monitr puts it exactly where Plex wants it and names it appropriately so that Plex can identify it and find it's proper match.

It works by watching a designated "Downloads" directory and whenever a new video, audio, or subtitle file is added to that directory, Monitr will automatically move it right to where it should be, then Plex takes care of the rest!

It supports either Linux or macOS operating systems using Apple's Swift language (and a tiny bit of C for some of the stuff on Linux). It also has some dependencies, like ruby (if you're enabling the conversion capabilities).

---

## Features:
* Cross-system compatability
  * Linux (tested on Ubuntu 16.04)
  * macOS (tested on macOS Sierra 10.12)
* Monitors a downloads directory for when files are moved into it
* Supports _most_ Plex media types
  * Movies & TV Shows
    * Including subtitles
  * Music
  * Home videos would be placed in either the Movies or TV Shows directories (depends on the file name)

---

## Installation
### macOS
```bash
# Homebrew installation (To install swiftenv and also the transcode_video dependencies)
/usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"

# transcode_video dependencies installation
brew install handbrake ffmpeg mkvtoolnix mp4v2 kylef/formulae/swiftenv

# transcode_video installation
gem install video_transcoding

# Plex-Monitr and swift installation
git clone https://github.com/Ponyboy47/Plex-Monitr.git
cd Plex-Monitr
swiftenv install $(cat .swift-version)
swift build
.build/debug/monitr -v
```

### Linux (Ubuntu 16.04)
```bash
# transcode_video dependency installation
sudo add-apt-repository ppa:stebbins/handbrake-releases
sudo add-apt-repository ppa:jonathonf/ffmpeg-3
sudo apt-get remove handbrake ffmpeg && sudo apt autoremove
sudo apt-get update
sudo apt-get install -y ruby handbrake-cli ffmpeg mkvtoolnix mp4v2-utils libav-tools x264 x265

# transcode_video installation
sudo gem install video_transcoding

# Swiftenv installation (makes installing and updating swift way easier)
git clone https://github.com/kylef/swiftenv.git ~/.swiftenv
echo 'export SWIFTENV_ROOT="$HOME/.swiftenv"' >> ~/.bash_profile
echo 'export PATH="$SWIFTENV_ROOT/bin:$PATH"' >> ~/.bash_profile
echo 'eval "$(swiftenv init -)"' >> ~/.bash_profile

# Plex-Monitr and swift installation
git clone https://github.com/Ponyboy47/Plex-Monitr.git
cd Plex-Monitr
swiftenv install $(cat .swift-version)
swift build
.build/debug/monitr
```

---

## Usage:

### CLI Arguments:
There are a number of ways to configure your Monitr. Like any CLI application, any of these arguments can be used at the same time to create the exact Monitr that you need.

#### See the usage/help text:
`-h` or `--help`
```bash
.build/debug/monitr -h
```

#### See the current version of monitr:
`-v` or `--version`
```bash
.build/debug/monitr -v
```

#### Set the Config file to use/save to:
`-f` or `--config`
```bash
.build/debug/monitr --config /path/to/config.json
```
The default value for this is ~/.config/monitr/settings.json.

#### Set the Plex Library directory:
`-p` or `--plex-dir`
```bash
.build/debug/monitr --plex-dir /path/to/plexmediaserver/Library
```
If this is not specified, then /var/lib/plexmediaserver/Library is used.

#### Set the Download directory to monitor:
`-t` or `--download-dir`
```bash
.build/debug/monitr --download-dir /path/to/downloads/dir
```
If left unspecified, then /var/lib/deluge/Downloads is used.

#### Set the Convert flag (whether to convert media to Direct Play formats for plex):
`-c` or `--convert`
```bash
.build/debug/monitr --convert
```
Defaults to false.

#### Set whether to convert media files immediately, or as a scheduled task:
`-i` or `--convert-immediately`
```bash
.build/debug/monitr --convert-immediately
```
<p>defaults to true<br />
When true, files are converted before they are moved to their corresponding Plex directory</p>

#### Set when scheduled media file conversion tasks should begin:
`-a` or `--convert-cron-start`
```bash
.build/debug/monitr -a "0 0 * * *"
```
default is "0 0 * * *" (midnight every day)

#### Set when scheduled media file conversion tasks should be finished:
`-z` `--convert-cron-end`
```bash
.build/debug/monitr -z "0 8 * * *"
```
default is "0 8 * * *" (8am every day)

#### Set the number of simultaneous conversion threads we can have running at one time:
`-r` or `--convert-threads`
```bash
.build/debug/monitr --convert-threads 4
```
default is 2

#### Set whether of not to delete the original media file after converting it:
`-o` or `--delete-original`
```bash
.build/debug/monitr --delete-original
```
<p>defaults to false<br />
NOTE: If false, unconverted media files will be placed in the plex location along with the converted media file. The original file will have '.original' appended to the end of the filepath</p>

#### Set the container to use when converting video files:
`-e` or `--convert-video-container`
```bash
.build/debug/monitr --convert-video-container mkv
```
defaults to mp4 since that is the most commonly supported container for DirectPlay across the various Plex devices

#### Set the codec to use when converting video streams:
`-g` or `--convert-video-codec`
```bash
.build/debug/monitr --convert-video-codec mpeg
```
default is h264 since that is the most commonly supported codec for DirectPlay in Plex

#### Set the container to use when converting audio files:
`-j` or `--convert-audio-container`
```bash
.build/debug/monitr --convert-audio-container mp3
```
<p>defaults to aac right now<br />
NOTE: I don't have plans for a lot of audio file conversion support. I know Plex generally supports streaming aac, which is why I use aac, but I haven't looked into the Plex audio streaming stuff as much as I have it's video streaming requirements.</p>

#### Set the codec to use when converting audio streams:
`-k` or `--convert-audio-codec`
```bash
.build/debug/monitr --convert-audio-codec ac3
```
default is aac since that is the most commonly supported codec for DirectPlay in Plex

#### Set whether to scan for foreign audio subtitles and burn them into a video stream:
`-n` or `--convert-video-subtitle-scan`
```bash
.build/debug/monitr --convert-video-subtitle-scan
```
<p>defaults to false<br />
NOTE: This is an experimental feature in the transcode_video tool. If it screws up, you could end up with the wrong subtitle track burned into your video. [See @donmelton's own documentation on this feature](https://github.com/donmelton/video_transcoding#understanding-subtitles) in his transcode_video.

#### Set the maximum framerate to use when converting video streams:
`-m` or `--convert-video-max-framerate`
```bash
.build/debug/monitr --convert-video-max-framerate 23.976
```
defaults to 30.0

#### Set the directory to use for conversion jobs when deleteOriginal is false:
`-u` or `--convert-temp-dir`
```bash
.build/debug/monitr --convert-temp-dir /tmp/monitr/conversionJobs
```
default is /tmp

#### Set whether or not to save these config settings to the config file:
`-s` or `--save-settings`
```bash
.build/debug/monitr --save-settings
```
<p>defaults to false<br />
NOTE: If true, subsequent monitr instances can be run and will load in the settings file and use it's config values.</p>

#### Set the default logging level to use:
`-d`
```bash
.build/debug/monitr -d 3
```
default value is 0 (Errors only). Valid values range from 0-4.

##### Logging levels:
0. Error
1. Warning
2. Info
3. Debug
4. Verbose

#### Set the log file to use:
`-l` or `--log-file`
```bash
.build/debug/monitr --log-file /var/log/monitr/monitr.log
```
<p>Default is nil, which means logs are only written to stdout.<br />
NOTE: If set, and logging level >= 3 (debug or verbose), logs are written both to the file specified, and also to stdout.</p>

---

## TODO:
- [x] Make a graphic
- [x] Logging
- [x] The CLI boolean flags with a default value of true cannot be set to false. Fix it.
- [ ] Do something with files that failed to be moved
- [x] Don't register downloads with x264 as a TV show of Season 2 Episode 64
- [ ] Better subtitle file support
- [ ] Get show name/season from parent directory? (Useful when there is an organized directory structure, but file names do not contain all the relevant info)
- [x] Convert media to Plex Direct Play/Stream formats with Handbrake CLI or ffmpeg
- [ ] Preserve TV show episode titles
- [ ] Support multi-part TV show episodes
- [ ] Create a command to display the statistics
