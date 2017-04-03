# Monitr:

<p align="center"><img src="https://github.com/Ponyboy47/Plex-Monitr/blob/master/img/monitr.jpg" width=100 /></p>

Let's be honest. Managing your Plex media can be a pain. Especially when you have a ton of new stuff you want to add all at once or if you are just constantly adding new stuff! That's where Monitr comes in.

Downloading movies or tv shows or ripping cds/dvds/blu-rays is now the hardest part of getting new media onto your plex server. No more manually placing files or hacking together the proper metadata for your media. Monitr makes adding new media to your Plex server much easier. Just make sure you add new files to a designated "downloads" directory and that's all! Monitr puts it exactly where Plex wants it and names it appropriately so that Plex can identify it and find it's proper match.

It works by watching a designated "Downloads" directory and whenever a new video, audio, or subtitle file is added to that directory, Monitr will automatically move it right to where it should be, then Plex takes care of the rest!

It supports either Linux or macOS operating systems using Apple's Swift language (and a tiny bit of C for some of the stuff on Linux).

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

## Usage:
Clone the repo and build it:
```bash
git clone https://github.com/Ponyboy47/Plex-Monitr.git
cd Plex-Monitr
swift build
```
There should be a binary executable at .build/debug/monitr
Run it just like any other executable!

```bash
.build/debug/monitr
```

### CLI Arguments:
There are a number of ways to configure your Monitr. Like any CLI application, any of these arguments can be used at the same time to create the exact Monitr that you need.

#### See the usage/help text:
`-h` or `--help`
```bash
.build/debug/monitr -h
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

#### Set whether or not to save these config settings to the config file:
`-s` or `--save-settings`
```bash
.build/debug/monitr --save-settings
```
<p>Defaults to false.<br />
NOTE: If true, subsequent monitr instances can be run and will load in the settings file and use it's config values.</p>

#### Set the default logging level to use:
`-d`
```bash
.build/debug/monitr -d 3
```
Default value is 0 (Errors only). Valid values range from 0-4.

#### Set the log file to use:
`-l` or `--log-file`
```bash
.build/debug/monitr --log-file /var/log/monitr/monitr.log
```
<p>Default is nil, which means logs are only written to stdout.<br />
NOTE: If set, and logging level >= 3 (debug or higher), logs are written both to the file specified, and also to stdout.</p>

---

## TODO:
- [x] Make a graphic
- [x] Logging
- [x] The CLI boolean flags with a default value of true cannot be set to false. Fix it.
- [ ] Do something with files that failed to be moved
- [x] Don't register downloads with x264 as a TV show of Season 2 Episode 64
- [ ] Better subtitle file support
- [ ] Get show name/season from parent directory? (Useful when there is an organized directory structure, but file names do not contain all the relevant info)
- [ ] Convert media to Plex Direct Play/Stream formats with Handbrake CLI or ffmpeg
- [ ] Preserve TV show episode titles
- [ ] Support multi-part TV show episodes
