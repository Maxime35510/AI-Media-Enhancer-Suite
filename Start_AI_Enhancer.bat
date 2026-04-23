@echo off
setlocal EnableExtensions
set "BAT_PATH=%~f0"
set "BAT_ARGS=%*"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $p=$env:BAT_PATH; $lines=Get-Content -LiteralPath $p; $marker='### POWERSHELL_ENGINE_BELOW ###'; $i=[Array]::IndexOf($lines,$marker); if($i -lt 0){throw 'PowerShell engine marker not found'}; $code=($lines[($i+1)..($lines.Count-1)] -join [Environment]::NewLine); Invoke-Expression $code"
set "EXITCODE=%ERRORLEVEL%"
echo.
echo Finished with code %EXITCODE%.
if /i not "%BAT_ARGS%"=="check" pause
exit /b %EXITCODE%
### POWERSHELL_ENGINE_BELOW ###

$ErrorActionPreference = "Stop"

# ============================================================
# AI Media Enhancer - one-folder Windows tool
# Root folders:
#   To enhance  -> input images/videos
#   Enhanced    -> final enhanced outputs only
#   Tools       -> FFmpeg + Video2X binaries
#   Segments    -> resumable work files, logs, temp, split parts
# ============================================================

$VideoSegmentSeconds = 300
$VideoScale = 2
$VideoModel = "realesr-animevideov3"
$VideoProcessor = "realesrgan"
$VideoTargetHeight = 1080
$VideoDurationToleranceSeconds = 3.0
$VideoUpscaleRealtimeFactor = 18.0
$FinalCompileSpeedFactor = 4.0

$ImageScale = 4
$ImageModel = "realesrgan-plus"
$ImageProcessor = "realesrgan"
$ImageModeName = "Ultra 4K RAW"
$ImageModeDescription = "4x RealESRGAN, lossless PNG, force 4096 px long edge"
$ImageExtractFilter = "unsharp=5:5:0.85:3:3:0.35"
$ImageTargetLongEdge = 4096
$ImageOutputExtension = ".png"
$ImageMegapixelsPerSecond = 0.075

$VideoExtensions = @(".mp4", ".mkv", ".mov", ".avi", ".m4v", ".webm")
$ImageExtensions = @(".png", ".jpg", ".jpeg", ".bmp", ".webp", ".tif", ".tiff")

$RootDir = Split-Path -Parent $env:BAT_PATH
$ToEnhanceDir = Join-Path $RootDir "To enhance"
$EnhancedRootDir = Join-Path $RootDir "Enhanced"
$ToolsDir = Join-Path $RootDir "Tools"
$SegmentsRootDir = Join-Path $RootDir "Segments"
New-Item -ItemType Directory -Force -Path $ToEnhanceDir, $EnhancedRootDir, $ToolsDir, $SegmentsRootDir | Out-Null

function Write-Header {
    Clear-Host
    Write-Host "============================================================"
    Write-Host " AI MEDIA ENHANCER"
    Write-Host "============================================================"
    Write-Host "Drop images or videos here:"
    Write-Host "  $ToEnhanceDir"
    Write-Host "Final results:"
    Write-Host "  $EnhancedRootDir"
    Write-Host "Work/resume files:"
    Write-Host "  $SegmentsRootDir"
    Write-Host ""
}

function Read-ChoiceNumber([int]$Min, [int]$Max, [string]$Prompt) {
    while ($true) {
        $raw = Read-Host $Prompt
        $n = 0
        if ([int]::TryParse($raw, [ref]$n) -and $n -ge $Min -and $n -le $Max) { return $n }
        Write-Host "Please enter a number from $Min to $Max."
    }
}

function Safe-Name([string]$Name) {
    $invalid = [IO.Path]::GetInvalidFileNameChars()
    $chars = $Name.ToCharArray() | ForEach-Object { if ($invalid -contains $_) { "_" } else { $_ } }
    $safe = (-join $chars).Trim() -replace "\s+", " "
    if ([string]::IsNullOrWhiteSpace($safe)) { $safe = "AI_Enhance_Project" }
    return $safe
}

function Format-Seconds([double]$Seconds) {
    if ($Seconds -lt 0 -or [double]::IsNaN($Seconds) -or [double]::IsInfinity($Seconds)) { $Seconds = 0 }
    $ts = [TimeSpan]::FromSeconds($Seconds)
    return "{0:00}:{1:00}:{2:00}" -f [int][Math]::Floor($ts.TotalHours), $ts.Minutes, $ts.Seconds
}

function Get-EvenDimension([double]$Value) {
    $rounded = [int][Math]::Round($Value)
    if ($rounded -lt 2) { $rounded = 2 }
    if (($rounded % 2) -ne 0) { $rounded++ }
    return $rounded
}

function Log([string]$Message) {
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Write-Host $line
    if ($script:LogFile) { Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 }
}

function Run-NativeLogged([string]$Exe, [string[]]$Arguments, [string]$LogPath) {
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & $Exe @Arguments *> $LogPath
        return $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $oldPreference
    }
}

function Find-Exe([string]$Name, [string[]]$Candidates) {
    foreach ($candidate in $Candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) { return (Resolve-Path -LiteralPath $candidate).Path }
    }
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    throw "$Name was not found. Put it under Tools, or add it to PATH."
}

function Try-FindExe([string]$Name, [string[]]$Candidates) {
    try { return Find-Exe $Name $Candidates } catch { return $null }
}

function Resolve-Tools {
    $script:FFmpeg = Find-Exe "ffmpeg.exe" @(
        (Join-Path $ToolsDir "ffmpeg\bin\ffmpeg.exe"),
        (Join-Path $ToolsDir "ffmpeg.exe"),
        (Join-Path $RootDir "AI enhance videos\Start\tools\ffmpeg\bin\ffmpeg.exe"),
        (Join-Path $RootDir "AI enhance images\Start\tools\ffmpeg\bin\ffmpeg.exe")
    )
    $script:FFProbe = Find-Exe "ffprobe.exe" @(
        (Join-Path $ToolsDir "ffmpeg\bin\ffprobe.exe"),
        (Join-Path $ToolsDir "ffprobe.exe"),
        (Join-Path $RootDir "AI enhance videos\Start\tools\ffmpeg\bin\ffprobe.exe"),
        (Join-Path $RootDir "AI enhance images\Start\tools\ffmpeg\bin\ffprobe.exe")
    )
    $script:Video2X = Find-Exe "video2x.exe" @(
        (Join-Path $ToolsDir "video2x\video2x.exe"),
        (Join-Path $ToolsDir "video2x.exe"),
        (Join-Path $RootDir "AI enhance videos\Start\tools\video2x\video2x.exe"),
        (Join-Path $RootDir "AI enhance images\Start\tools\video2x\video2x.exe")
    )
}

function Test-Environment {
    Write-Header
    Write-Host "Checking folders..."
    foreach ($dir in @($ToEnhanceDir, $EnhancedRootDir, $ToolsDir, $SegmentsRootDir)) {
        if (!(Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        if (Test-Path -LiteralPath $dir) { Write-Host "  OK      $dir" } else { Write-Host "  MISSING $dir"; return $false }
    }
    Write-Host ""
    Write-Host "Checking tools..."
    $ffmpeg = Try-FindExe "ffmpeg.exe" @((Join-Path $ToolsDir "ffmpeg\bin\ffmpeg.exe"), (Join-Path $ToolsDir "ffmpeg.exe"), (Join-Path $RootDir "AI enhance videos\Start\tools\ffmpeg\bin\ffmpeg.exe"), (Join-Path $RootDir "AI enhance images\Start\tools\ffmpeg\bin\ffmpeg.exe"))
    $ffprobe = Try-FindExe "ffprobe.exe" @((Join-Path $ToolsDir "ffmpeg\bin\ffprobe.exe"), (Join-Path $ToolsDir "ffprobe.exe"), (Join-Path $RootDir "AI enhance videos\Start\tools\ffmpeg\bin\ffprobe.exe"), (Join-Path $RootDir "AI enhance images\Start\tools\ffmpeg\bin\ffprobe.exe"))
    $video2x = Try-FindExe "video2x.exe" @((Join-Path $ToolsDir "video2x\video2x.exe"), (Join-Path $ToolsDir "video2x.exe"), (Join-Path $RootDir "AI enhance videos\Start\tools\video2x\video2x.exe"), (Join-Path $RootDir "AI enhance images\Start\tools\video2x\video2x.exe"))
    if ($ffmpeg) { Write-Host "  OK      FFmpeg  -> $ffmpeg" } else { Write-Host "  MISSING FFmpeg"; return $false }
    if ($ffprobe) { Write-Host "  OK      FFprobe -> $ffprobe" } else { Write-Host "  MISSING FFprobe"; return $false }
    if ($video2x) { Write-Host "  OK      Video2X -> $video2x" } else { Write-Host "  MISSING Video2X"; return $false }
    Write-Host ""
    Write-Host "Overall status: OK"
    return $true
}

function Detect-Video2X {
    Log "Checking Video2X CLI syntax."
    $help = & $script:Video2X --help 2>&1
    $help | Set-Content -LiteralPath $script:Video2XHelpFile -Encoding UTF8
    if ($LASTEXITCODE -ne 0) { throw "video2x --help failed. See $script:Video2XHelpFile" }
    if (($help -join "`n") -notmatch "--realesrgan-model") { throw "This Video2X build does not expose --realesrgan-model." }
    Log "Detected Video2X modern RealESRGAN CLI."
}

function Remove-StaleLock([string]$LockDir, [string[]]$ProcessNames) {
    if (!(Test-Path -LiteralPath $LockDir)) { return }
    $active = foreach ($name in $ProcessNames) { Get-Process $name -ErrorAction SilentlyContinue }
    if ($active) { throw "Another active enhancement process is running. Stop it before starting another job." }
    Write-Host "Found stale lock. Removing it: $LockDir"
    Remove-Item -LiteralPath $LockDir -Recurse -Force -ErrorAction SilentlyContinue
}

function Get-DurationSeconds([string]$File) {
    $output = & $script:FFProbe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $File 2>> $script:LogFile
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($output)) { throw "Could not read duration: $File" }
    return [double]::Parse(($output | Select-Object -First 1), [Globalization.CultureInfo]::InvariantCulture)
}

function Test-VideoReadable([string]$File) {
    if (!(Test-Path -LiteralPath $File)) { return $false }
    if ((Get-Item -LiteralPath $File).Length -le 0) { return $false }
    & $script:FFmpeg -v error -i $File -map 0:v:0 -frames:v 1 -f null NUL 2>> $script:LogFile | Out-Null
    return ($LASTEXITCODE -eq 0)
}

function Test-DurationMatch([string]$Source, [string]$Output, [double]$Tolerance = $VideoDurationToleranceSeconds) {
    try {
        $a = Get-DurationSeconds $Source
        $b = Get-DurationSeconds $Output
        return ([Math]::Abs($a - $b) -le $Tolerance)
    } catch { return $false }
}

function Test-ProcessedSegment([string]$SourceSegment, [string]$OutputSegment) {
    if (!(Test-VideoReadable $OutputSegment)) { return $false }
    if (!(Test-DurationMatch $SourceSegment $OutputSegment)) { return $false }
    return $true
}

function Test-FinalVideo {
    if (!(Test-VideoReadable $script:FinalOutput)) { return $false }
    try {
        $height = (& $script:FFProbe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 $script:FinalOutput 2>> $script:LogFile | Select-Object -First 1)
        if ([int]$height -ne $VideoTargetHeight) { return $false }
        $sourceAudio = (& $script:FFProbe -v error -select_streams a -show_entries stream=index -of csv=p=0 $script:InputVideo 2>> $script:LogFile | Select-Object -First 1)
        $finalAudio = (& $script:FFProbe -v error -select_streams a -show_entries stream=index -of csv=p=0 $script:FinalOutput 2>> $script:LogFile | Select-Object -First 1)
        if (![string]::IsNullOrWhiteSpace($sourceAudio) -and [string]::IsNullOrWhiteSpace($finalAudio)) { return $false }
        return (Test-DurationMatch $script:InputVideo $script:FinalOutput 5.0)
    } catch { return $false }
}

function Test-SplitSegmentsReady {
    $segments = @(Get-ChildItem -LiteralPath $script:VideoSegmentsDir -Filter "segment_*.mp4" -ErrorAction SilentlyContinue | Sort-Object Name)
    if ($segments.Count -ne $script:ExpectedSegments) {
        Log "Split check failed. Expected $script:ExpectedSegments segments, found $($segments.Count)."
        return $false
    }
    for ($i = 0; $i -lt $script:ExpectedSegments; $i++) {
        $name = "segment_{0:0000}.mp4" -f $i
        $path = Join-Path $script:VideoSegmentsDir $name
        if (!(Test-VideoReadable $path)) {
            Log "Split check failed. Segment missing or unreadable: $name"
            return $false
        }
    }
    return $true
}

function Split-VideoIfNeeded {
    if ((Test-Path -LiteralPath $script:SplitDoneFile) -and (Test-SplitSegmentsReady)) {
        Log "Split already completed and validated."
        return
    }
    Log "Preparing clean split into $VideoSegmentSeconds-second segments."
    Get-ChildItem -LiteralPath $script:VideoSegmentsDir -Filter "segment_*.mp4" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    $splitArgs = @("-hide_banner","-y","-i",$script:InputVideo,"-map","0","-c","copy","-f","segment","-segment_time","$VideoSegmentSeconds","-reset_timestamps","1","-avoid_negative_ts","make_zero",(Join-Path $script:VideoSegmentsDir "segment_%04d.mp4"))
    $code = Run-NativeLogged $script:FFmpeg $splitArgs $script:SplitLogFile
    if ($code -ne 0) { throw "FFmpeg split failed. See $script:SplitLogFile" }
    if (!(Test-SplitSegmentsReady)) { throw "Split finished but validation failed. See $script:LogFile" }
    New-Item -ItemType File -Force -Path $script:SplitDoneFile | Out-Null
    Log "Split completed and validated."
}

function Show-VideoEstimate([double]$DurationSeconds, [int]$ExpectedSegments) {
    $existing = @(Get-ChildItem -LiteralPath $script:VideoEnhancedSegmentsDir -Filter "segment_*_enhanced.mp4" -ErrorAction SilentlyContinue).Count
    $remainingSegments = [Math]::Max(0, $ExpectedSegments - $existing)
    $remainingFraction = if ($ExpectedSegments -gt 0) { $remainingSegments / $ExpectedSegments } else { 1.0 }
    $estimatedUpscaleAll = $DurationSeconds * $VideoUpscaleRealtimeFactor
    $estimatedCompile = if ($FinalCompileSpeedFactor -gt 0) { $DurationSeconds / $FinalCompileSpeedFactor } else { 0.0 }
    $estimatedChecks = 300 + ($ExpectedSegments * 30)
    $estimatedResume = ($estimatedUpscaleAll * $remainingFraction) + $estimatedCompile + $estimatedChecks
    Write-Host ""
    Write-Host "Rough estimate:"
    Write-Host "  Video duration:    $(Format-Seconds $DurationSeconds)"
    Write-Host "  Segments:          $ExpectedSegments x $VideoSegmentSeconds seconds"
    Write-Host "  Already enhanced:  $existing"
    Write-Host "  Estimated time:    $(Format-Seconds $estimatedResume)"
    Write-Host "  Note: real time depends on GPU heat, scene detail, and Video2X speed."
    Write-Host ""
    Log "Video estimate: duration=$(Format-Seconds $DurationSeconds), segments=$ExpectedSegments, existing=$existing, eta=$(Format-Seconds $estimatedResume)."
}

function Show-VideoStatus {
    $segments = @(Get-ChildItem -LiteralPath $script:VideoSegmentsDir -Filter "segment_*.mp4" -ErrorAction SilentlyContinue)
    $enhanced = @(Get-ChildItem -LiteralPath $script:VideoEnhancedSegmentsDir -Filter "segment_*_enhanced.mp4" -ErrorAction SilentlyContinue)
    Write-Host ""
    Write-Host "Status:"
    Write-Host "  Segments: $($segments.Count)"
    Write-Host "  Enhanced: $($enhanced.Count) / $script:ExpectedSegments"
    Write-Host "  Output:   $script:FinalOutput"
    Write-Host "  Log:      $script:LogFile"
    Write-Host ""
}

function Process-VideoSegments {
    $segments = @(Get-ChildItem -LiteralPath $script:VideoSegmentsDir -Filter "segment_*.mp4" | Sort-Object Name)
    if ($segments.Count -eq 0) { throw "No split segments found." }
    $i = 0
    foreach ($segment in $segments) {
        $i++
        $base = [IO.Path]::GetFileNameWithoutExtension($segment.Name)
        $temp = Join-Path $script:TempDir "$base`_video2x.mp4"
        $enhanced = Join-Path $script:VideoEnhancedSegmentsDir "$base`_enhanced.mp4"
        if (Test-ProcessedSegment $segment.FullName $enhanced) { Log "Skipping valid segment $i/$($segments.Count): $base"; continue }
        if (Test-Path -LiteralPath $enhanced) { Log "Deleting invalid enhanced segment: $base"; Remove-Item -LiteralPath $enhanced -Force -ErrorAction SilentlyContinue }
        if ((Test-Path -LiteralPath $temp) -and !(Test-ProcessedSegment $segment.FullName $temp)) { Log "Deleting invalid temp segment: $base"; Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
        Log "Processing segment $i/$($segments.Count): $base"
        Write-Host ""
        Write-Host "Video2X segment $i/$($segments.Count): $base"
        Write-Host "Pause/resume in Video2X: Space. Stop: q, or Ctrl+C then rerun this BAT."
        if (!(Test-Path -LiteralPath $temp)) {
            & $script:Video2X -i $segment.FullName -o $temp -p $VideoProcessor -s $VideoScale --realesrgan-model $VideoModel -c libx264 --pix-fmt yuv420p -e preset=veryfast -e crf=20
            if ($LASTEXITCODE -ne 0) { throw "Video2X failed on $base." }
        }
        if (!(Test-ProcessedSegment $segment.FullName $temp)) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue; throw "Video2X output failed validation for $base." }
        Log "Restoring source audio: $base"
        $audioCopyArgs = @("-hide_banner","-y","-i",$temp,"-i",$segment.FullName,"-map","0:v:0","-map","1:a?","-c:v","copy","-c:a","copy","-shortest",$enhanced)
        $code = Run-NativeLogged $script:FFmpeg $audioCopyArgs $script:AudioLogFile
        if ($code -ne 0) {
            Log "Audio copy failed. Retrying AAC: $base"
            $audioAacArgs = @("-hide_banner","-y","-i",$temp,"-i",$segment.FullName,"-map","0:v:0","-map","1:a?","-c:v","copy","-c:a","aac","-b:a","192k","-shortest",$enhanced)
            $code = Run-NativeLogged $script:FFmpeg $audioAacArgs $script:AudioLogFile
            if ($code -ne 0) { throw "Audio restoration failed for $base." }
        }
        if (!(Test-ProcessedSegment $segment.FullName $enhanced)) { throw "Enhanced segment failed validation: $base." }
        Log "Finished segment: $base"
        Show-VideoStatus
    }
}

function Validate-AllVideoSegments {
    $segments = @(Get-ChildItem -LiteralPath $script:VideoSegmentsDir -Filter "segment_*.mp4" | Sort-Object Name)
    $bad = @()
    foreach ($segment in $segments) {
        $base = [IO.Path]::GetFileNameWithoutExtension($segment.Name)
        $enhanced = Join-Path $script:VideoEnhancedSegmentsDir "$base`_enhanced.mp4"
        if (!(Test-ProcessedSegment $segment.FullName $enhanced)) {
            $bad += $base
            if (Test-Path -LiteralPath $enhanced) { Remove-Item -LiteralPath $enhanced -Force -ErrorAction SilentlyContinue }
            $temp = Join-Path $script:TempDir "$base`_video2x.mp4"
            if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
        }
    }
    if ($bad.Count -gt 0) { Log "Bad/missing enhanced segments: $($bad -join ', ')"; return $false }
    Log "All enhanced video segments are valid."
    return $true
}

function Repair-And-ValidateVideoSegments {
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        Log "Video enhance/repair pass $attempt."
        Process-VideoSegments
        if (Validate-AllVideoSegments) { return }
        Log "Some segments were repaired/deleted. Running another pass."
    }
    throw "Segments are still invalid after 3 repair passes."
}

function Quote-CmdArg([string]$Arg) {
    if ($null -eq $Arg) { return '""' }
    if ($Arg -notmatch '[\s"]') { return $Arg }
    return '"' + ($Arg -replace '"','\"') + '"'
}

function Read-ProgressSeconds([string]$ProgressPath) {
    if (!(Test-Path -LiteralPath $ProgressPath)) { return 0.0 }
    $line = Get-Content -LiteralPath $ProgressPath -Tail 80 -ErrorAction SilentlyContinue | Where-Object { $_ -like "out_time=*" } | Select-Object -Last 1
    if ($line -match '^out_time=(\d+):(\d+):([0-9.]+)') {
        return ([double]$matches[1] * 3600.0) + ([double]$matches[2] * 60.0) + [double]::Parse($matches[3], [Globalization.CultureInfo]::InvariantCulture)
    }
    return 0.0
}

function Get-CurrentSegmentLabel([object[]]$Timeline, [double]$DoneSeconds) {
    if (!$Timeline -or $Timeline.Count -eq 0) { return "unknown" }
    foreach ($item in $Timeline) {
        if ($DoneSeconds -ge $item.StartSec -and $DoneSeconds -lt $item.EndSec) {
            return "{0} ({1}/{2})" -f $item.Name, $item.Index, $item.Total
        }
    }
    $last = $Timeline | Select-Object -Last 1
    return "{0} ({1}/{2})" -f $last.Name, $last.Index, $last.Total
}

function Run-FFmpegWithEta([string]$Exe, [string[]]$Arguments, [string]$LogPath, [double]$TotalSeconds, [object[]]$Timeline = @()) {
    $progressPath = Join-Path $script:TempDir "ffmpeg_compile_progress.txt"
    Remove-Item -LiteralPath $progressPath -Force -ErrorAction SilentlyContinue
    $argsWithProgress = @("-nostats", "-progress", $progressPath) + $Arguments
    $quotedArgs = ($argsWithProgress | ForEach-Object { Quote-CmdArg $_ }) -join " "
    $cmdLine = '"' + $Exe + '" ' + $quotedArgs + ' > "' + $LogPath + '" 2>&1'
    $process = Start-Process -FilePath "$env:ComSpec" -ArgumentList "/d", "/c", $cmdLine -WindowStyle Hidden -PassThru
    $start = Get-Date
    $lastShown = [DateTime]::MinValue
    Write-Host ""
    Write-Host "Compile ETA updates about every 15 seconds."
    while (!$process.HasExited) {
        Start-Sleep -Seconds 3
        $now = Get-Date
        if (($now - $lastShown).TotalSeconds -lt 15) { continue }
        $doneSeconds = Read-ProgressSeconds $progressPath
        $elapsed = ($now - $start).TotalSeconds
        $percent = if ($TotalSeconds -gt 0) { [Math]::Min(100.0, ($doneSeconds / $TotalSeconds) * 100.0) } else { 0.0 }
        $speed = if ($elapsed -gt 0) { $doneSeconds / $elapsed } else { 0.0 }
        $eta = if ($speed -gt 0 -and $TotalSeconds -gt $doneSeconds) { ($TotalSeconds - $doneSeconds) / $speed } else { 0.0 }
        $segmentLabel = Get-CurrentSegmentLabel $Timeline $doneSeconds
        Write-Host ("Compile: {0,5:n1}% | segment {1} | video {2}/{3} | elapsed {4} | ETA {5} | speed {6:n2}x" -f $percent, $segmentLabel, (Format-Seconds $doneSeconds), (Format-Seconds $TotalSeconds), (Format-Seconds $elapsed), (Format-Seconds $eta), $speed)
        $lastShown = $now
    }
    $process.WaitForExit()
    return $process.ExitCode
}

function Compile-FinalVideo {
    if (Test-FinalVideo) { Log "Valid final video already exists. Skipping compile."; return }
    if (Test-Path -LiteralPath $script:FinalOutput) { Log "Deleting invalid final video before rebuild."; Remove-Item -LiteralPath $script:FinalOutput -Force -ErrorAction SilentlyContinue }
    $segments = @(Get-ChildItem -LiteralPath $script:VideoEnhancedSegmentsDir -Filter "segment_*_enhanced.mp4" | Sort-Object Name)
    if ($segments.Count -eq 0) { throw "No enhanced segments to compile." }
    $lines = $segments | ForEach-Object { "file '$($_.FullName.Replace('\','/'))'" }
    Set-Content -LiteralPath $script:ConcatFile -Value $lines -Encoding ASCII
    $totalSeconds = 0.0
    $timeline = @()
    for ($idx = 0; $idx -lt $segments.Count; $idx++) {
        $dur = Get-DurationSeconds $segments[$idx].FullName
        $name = ([IO.Path]::GetFileNameWithoutExtension($segments[$idx].Name) -replace '_enhanced$','')
        $timeline += [pscustomobject]@{ Name=$name; Index=($idx + 1); Total=$segments.Count; StartSec=$totalSeconds; EndSec=($totalSeconds + $dur) }
        $totalSeconds += $dur
    }
    if ($totalSeconds -le 0) { $totalSeconds = Get-DurationSeconds $script:InputVideo }
    Log "Compiling final video."
    $copyArgs = @("-hide_banner","-y","-f","concat","-safe","0","-i",$script:ConcatFile,"-map","0:v:0","-map","0:a?","-vf","scale=-2:$VideoTargetHeight`:flags=lanczos","-c:v","libx264","-preset","veryfast","-crf","20","-pix_fmt","yuv420p","-c:a","copy","-movflags","+faststart","-fflags","+genpts","-avoid_negative_ts","make_zero",$script:FinalOutput)
    $code = Run-FFmpegWithEta $script:FFmpeg $copyArgs $script:FinalMergeLog $totalSeconds $timeline
    if ($code -ne 0) {
        Log "Compile with copied audio failed. Retrying AAC."
        $aacArgs = @("-hide_banner","-y","-f","concat","-safe","0","-i",$script:ConcatFile,"-map","0:v:0","-map","0:a?","-vf","scale=-2:$VideoTargetHeight`:flags=lanczos","-c:v","libx264","-preset","veryfast","-crf","20","-pix_fmt","yuv420p","-c:a","aac","-b:a","192k","-movflags","+faststart","-fflags","+genpts","-avoid_negative_ts","make_zero",$script:FinalOutput)
        $code = Run-FFmpegWithEta $script:FFmpeg $aacArgs $script:FinalMergeLog $totalSeconds $timeline
        if ($code -ne 0) { throw "Final compile failed. See $script:FinalMergeLog" }
    }
    if (!(Test-FinalVideo)) { throw "Final video failed validation." }
    Log "Final video validated: $script:FinalOutput"
}

function Initialize-VideoProject([IO.FileInfo]$Video) {
    $script:InputVideo = $Video.FullName
    $projectName = Safe-Name ([IO.Path]::GetFileNameWithoutExtension($script:InputVideo))
    $script:ProjectDir = Join-Path $SegmentsRootDir "$projectName`_video"
    $script:VideoSegmentsDir = Join-Path $script:ProjectDir "segments"
    $script:VideoEnhancedSegmentsDir = Join-Path $script:ProjectDir "enhanced_segments"
    $script:TempDir = Join-Path $script:ProjectDir "temp"
    $script:LogsDir = Join-Path $script:ProjectDir "logs"
    $script:LogFile = Join-Path $script:LogsDir "progress.log"
    $script:Video2XHelpFile = Join-Path $script:LogsDir "video2x_help.txt"
    $script:SplitLogFile = Join-Path $script:LogsDir "split.log"
    $script:AudioLogFile = Join-Path $script:LogsDir "audio_restore.log"
    $script:FinalMergeLog = Join-Path $script:LogsDir "final_merge.log"
    $script:ConcatFile = Join-Path $script:TempDir "concat_list.txt"
    $script:SplitDoneFile = Join-Path $script:ProjectDir "split.complete"
    $script:LockDir = Join-Path $script:TempDir "pipeline.lock"
    $script:FinalOutput = Join-Path $EnhancedRootDir "$projectName`_enhanced.mp4"
    New-Item -ItemType Directory -Force -Path $script:ProjectDir, $script:VideoSegmentsDir, $script:VideoEnhancedSegmentsDir, $script:TempDir, $script:LogsDir | Out-Null
    Set-Content -LiteralPath (Join-Path $script:ProjectDir "source_video.txt") -Value $script:InputVideo -Encoding UTF8
}

function Process-Video([IO.FileInfo]$Video) {
    Initialize-VideoProject $Video
    Remove-StaleLock $script:LockDir @("video2x","ffmpeg")
    New-Item -ItemType Directory -Force -Path $script:LockDir | Out-Null
    try {
        Log "============================================================"
        Log "Selected video: $script:InputVideo"
        Log "Project: $script:ProjectDir"
        Log "FFmpeg: $script:FFmpeg"
        Log "FFprobe: $script:FFProbe"
        Log "Video2X: $script:Video2X"
        if (!(Test-VideoReadable $script:InputVideo)) { throw "Input video is not readable." }
        Detect-Video2X
        $duration = Get-DurationSeconds $script:InputVideo
        $script:ExpectedSegments = [Math]::Ceiling($duration / $VideoSegmentSeconds)
        Log "Input duration: $([Math]::Round($duration, 2)) seconds. Expected segments: $script:ExpectedSegments"
        Show-VideoEstimate $duration $script:ExpectedSegments
        Split-VideoIfNeeded
        Show-VideoStatus
        Repair-And-ValidateVideoSegments
        Show-VideoStatus
        Compile-FinalVideo
        Write-Host ""
        Write-Host "DONE. Enhanced video:"
        Write-Host "  $script:FinalOutput"
        Write-Host "Work files kept:"
        Write-Host "  $script:ProjectDir"
    } finally {
        if (Test-Path -LiteralPath $script:LockDir) { Remove-Item -LiteralPath $script:LockDir -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

function Get-ImageInfo([string]$File) {
    $output = & $script:FFProbe -v error -select_streams v:0 -show_entries stream=codec_name,width,height -of csv=s=x:p=0 $File 2>> $script:LogFile
    $line = $output | Select-Object -First 1
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($line) -or $line -notmatch '^([^x]+)x(\d+)x(\d+)') { throw "Could not read image dimensions: $File" }
    return [pscustomobject]@{ Codec=$matches[1]; Width=[int]$matches[2]; Height=[int]$matches[3] }
}

function Test-ImageReadable([string]$File) {
    if (!(Test-Path -LiteralPath $File)) { return $false }
    if ((Get-Item -LiteralPath $File).Length -le 0) { return $false }
    $args = @("-v", "error", "-i", $File, "-frames:v", "1", "-f", "null", "NUL")
    $code = Run-NativeLogged $script:FFmpeg $args $script:ValidationLogFile
    return ($code -eq 0)
}

function Get-ImageColorStats([string]$File) {
    Add-Type -AssemblyName System.Drawing
    $bitmap = $null
    try {
        $bitmap = [System.Drawing.Bitmap]::new($File)
        $stepX = [Math]::Max(1, [int][Math]::Floor($bitmap.Width / 48))
        $stepY = [Math]::Max(1, [int][Math]::Floor($bitmap.Height / 48))
        $sumDiff = 0.0
        $maxDiff = 0
        $colorPixels = 0
        $count = 0
        for ($y = 0; $y -lt $bitmap.Height; $y += $stepY) {
            for ($x = 0; $x -lt $bitmap.Width; $x += $stepX) {
                $c = $bitmap.GetPixel($x, $y)
                $d1 = [Math]::Abs([int]$c.R - [int]$c.G)
                $d2 = [Math]::Abs([int]$c.G - [int]$c.B)
                $d3 = [Math]::Abs([int]$c.R - [int]$c.B)
                $d = [Math]::Max($d1, [Math]::Max($d2, $d3))
                $sumDiff += $d
                if ($d -gt $maxDiff) { $maxDiff = $d }
                if ($d -gt 18) { $colorPixels++ }
                $count++
            }
        }
        if ($count -eq 0) { return [pscustomobject]@{ AverageDiff=0.0; MaxDiff=0; ColorFraction=0.0 } }
        return [pscustomobject]@{
            AverageDiff = $sumDiff / $count
            MaxDiff = $maxDiff
            ColorFraction = $colorPixels / $count
        }
    } finally {
        if ($bitmap) { $bitmap.Dispose() }
    }
}

function Test-ImageLooksGrayscale([string]$File) {
    try {
        $stats = Get-ImageColorStats $File
        # Old JPEGs often contain tiny RGB noise even when the image is visually grayscale.
        return ($stats.AverageDiff -lt 22.0 -and $stats.MaxDiff -lt 80)
    } catch {
        return $false
    }
}

function Test-EnhancedImage([string]$Source, [string]$Output, [bool]$RequireStillImage = $true) {
    if (!(Test-ImageReadable $Output)) { return $false }
    try {
        $src = Get-ImageInfo $Source
        $out = Get-ImageInfo $Output
        if ($RequireStillImage) {
            $stillCodecs = @("png", "mjpeg", "bmp", "webp", "tiff")
            if ($stillCodecs -notcontains $out.Codec.ToLowerInvariant()) { return $false }
        }
        $minW = [Math]::Floor($src.Width * $ImageScale * 0.98)
        $minH = [Math]::Floor($src.Height * $ImageScale * 0.98)
        if ($out.Width -lt $minW -or $out.Height -lt $minH) { return $false }
        if ($RequireStillImage -and $ImageTargetLongEdge -gt 0 -and ([Math]::Max($out.Width, $out.Height) -lt [Math]::Floor($ImageTargetLongEdge * 0.98))) { return $false }
        if ($RequireStillImage -and (Test-ImageLooksGrayscale $Source) -and !(Test-ImageLooksGrayscale $Output)) { return $false }
        return $true
    } catch { return $false }
}

function Select-ImageMode {
    Write-Host "Image enhancement mode:"
    Write-Host "  1. Ultra 4K RAW (recommended) - strongest visible repair, PNG lossless"
    Write-Host "  2. Photo / Realistic Strong - 4x native"
    Write-Host "  3. Anime / Cartoon Ultra 4K"
    Write-Host "  4. Anime / Cartoon Conservative"
    Write-Host "  5. Legacy 2x Anime"
    Write-Host ""
    $choice = Read-ChoiceNumber 1 5 "Choose mode"
    switch ($choice) {
        1 { $script:ImageModeName="Ultra 4K RAW"; $script:ImageModeDescription="4x RealESRGAN, lossless PNG, force 4096 px long edge"; $script:ImageScale=4; $script:ImageModel="realesrgan-plus"; $script:ImageExtractFilter="unsharp=5:5:0.85:3:3:0.35"; $script:ImageTargetLongEdge=4096; $script:ImageMegapixelsPerSecond=0.075 }
        2 { $script:ImageModeName="Photo / Realistic Strong"; $script:ImageModeDescription="4x, realesrgan-plus, light sharpen"; $script:ImageScale=4; $script:ImageModel="realesrgan-plus"; $script:ImageExtractFilter="unsharp=5:5:0.7:3:3:0.3"; $script:ImageTargetLongEdge=0; $script:ImageMegapixelsPerSecond=0.10 }
        3 { $script:ImageModeName="Anime / Cartoon Ultra 4K"; $script:ImageModeDescription="4x, realesrgan-plus-anime, force 4096 px long edge"; $script:ImageScale=4; $script:ImageModel="realesrgan-plus-anime"; $script:ImageExtractFilter="unsharp=5:5:0.65:3:3:0.25"; $script:ImageTargetLongEdge=4096; $script:ImageMegapixelsPerSecond=0.075 }
        4 { $script:ImageModeName="Anime / Cartoon Conservative"; $script:ImageModeDescription="4x, realesr-animevideov3"; $script:ImageScale=4; $script:ImageModel="realesr-animevideov3"; $script:ImageExtractFilter=""; $script:ImageTargetLongEdge=0; $script:ImageMegapixelsPerSecond=0.12 }
        5 { $script:ImageModeName="Legacy 2x Anime"; $script:ImageModeDescription="2x, realesr-animevideov3"; $script:ImageScale=2; $script:ImageModel="realesr-animevideov3"; $script:ImageExtractFilter=""; $script:ImageTargetLongEdge=0; $script:ImageMegapixelsPerSecond=0.25 }
    }
    Write-Host ""
    Write-Host "Selected: $ImageModeName - $ImageModeDescription"
    Write-Host ""
}

function Get-ExpectedImageOutputDimensions([int]$Width, [int]$Height) {
    $outW = [double]($Width * $ImageScale)
    $outH = [double]($Height * $ImageScale)
    if ($ImageTargetLongEdge -gt 0) {
        $long = [Math]::Max($outW, $outH)
        if ($long -lt $ImageTargetLongEdge) {
            $factor = [double]$ImageTargetLongEdge / [double]$long
            $outW *= $factor
            $outH *= $factor
        }
    }
    return [pscustomobject]@{ Width=(Get-EvenDimension $outW); Height=(Get-EvenDimension $outH) }
}

function Show-ImageEstimate([string]$ImagePath) {
    $info = Get-ImageInfo $ImagePath
    $expected = Get-ExpectedImageOutputDimensions $info.Width $info.Height
    $mp = ($expected.Width * $expected.Height) / 1000000.0
    $seconds = [Math]::Max(20.0, ($mp / $ImageMegapixelsPerSecond) + 20.0)
    Write-Host ""
    Write-Host "Rough image estimate:"
    Write-Host "  Input:      $($info.Width)x$($info.Height)"
    Write-Host "  Output:     $($expected.Width)x$($expected.Height)"
    Write-Host "  Mode/model: $ImageModeName / $ImageModel"
    Write-Host "  ETA:        $(Format-Seconds $seconds)"
    Write-Host ""
    Log "Image estimate: input=$($info.Width)x$($info.Height), output=$($expected.Width)x$($expected.Height), mode=$ImageModeName, eta=$(Format-Seconds $seconds)."
}

function Get-ImageModeSignature {
    return "pipeline=4|mode=$ImageModeName|model=$ImageModel|scale=$ImageScale|target=$ImageTargetLongEdge|filter=$ImageExtractFilter|sourceGray=$script:SourceIsGrayscale"
}

function Test-ImageTempModeMatches {
    if (!(Test-Path -LiteralPath $script:TempModeFile)) { return $false }
    try { return ((Get-Content -LiteralPath $script:TempModeFile -Raw) -match [regex]::Escape((Get-ImageModeSignature))) } catch { return $false }
}

function Invoke-Video2XImage([string[]]$Arguments, [string]$AttemptName) {
    Log "Video2X image attempt: $AttemptName"
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = & $script:Video2X @Arguments 2>&1
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $oldPreference
    }
    $output | Tee-Object -FilePath $script:Video2XLogFile -Append | ForEach-Object { Write-Host $_ }
    return $code
}

function Initialize-ImageProject([IO.FileInfo]$Image) {
    $script:InputImage = $Image.FullName
    $projectName = Safe-Name ([IO.Path]::GetFileNameWithoutExtension($script:InputImage))
    $script:ProjectDir = Join-Path $SegmentsRootDir "$projectName`_image"
    $script:ImageWorkDir = Join-Path $script:ProjectDir "enhanced_frame"
    $script:TempDir = Join-Path $script:ProjectDir "temp"
    $script:LogsDir = Join-Path $script:ProjectDir "logs"
    $script:LogFile = Join-Path $script:LogsDir "progress.log"
    $script:Video2XHelpFile = Join-Path $script:LogsDir "video2x_help.txt"
    $script:Video2XLogFile = Join-Path $script:LogsDir "video2x_run.log"
    $script:ValidationLogFile = Join-Path $script:LogsDir "validation.log"
    $script:ExtractLogFile = Join-Path $script:LogsDir "extract_png.log"
    $script:LockDir = Join-Path $script:TempDir "pipeline.lock"
    $script:TempOutput = Join-Path $script:TempDir "$projectName`_video2x.mp4"
    $script:TempModeFile = Join-Path $script:TempDir "video2x_mode.txt"
    $script:ProjectOutput = Join-Path $script:ImageWorkDir "$projectName`_enhanced$ImageOutputExtension"
    $script:FinalOutput = Join-Path $EnhancedRootDir "$projectName`_enhanced$ImageOutputExtension"
    New-Item -ItemType Directory -Force -Path $script:ProjectDir, $script:ImageWorkDir, $script:TempDir, $script:LogsDir | Out-Null
    Set-Content -LiteralPath (Join-Path $script:ProjectDir "source_image.txt") -Value $script:InputImage -Encoding UTF8
    $script:SourceIsGrayscale = Test-ImageLooksGrayscale $script:InputImage
}

function Process-OneImage([IO.FileInfo]$Image, [int]$Index, [int]$Total) {
    Initialize-ImageProject $Image
    Remove-StaleLock $script:LockDir @("video2x")
    New-Item -ItemType Directory -Force -Path $script:LockDir | Out-Null
    try {
        Write-Host ""
        Write-Host ("Image {0}/{1}: {2}" -f $Index, $Total, $Image.Name)
        Log "============================================================"
        Log "Selected image: $script:InputImage"
        Log "Mode: $ImageModeName ($ImageModeDescription)"
        Detect-Video2X
        if (!(Test-ImageReadable $script:InputImage)) { throw "Input image is not readable." }
        Show-ImageEstimate $script:InputImage
        $tempMatches = Test-ImageTempModeMatches
        if ((Test-EnhancedImage $script:InputImage $script:FinalOutput) -and $tempMatches) { Log "Valid enhanced image already exists. Skipping."; return [pscustomobject]@{File=$Image.Name; Status="OK"; Output=$script:FinalOutput} }
        if (Test-Path -LiteralPath $script:FinalOutput) { Log "Deleting old/invalid final image."; Remove-Item -LiteralPath $script:FinalOutput -Force -ErrorAction SilentlyContinue }
        if ((Test-Path -LiteralPath $script:TempOutput) -and !(Test-ImageTempModeMatches)) { Log "Deleting temp from older image mode."; Remove-Item -LiteralPath $script:TempOutput -Force -ErrorAction SilentlyContinue; Remove-Item -LiteralPath $script:TempModeFile -Force -ErrorAction SilentlyContinue }
        if ((Test-Path -LiteralPath $script:TempOutput) -and !(Test-EnhancedImage $script:InputImage $script:TempOutput $false)) { Log "Deleting invalid image temp."; Remove-Item -LiteralPath $script:TempOutput -Force -ErrorAction SilentlyContinue; Remove-Item -LiteralPath $script:TempModeFile -Force -ErrorAction SilentlyContinue }
        if (!(Test-Path -LiteralPath $script:TempOutput)) {
            $baseArgs = @("-i", $script:InputImage, "-o", $script:TempOutput, "-p", $ImageProcessor, "-s", "$ImageScale", "--realesrgan-model", $ImageModel)
            $safeArgs = $baseArgs + @("-c", "libx264", "--pix-fmt", "yuv444p", "-e", "crf=12", "-e", "preset=veryfast")
            $attempt = "high quality YUV intermediate"
            $code = Invoke-Video2XImage $safeArgs $attempt
            if ($code -ne 0 -and !(Test-EnhancedImage $script:InputImage $script:TempOutput $false)) {
                Log "High quality YUV attempt failed. Retrying default Video2X encoder."
                Remove-Item -LiteralPath $script:TempOutput -Force -ErrorAction SilentlyContinue
                $attempt = "default Video2X encoder fallback"
                $code = Invoke-Video2XImage $baseArgs $attempt
            }
            if ($code -ne 0 -and !(Test-EnhancedImage $script:InputImage $script:TempOutput $false)) { throw "Video2X image processing failed. See $script:Video2XLogFile" }
            if ($code -ne 0) { Log "Video2X returned code $code, but output frame is valid. Continuing." }
            Set-Content -LiteralPath $script:TempModeFile -Value @((Get-ImageModeSignature), "intermediate=$attempt", "created=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')") -Encoding UTF8
        } else {
            Log "Using existing valid image temp."
        }
        $tempInfo = Get-ImageInfo $script:TempOutput
        $filters = @()
        if ($ImageTargetLongEdge -gt 0 -and ([Math]::Max($tempInfo.Width, $tempInfo.Height) -lt $ImageTargetLongEdge)) {
            $factor = [double]$ImageTargetLongEdge / [double]([Math]::Max($tempInfo.Width, $tempInfo.Height))
            $filters += "scale=$(Get-EvenDimension ($tempInfo.Width * $factor)):$(Get-EvenDimension ($tempInfo.Height * $factor)):flags=lanczos"
        }
        if ($script:SourceIsGrayscale) {
            Log "Source is grayscale. Forcing grayscale final output to prevent color-channel artifacts."
            $filters += "format=gray"
            $filters += "format=rgb24"
        }
        if (![string]::IsNullOrWhiteSpace($ImageExtractFilter)) { $filters += $ImageExtractFilter }
        $extractArgs = @("-hide_banner","-y","-i",$script:TempOutput)
        if ($filters.Count -gt 0) { $extractArgs += @("-vf", ($filters -join ",")) }
        $extractArgs += @("-frames:v","1",$script:ProjectOutput)
        $extractCode = Run-NativeLogged $script:FFmpeg $extractArgs $script:ExtractLogFile
        if ($extractCode -ne 0) { throw "Final PNG extraction failed. See $script:ExtractLogFile" }
        Copy-Item -LiteralPath $script:ProjectOutput -Destination $script:FinalOutput -Force
        if (!(Test-EnhancedImage $script:InputImage $script:FinalOutput)) { throw "Final enhanced image failed validation." }
        $outInfo = Get-ImageInfo $script:FinalOutput
        Log "Final image validated: $script:FinalOutput ($($outInfo.Width)x$($outInfo.Height))"
        return [pscustomobject]@{File=$Image.Name; Status="OK"; Output=$script:FinalOutput}
    } catch {
        Log "ERROR: $($_.Exception.Message)"
        Write-Host "ERROR on image $($Image.Name): $($_.Exception.Message)" -ForegroundColor Red
        return [pscustomobject]@{File=$Image.Name; Status="FAILED"; Output=""}
    } finally {
        if (Test-Path -LiteralPath $script:LockDir) { Remove-Item -LiteralPath $script:LockDir -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

function Process-Images([IO.FileInfo[]]$Images) {
    Select-ImageMode
    $results = @()
    for ($i = 0; $i -lt $Images.Count; $i++) { $results += Process-OneImage $Images[$i] ($i + 1) $Images.Count }
    Write-Host ""
    Write-Host "Summary:"
    $results | Format-Table File, Status, Output -AutoSize | Out-String | Write-Host
    if (($results | Where-Object Status -ne "OK").Count -gt 0) { exit 1 }
}

function Get-MediaItems {
    $files = @(Get-ChildItem -LiteralPath $ToEnhanceDir -File | Where-Object { $_.BaseName -notmatch '_(enhance|enhanced)$' } | Sort-Object Name)
    $items = @()
    foreach ($file in $files) {
        $ext = $file.Extension.ToLowerInvariant()
        if ($VideoExtensions -contains $ext) { $items += [pscustomobject]@{File=$file; Type="video"} }
        elseif ($ImageExtensions -contains $ext) { $items += [pscustomobject]@{File=$file; Type="image"} }
    }
    return @($items)
}

function Select-Media {
    $items = @(Get-MediaItems)
    if ($items.Count -eq 0) {
        Write-Host "No supported images or videos found in:"
        Write-Host "  $ToEnhanceDir"
        Write-Host ""
        Write-Host "Supported videos: $($VideoExtensions -join ', ')"
        Write-Host "Supported images: $($ImageExtensions -join ', ')"
        exit 0
    }
    Write-Host "Found $($items.Count) file(s):"
    for ($i = 0; $i -lt $items.Count; $i++) {
        $mb = [Math]::Round($items[$i].File.Length / 1MB, 2)
        Write-Host ("  {0}. [{1}] {2} ({3} MB)" -f ($i + 1), $items[$i].Type, $items[$i].File.Name, $mb)
    }
    $imageItems = @($items | Where-Object Type -eq "image")
    if ($imageItems.Count -gt 1) { Write-Host "  all. Process all images" }
    Write-Host ""
    if ($items.Count -eq 1) { return @($items[0]) }
    while ($true) {
        $raw = (Read-Host "Choose file number, or type all for all images").Trim()
        if ($raw.Equals("all", [StringComparison]::OrdinalIgnoreCase) -or $raw.Equals("a", [StringComparison]::OrdinalIgnoreCase)) {
            if ($imageItems.Count -gt 0) { return @($imageItems) }
            Write-Host "No images available for all."
            continue
        }
        $n = 0
        if ([int]::TryParse($raw, [ref]$n) -and $n -ge 1 -and $n -le $items.Count) { return @($items[$n - 1]) }
        Write-Host "Please enter 1-$($items.Count), or all."
    }
}

try {
    if (($env:BAT_ARGS -as [string]).Trim().Equals("check", [StringComparison]::OrdinalIgnoreCase)) {
        if (Test-Environment) { exit 0 } else { exit 1 }
    }
    Write-Header
    Resolve-Tools
    $selected = Select-Media
    $types = @($selected | Select-Object -ExpandProperty Type -Unique)
    if ($types.Count -gt 1) { throw "Mixed batch is not supported. Choose one video, or all images." }
    if ($types[0] -eq "video") {
        if ($selected.Count -gt 1) { throw "Video batch is intentionally disabled. Process one long video at a time." }
        Process-Video $selected[0].File
    } elseif ($types[0] -eq "image") {
        Process-Images @($selected | ForEach-Object { $_.File })
    } else {
        throw "Unknown media type."
    }
} catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    if ($script:LogFile) {
        try { Log "ERROR: $($_.Exception.Message)" } catch {}
        Write-Host "Log:"
        Write-Host "  $script:LogFile"
    }
    exit 1
}
