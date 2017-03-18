# Monitr:
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
git clone https://github.com/Ponyboy47/Monitr.git
cd Monitr
swift build -c=release
```
There should be a binary executable at .build/release/swift-exec
Run it just like any other executable!

Use the -h or --help flags to see the usage/help text
```bash
.build/release/swift-exec -h
```

---

## TODO:
- [ ] Make a graphic
- [ ] Logging
- [ ] The CLI boolean flags with a default value of true cannot be set to false. Fix it.
- [ ] Do something with files that failed to be moved
- [ ] Don't register downloads with x264 as a TV show of Season 2 Episode 64
- [ ] Better subtitle file support
- [ ] Get show name/season from parent directory?
- [ ] Convert media to Plex Direct Play/Strem formats with Handbrake CLI or ffmpeg
- [ ] Preserve TV show episode titles
- [ ] Support multi-part TV show episodes
