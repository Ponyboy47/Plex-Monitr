# Monitr: [![Build Status](https://travis-ci.org/Ponyboy47/Plex-Monitr.svg?branch=master)](https://travis-ci.org/Ponyboy47/Plex-Monitr)

<p align="center"><img src="https://github.com/Ponyboy47/Plex-Monitr/blob/master/img/monitr.jpg" width=100 /></p>

Let's be honest. Managing your Plex media can be a pain. Especially when you have a ton of new stuff you want to add all at once or if you are just constantly adding new stuff! That's where Monitr comes in.

Downloading movies or tv shows or ripping cds/dvds/blu-rays is now the hardest part of getting new media onto your plex server. No more manually placing files or hacking together the proper metadata for your media. Monitr makes adding new media to your Plex server much easier. Just make sure you add new files to a designated "downloads" directory and that's all! Monitr puts it exactly where Plex wants it and names it appropriately so that Plex can identify it and find it's proper metadata match.

It works by watching a designated "Downloads" directory and whenever a new video, audio, or subtitle file is added to that directory, Monitr will automatically move it right to where it should be, then Plex takes care of the rest!

You can also configure Monitr to automatically transcode media into Plex Direct Play/Stream capable formats. This means that Plex won't have to transcode media on-the-go and can help keep your CPU load lower when watching movies or TV shows.

It supports either Linux or macOS operating systems using Apple's Swift language (and a tiny bit of C for some of the stuff on Linux). It also has some dependencies, like ruby (if you're enabling the conversion capabilities).

---

## Features:
* Cross-system compatability
  * Linux (tested on Ubuntu 16.04) <- This is my primary development environment
  * macOS (tested on macOS Sierra 10.12)
* Monitors a downloads directory for when files are moved into it
* Supports _most_ Plex media types
  * Movies & TV Shows
    * Including subtitles
  * Music
  * Home Videos
* Automatically converts media to Plex Direct Play/Stream capable formats
  * It uses the most common Direct Play/Stream formats by default, but you can configure the conversion settings however you'd like
  * Automatic media transcoding can be ran immediately when new media is added, or later as a scheduled task when the server will most likely not be in use

---

## Installation
### Linux (Tested on Ubuntu 16.04)
```bash
# transcode_video dependency installation (only needed if you're going to enable automatic media conversion)
sudo add-apt-repository ppa:stebbins/handbrake-releases
sudo add-apt-repository ppa:jonathonf/ffmpeg-3
sudo apt-get remove handbrake* ffmpeg && sudo apt autoremove
sudo apt-get update
sudo apt-get install -y ruby handbrake-cli ffmpeg mkvtoolnix mp4v2-utils libav-tools x264 x265

# transcode_video installation (only needed if you're going to enable automatic media conversion)
sudo gem install video_transcoding

# Swiftenv installation (makes installing and updating swift super easy)
git clone https://github.com/kylef/swiftenv.git ~/.swiftenv
echo 'export SWIFTENV_ROOT="$HOME/.swiftenv"' >> ~/.bash_profile
echo 'export PATH="$SWIFTENV_ROOT/bin:$PATH"' >> ~/.bash_profile
echo 'eval "$(swiftenv init -)"' >> ~/.bash_profile
source ~/.bash_profile

# Plex-Monitr and swift installation
git clone https://github.com/Ponyboy47/Plex-Monitr.git
cd Plex-Monitr
swiftenv install $(cat .swift-version)
swift build
.build/debug/monitr
```

### macOS (Tested on macOS High Sierra 10.13.2)
```bash
# Homebrew installation (To install swiftenv and also the transcode_video dependencies)
/usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"

# transcode_video dependencies and installation (only needed if you're going to enable automatic media conversion)
brew install handbrake ffmpeg mkvtoolnix mp4v2 && gem install video_transcoding

# Makes installing and updating swift super easy
brew install kylef/formulae/swiftenv

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

#### See the current version of monitr:
`-v` or `--version`

#### Set the Config file to use/save to:
`-f` or `--config`
<p>The default value for this is ~/.config/monitr/settings.json.</p>

#### Set the Plex Library directory:
`-p` or `--plex-dir`
<p>If this is not specified, then /var/lib/plexmediaserver/Library is used (the default location on Ubuntu).</p>

#### Set the Download directories to monitor:
`-t` or `--download-dirs`
<p>If left unspecified, then /var/lib/deluge/Downloads is used (Where I've kept my own downloads on Ubuntu).</p>

#### Set the Home Video directories to monitor
`-b` or `--home-video-download-dirs`
<p>If left unspecified, then ~/HomeVideos is used.</p>

#### Set the Convert flag (whether to convert media to Direct Play formats for plex):
`-c` or `--convert`
<p>Defaults to false.</p>

#### Set whether to convert media files immediately, or as a scheduled task:
`-i` or `--convert-immediately`
<p>defaults to true<br />
When true, files are converted before they are moved to their corresponding Plex directory</p>

#### Set when scheduled media file conversion tasks should begin:
`-a` or `--convert-cron-start`
<p>default is "0 0 * * *" (midnight every day)</p>

#### Set when scheduled media file conversion tasks should be finished:
`-z` `--convert-cron-end`
<p>default is "0 8 * * *" (8am every day)</p>

#### Set the number of simultaneous conversion threads we can have running at one time:
`-r` or `--convert-threads`
<p>default is 2<br />
NOTE: Preliminary performance testing shows that using multiple threads will still convert the same number of files in the same amount of time. A single thread will convert one file faster, but multiple threads convert multiple files simultaneously, but slower. Overall, it tends to take the same amount of time to convert a batch of files.</p>

#### Set whether of not to delete the original media file after converting it:
`-o` or `--delete-original`
<p>defaults to false<br />
NOTE: If false, unconverted media files will be placed in the plex location along with the converted media file. The original file will have '.original' appended to the end of the filepath</p>

#### Set the container to use when converting video files:
`-e` or `--convert-video-container`
<p>defaults to mp4 since that is the most commonly supported container for DirectPlay across the various Plex devices</p>

#### Set the codec to use when converting video streams:
`-g` or `--convert-video-codec`
<p>default is h264 since that is the most commonly supported codec for DirectPlay in Plex</p>

#### Set the container to use when converting audio files:
`-j` or `--convert-audio-container`
<p>defaults to aac right now<br />
NOTE: I don't have plans for a lot of audio file conversion support. I know Plex generally supports streaming aac, which is why I use aac, but I haven't looked into the Plex audio streaming stuff as much as I have it's video streaming requirements.</p>

#### Set the codec to use when converting audio streams:
`-k` or `--convert-audio-codec`
<p>default is aac since that is the most commonly supported codec for DirectPlay in Plex</p>

#### Set whether to scan for foreign audio subtitles and burn them into a video stream:
`-n` or `--convert-video-subtitle-scan`
<p>defaults to false<br />
NOTE: This is an experimental feature in the transcode_video tool. If it screws up, you could end up with the wrong subtitle track burned into your video. [See @donmelton's own documentation on this feature](https://github.com/donmelton/video_transcoding#understanding-subtitles) in his transcode_video.

#### Set the maximum framerate to use when converting video streams:
`-m` or `--convert-video-max-framerate`
<p>defaults to 30.0</p>

#### Set the directory to use for conversion jobs when deleteOriginal is false:
`-u` or `--convert-temp-dir`
<p>default is /tmp/MonitrConversion</p>

#### Set whether or not subtitle files should be deleted or preserved for video media:
`-q` or `--delete-subtitles`
<p>default is false</p>

#### Set whether or not to save these config settings to the config file:
`-s` or `--save-settings`
<p>defaults to false<br />
NOTE: If true, subsequent monitr instances can be run and will load in the settings file and use it's config values.</p>

#### Set the default logging level to use:
`-d`
<p>default value is 0 (Errors only). Valid values range from 0-4.</p>

##### Logging levels:
0. Error
1. Warning
2. Info
3. Debug
4. Verbose

#### Set the log file to use:
`-l` or `--log-file`
<p>Default is nil, which means logs are only written to stdout.<br />
NOTE: If set, and logging level >= 3 (debug or verbose), logs are written both to the file specified, and also to stdout.</p>

---

## TODO:
- [x] Make a graphic
- [x] Logging
- [x] The CLI boolean flags with a default value of true cannot be set to false. Fix it.
- [ ] Do something with files that failed to be moved
- [x] Don't register downloads with x264 as a TV show of Season 2 Episode 64
- [x] Better subtitle file support
- [x] Make an option for deleting subtitle files upon import
- [ ] Get show name/season from parent directory? (Useful when there is an organized directory structure, but file names do not contain all the relevant info)
- [x] Convert media to Plex Direct Play/Stream formats with Handbrake CLI or ffmpeg
- [ ] Preserve TV show episode titles
- [ ] Support multi-part TV show episodes
- [ ] Create a command to display the statistics
- [x] Support monitoring multiple directories
- [x] Watch a specific directory for Home Videos
- [x] Make the entire program more asynchronous
  - [x] Continue execution while converting media (Just add new stuff to a queue)
  - [ ] Finishing conversion automatically continues to moveMedia()
- [ ] Improve the stability with large amounts of conversion jobs
- [x] Swift 4
- [ ] Dynamically add paths to watch lists (such as an auto-generated directory inside users' home directories)
