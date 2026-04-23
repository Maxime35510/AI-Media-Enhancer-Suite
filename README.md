# AI Media Enhancer

One Windows batch launcher for enhancing both videos and images with FFmpeg, Video2X, and RealESRGAN.

Drop a file in one folder, run one BAT, choose what you want, and let the tool handle the rest.

```text
drop media -> run Start_AI_Enhancer.bat -> choose file/mode -> get enhanced output
```

The project is built for reliability first: resumable work, validation, repair, logs, and conservative defaults for long jobs on modest Windows PCs.

## Folder Layout

```text
AI enhance/
+-- Start_AI_Enhancer.bat
+-- README.md
+-- To enhance/
+-- Enhanced/
+-- Tools/
+-- Segments/
```

## Folders

### `To enhance`

Put your source files here.

Supported videos:

```text
.mp4 .mkv .mov .avi .m4v .webm
```

Supported images:

```text
.png .jpg .jpeg .bmp .webp .tif .tiff
```

### `Enhanced`

Final outputs are saved here.

Examples:

```text
movie_enhanced.mp4
photo_enhanced.png
```

### `Tools`

Local binaries go here:

```text
Tools/ffmpeg/bin/ffmpeg.exe
Tools/ffmpeg/bin/ffprobe.exe
Tools/video2x/video2x.exe
```

### `Segments`

This is the resumable work area. It stores split segments, enhanced segments, temp image/video files, validation logs, FFmpeg logs, and Video2X logs.

Do not delete it while a job is unfinished. It is how the tool resumes instead of starting from zero.

## Quick Start

1. Put image or video files into `To enhance`.
2. Double-click `Start_AI_Enhancer.bat`.
3. Choose the file number.
4. For multiple images, type `all` to process all images.
5. Pick an image mode when asked.
6. Wait for the final result in `Enhanced`.

Videos are processed one at a time on purpose because they can run for many hours.

## Health Check

From a terminal:

```bat
Start_AI_Enhancer.bat check
```

This verifies that the required folders and tools exist:

- FFmpeg
- FFprobe
- Video2X
- `To enhance`
- `Enhanced`
- `Segments`
- `Tools`

## Image Enhancement

The image pipeline uses Video2X with RealESRGAN.

Available modes:

```text
1. Ultra 4K RAW
2. Photo / Realistic Strong
3. Anime / Cartoon Ultra 4K
4. Anime / Cartoon Conservative
5. Legacy 2x Anime
```

Recommended mode:

```text
Ultra 4K RAW
```

It uses:

```text
Model: realesrgan-plus
Scale: 4x
Final target: at least 4096 px on the long edge
Output: PNG
Extra pass: light sharpen
```

The image pipeline validates the final PNG. If temp files were created with another mode or an older pipeline, the tool deletes only the stale files and rebuilds them.

For old grayscale JPGs with small color noise, the tool also protects against broken color channels. If the source is visually black and white, the final enhanced PNG is forced back to grayscale so green/magenta corruption is rejected and rebuilt automatically.

## Video Enhancement

The video pipeline is conservative and resumable.

It does this:

1. Validates the input video.
2. Splits it into 5-minute segments.
3. Upscales each segment with Video2X + RealESRGAN.
4. Restores audio per segment.
5. Validates every enhanced segment.
6. Rebuilds only missing or broken enhanced segments.
7. Compiles the final video.
8. Validates duration, audio, readability, and 1080p height.

Default video settings:

```text
Processor: RealESRGAN
Model: realesr-animevideov3
Scale: 2x
Segment length: 300 seconds
Final height: 1080p
Audio: copy first, AAC fallback
```

## Resume And Repair

If the PC shuts down, Video2X crashes, or you stop the job, just run:

```text
Start_AI_Enhancer.bat
```

The tool checks what already exists and continues from the last valid step.

It can recover from:

- missing source segments
- broken enhanced segments
- invalid temp files
- failed audio copy
- invalid final video
- old image temp files from another mode
- grayscale images that accidentally produced colored artifacts

## Keyboard Notes

Inside the BAT:

```text
number  choose a file or mode
all     process all images
```

During Video2X:

```text
Space   pause/resume
q       abort Video2X
Ctrl+C  stop the BAT, then rerun later to resume
```

## What Goes In GitHub

Commit:

- `Start_AI_Enhancer.bat`
- `README.md`
- `.gitignore`
- empty folder markers such as `.gitkeep`

Do not commit:

- source media
- enhanced outputs
- split segments
- temp files
- logs
- FFmpeg binaries
- Video2X binaries

## Goal

This is meant to be a personal media repair station: one folder, one launcher, automatic image/video detection, resumable work, and final outputs that are validated before you trust them.
