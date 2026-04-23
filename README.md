# AI Media Enhancer

A single-folder Windows tool that automatically detects whether you dropped an image or a video, then enhances it with FFmpeg, Video2X, and RealESRGAN.

This project is designed for a simple daily workflow:

```text
drop file -> run BAT -> choose file -> get enhanced result
```

No separate image project. No separate video project. One tool, one place.

## Folder Layout

```text
AI enhance/
├── Start_AI_Enhancer.bat
├── README.md
├── To enhance/
├── Enhanced/
├── Tools/
└── Segments/
```

## What Each Folder Does

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

Final enhanced files are saved here.

Examples:

```text
movie_enhanced.mp4
photo_enhanced.png
```

### `Tools`

Local binaries live here:

```text
Tools/ffmpeg/bin/ffmpeg.exe
Tools/ffmpeg/bin/ffprobe.exe
Tools/video2x/video2x.exe
```

### `Segments`

This is the resumable work area.

It stores:

- split video segments
- enhanced video segments
- image temp files
- validation logs
- Video2X logs
- FFmpeg logs

Do not delete this folder while a job is unfinished. It is what allows the tool to resume instead of restarting from zero.

## Main Script

Run:

```text
Start_AI_Enhancer.bat
```

The script scans `To enhance`, detects file types, and shows a list like:

```text
1. [image] photo.jpg
2. [video] cartoon.mp4
```

If there are several images, you can type:

```text
all
```

That processes all images in one batch.

Videos are processed one at a time on purpose because they can run for many hours.

## Health Check

From a terminal:

```bat
Start_AI_Enhancer.bat check
```

This verifies:

- root folders exist
- FFmpeg exists
- FFprobe exists
- Video2X exists

If something is missing, the script tells you what to fix.

## Image Enhancement

The image workflow uses RealESRGAN through Video2X.

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

The image system validates the final PNG. If old temp files were created with another mode, it rebuilds them automatically.

## Video Enhancement

The video workflow is conservative and resumable.

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

## Resume Behavior

If the PC shuts down, Video2X crashes, or you stop the job:

```text
run Start_AI_Enhancer.bat again
```

The tool checks what already exists and continues from the last valid step.

It can recover from:

- missing segments
- broken enhanced segments
- invalid temp files
- failed audio copy
- invalid final video
- old image temp files from another mode

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

## GitHub Notes

The repo should include:

- `Start_AI_Enhancer.bat`
- `README.md`
- empty folder markers
- `.gitignore`

The repo should not include:

- original media
- enhanced outputs
- split segments
- temp files
- logs
- FFmpeg binaries
- Video2X binaries

## The Point

This is meant to feel like a personal media repair station.

Drop a bad-quality image or video into `To enhance`, run one BAT, and let the tool choose the right path.
