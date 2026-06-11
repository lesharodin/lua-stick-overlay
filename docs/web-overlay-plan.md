# Web Overlay Plan

The first web version should be static-hostable on GitHub Pages. Because GitHub Pages cannot run a backend worker, v1 web scope should avoid server-side video processing.

Planned flow:

1. User opens a static page.
2. User selects a video file and a `STICK*.CSV` log file locally.
3. The page parses the CSV and previews stick overlay playback on top of the video.
4. The page provides a manual offset slider to align CSV time with video time.

Deferred decisions:

- Whether final export happens fully in-browser using `ffmpeg.wasm` or `WebCodecs`.
- Whether a local CLI renderer is also provided for large files.
- Visual overlay design and configurable layout.

Not planned for the first web version:

- OCR detection of `ARMED` or other OSD text.
- Uploading user video/log files to a remote service.
- Backend rendering on GitHub Pages.

