# Monitr:
Watch a directory for new media and add it to the proper corresponding location in a Plex library.

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
- [ ] Logging
- [ ] The CLI boolean flags with a default value of true cannot be set to false. Fix it.
- [ ] Do something with files that failed to be moved
- [ ] Don't register downloads with x264 as a TV show of Season 2 Episode 64
- [ ] Better subtitle file support
- [ ] Get show name/season from parent directory?
- [ ] Convert media to Plex Direct Play/Strem formats with Handbrake CLI or ffmpeg
- [ ] Preserve TV show episode titles
