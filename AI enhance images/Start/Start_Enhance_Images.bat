@echo off
setlocal EnableExtensions
set "BAT_PATH=%~f0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $p=$env:BAT_PATH; $lines=Get-Content -LiteralPath $p; $marker='### POWERSHELL_ENGINE_BELOW ###'; $i=[Array]::IndexOf($lines,$marker); if($i -lt 0){throw 'PowerShell engine marker not found'}; $code=($lines[($i+1)..($lines.Count-1)] -join [Environment]::NewLine); Invoke-Expression $code"
set "EXITCODE=%ERRORLEVEL%"
echo.
echo Finished with code %EXITCODE%.
pause
exit /b %EXITCODE%
### POWERSHELL_ENGINE_BELOW ###

$ErrorActionPreference = "Stop"

$Scale = 4
$Model = "realesrgan-plus"
$Processor = "realesrgan"
$ModeName = "Ultra 4K RAW"
$ModeDescription = "4x RealESRGAN, lossless PNG, force 4096 px long edge"
$ExtractFilter = "unsharp=5:5:0.85:3:3:0.35"
$TargetLongEdge = 4096
$OutputExtension = ".png"
$ImageMegapixelsPerSecond = 0.075
$SupportedExtensions = @(".png", ".jpg", ".jpeg", ".bmp", ".webp", ".tif", ".tiff")

$StartDir = Split-Path -Parent $env:BAT_PATH
$ImageRootDir = Split-Path -Parent $StartDir
$AiEnhanceRootDir = Split-Path -Parent $ImageRootDir
$ToEnhanceDir = Join-Path $StartDir "To Enhance"
$EnhancedRootDir = Join-Path $StartDir "Enhanced"
$ToolsDir = Join-Path $StartDir "tools"
$SiblingVideoToolsDir = Join-Path $AiEnhanceRootDir "AI enhance videos\Start\tools"
New-Item -ItemType Directory -Force -Path $ToEnhanceDir, $EnhancedRootDir, $ToolsDir | Out-Null

function Write-Header {
    Clear-Host
    Write-Host "============================================================"
    Write-Host " AI Enhance Images - Start Tool"
    Write-Host "============================================================"
    Write-Host "Put images here:"
    Write-Host "  $ToEnhanceDir"
    Write-Host "Enhanced images will be saved here:"
    Write-Host "  $EnhancedRootDir"
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

function Read-ImageSelection([object[]]$Images) {
    if ($Images.Count -eq 1) { return @($Images[0]) }
    while ($true) {
        $raw = (Read-Host "Choose image number or type all").Trim()
        if ($raw.Equals("all", [StringComparison]::OrdinalIgnoreCase) -or $raw.Equals("a", [StringComparison]::OrdinalIgnoreCase)) {
            return @($Images)
        }
        $n = 0
        if ([int]::TryParse($raw, [ref]$n) -and $n -ge 1 -and $n -le $Images.Count) {
            return @($Images[$n - 1])
        }
        Write-Host "Please enter 1-$($Images.Count), or all."
    }
}

function Select-EnhancementMode {
    Write-Host "Enhancement mode:"
    Write-Host "  1. Ultra 4K RAW (recommended) - strongest visible repair, PNG lossless"
    Write-Host "  2. Photo / Realistic Strong - 4x native, no forced 4K resize"
    Write-Host "  3. Anime / Cartoon Ultra 4K - stronger 4K anime/cartoon mode"
    Write-Host "  4. Anime / Cartoon Conservative - 4x but softer"
    Write-Host "  5. Legacy 2x Anime - old conservative mode"
    Write-Host ""
    $choice = Read-ChoiceNumber 1 5 "Choose mode"

    switch ($choice) {
        1 {
            $script:ModeName = "Ultra 4K RAW"
            $script:ModeDescription = "4x RealESRGAN, lossless PNG, force 4096 px long edge"
            $script:Scale = 4
            $script:Model = "realesrgan-plus"
            $script:ExtractFilter = "unsharp=5:5:0.85:3:3:0.35"
            $script:TargetLongEdge = 4096
            $script:ImageMegapixelsPerSecond = 0.075
        }
        2 {
            $script:ModeName = "Photo / Realistic Strong"
            $script:ModeDescription = "4x, realesrgan-plus, light sharpen"
            $script:Scale = 4
            $script:Model = "realesrgan-plus"
            $script:ExtractFilter = "unsharp=5:5:0.7:3:3:0.3"
            $script:TargetLongEdge = 0
            $script:ImageMegapixelsPerSecond = 0.10
        }
        3 {
            $script:ModeName = "Anime / Cartoon Ultra 4K"
            $script:ModeDescription = "4x, realesrgan-plus-anime, force 4096 px long edge"
            $script:Scale = 4
            $script:Model = "realesrgan-plus-anime"
            $script:ExtractFilter = "unsharp=5:5:0.65:3:3:0.25"
            $script:TargetLongEdge = 4096
            $script:ImageMegapixelsPerSecond = 0.075
        }
        4 {
            $script:ModeName = "Anime / Cartoon Conservative"
            $script:ModeDescription = "4x, realesr-animevideov3, no extra sharpen"
            $script:Scale = 4
            $script:Model = "realesr-animevideov3"
            $script:ExtractFilter = ""
            $script:TargetLongEdge = 0
            $script:ImageMegapixelsPerSecond = 0.12
        }
        5 {
            $script:ModeName = "Legacy 2x Anime"
            $script:ModeDescription = "2x, realesr-animevideov3, no extra sharpen"
            $script:Scale = 2
            $script:Model = "realesr-animevideov3"
            $script:ExtractFilter = ""
            $script:TargetLongEdge = 0
            $script:ImageMegapixelsPerSecond = 0.25
        }
    }

    Write-Host ""
    Write-Host "Selected mode:"
    Write-Host "  $script:ModeName"
    Write-Host "  $script:ModeDescription"
    Write-Host ""
}

function Find-Exe([string]$Name, [string[]]$Candidates) {
    foreach ($candidate in $Candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) { return (Resolve-Path -LiteralPath $candidate).Path }
    }
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    throw "$Name was not found. Expected it in this image tool, the sibling video tool, or PATH."
}

function Safe-Name([string]$Name) {
    $invalid = [IO.Path]::GetInvalidFileNameChars()
    $chars = $Name.ToCharArray() | ForEach-Object { if ($invalid -contains $_) { "_" } else { $_ } }
    $safe = (-join $chars).Trim() -replace "\s+", " "
    if ([string]::IsNullOrWhiteSpace($safe)) { $safe = "Image_Project" }
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

function Get-ExpectedOutputDimensions([int]$Width, [int]$Height) {
    $outW = [double]($Width * $Scale)
    $outH = [double]($Height * $Scale)
    if ($TargetLongEdge -gt 0) {
        $longEdge = [Math]::Max($outW, $outH)
        if ($longEdge -lt $TargetLongEdge) {
            $factor = [double]$TargetLongEdge / [double]$longEdge
            $outW = $outW * $factor
            $outH = $outH * $factor
        }
    }
    return [pscustomobject]@{
        Width = Get-EvenDimension $outW
        Height = Get-EvenDimension $outH
    }
}

function Log([string]$Message) {
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Write-Host $line
    Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8
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

function Get-ImageInfo([string]$File) {
    $output = & $script:FFProbe -v error -select_streams v:0 -show_entries stream=codec_name,width,height -of csv=s=x:p=0 $File 2>> $script:LogFile
    $code = $LASTEXITCODE
    $line = $output | Select-Object -First 1
    if ($code -ne 0 -or [string]::IsNullOrWhiteSpace($line) -or $line -notmatch '^([^x]+)x(\d+)x(\d+)') {
        throw "Could not read image dimensions: $File"
    }
    return [pscustomobject]@{ Codec=$matches[1]; Width=[int]$matches[2]; Height=[int]$matches[3] }
}

function Test-ImageReadable([string]$File) {
    if (!(Test-Path -LiteralPath $File)) { return $false }
    if ((Get-Item -LiteralPath $File).Length -le 0) { return $false }
    $args = @("-v", "error", "-i", $File, "-frames:v", "1", "-f", "null", "NUL")
    $code = Run-NativeLogged $script:FFmpeg $args $script:ValidationLogFile
    return ($code -eq 0)
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
        $minW = [Math]::Floor($src.Width * $Scale * 0.98)
        $minH = [Math]::Floor($src.Height * $Scale * 0.98)
        if ($out.Width -lt $minW -or $out.Height -lt $minH) { return $false }
        if ($RequireStillImage -and $TargetLongEdge -gt 0 -and ([Math]::Max($out.Width, $out.Height) -lt [Math]::Floor($TargetLongEdge * 0.98))) { return $false }
        return $true
    } catch {
        return $false
    }
}

function Remove-StaleLock([string]$LockDir) {
    if (!(Test-Path -LiteralPath $LockDir)) { return }
    $active = Get-Process video2x -ErrorAction SilentlyContinue | Where-Object { $_.WorkingSet64 -gt 10MB }
    if ($active) { throw "Another active Video2X process is running. Stop it before starting another image job." }
    Write-Host "Found stale lock. Removing it: $LockDir"
    Remove-Item -LiteralPath $LockDir -Recurse -Force -ErrorAction SilentlyContinue
}

function Detect-Video2X {
    Log "Checking Video2X CLI syntax."
    $help = & $script:Video2X --help 2>&1
    $help | Set-Content -LiteralPath $script:Video2XHelpFile -Encoding UTF8
    if ($LASTEXITCODE -ne 0) { throw "video2x --help failed. See $script:Video2XHelpFile" }
    if (($help -join "`n") -notmatch "--realesrgan-model") { throw "This Video2X build does not expose --realesrgan-model." }
    Log "Detected Video2X modern RealESRGAN CLI."
}

function Show-Estimate([string]$ImagePath) {
    $info = Get-ImageInfo $ImagePath
    $expected = Get-ExpectedOutputDimensions $info.Width $info.Height
    $inputMp = ($info.Width * $info.Height) / 1000000.0
    $outputMp = ($expected.Width * $expected.Height) / 1000000.0
    $seconds = [Math]::Max(20.0, ($outputMp / $ImageMegapixelsPerSecond) + 20.0)
    Write-Host ""
    Write-Host "Rough estimate for this PC:"
    Write-Host "  Input size:       $($info.Width)x$($info.Height) ($([Math]::Round($inputMp, 2)) MP)"
    Write-Host "  Expected output:  $($expected.Width)x$($expected.Height) ($([Math]::Round($outputMp, 2)) MP)"
    Write-Host "  Mode:             $ModeName"
    Write-Host "  Scale/model:      ${Scale}x / $Model"
    if ($TargetLongEdge -gt 0) { Write-Host "  RAW target:       PNG lossless, at least $TargetLongEdge px on the long edge" }
    Write-Host "  Estimated time:   $(Format-Seconds $seconds)"
    Write-Host "  Note: big photos can vary a lot by GPU load and image detail."
    Write-Host ""
    Log "Estimate: mode=$ModeName, model=$Model, scale=${Scale}x, input=$($info.Width)x$($info.Height), output=$($expected.Width)x$($expected.Height), targetLongEdge=$TargetLongEdge, estimated=$(Format-Seconds $seconds)."
}

function Invoke-Video2XImage([string[]]$Arguments, [string]$AttemptName) {
    Log "Video2X attempt: $AttemptName"
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $video2xOutput = & $script:Video2X @Arguments 2>&1
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $oldPreference
    }
    $video2xOutput | Tee-Object -FilePath $script:Video2XLogFile -Append | ForEach-Object { Write-Host $_ }
    return $code
}

function Get-ModeSignature {
    return "mode=$ModeName|model=$Model|scale=$Scale|target=$TargetLongEdge|filter=$ExtractFilter"
}

function Test-TempModeMatches {
    if (!(Test-Path -LiteralPath $script:TempModeFile)) { return $false }
    try {
        $content = Get-Content -LiteralPath $script:TempModeFile -Raw
        return ($content -match [regex]::Escape((Get-ModeSignature)))
    } catch {
        return $false
    }
}

function Process-Image {
    $tempMatchesMode = Test-TempModeMatches
    if ((Test-EnhancedImage $script:InputImage $script:FinalOutput) -and $tempMatchesMode) {
        Log "Valid enhanced output already exists. Skipping processing."
        Write-Host ""
        Write-Host "Already done:"
        Write-Host "  $script:FinalOutput"
        return
    }
    if ((Test-EnhancedImage $script:InputImage $script:FinalOutput) -and !$tempMatchesMode) {
        Log "Final output is readable, but it was built with an older or unknown mode. Rebuilding for current mode."
    }
    if (Test-Path -LiteralPath $script:FinalOutput) {
        Log "Deleting invalid final output before rebuild."
        Remove-Item -LiteralPath $script:FinalOutput -Force -ErrorAction SilentlyContinue
    }
    if ((Test-Path -LiteralPath $script:TempOutput) -and !(Test-TempModeMatches)) {
        Log "Deleting temp output from an older or unknown mode before rebuild."
        Remove-Item -LiteralPath $script:TempOutput -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:TempModeFile -Force -ErrorAction SilentlyContinue
    }
    if ((Test-Path -LiteralPath $script:TempOutput) -and !(Test-EnhancedImage $script:InputImage $script:TempOutput $false)) {
        Log "Deleting invalid temp output before rebuild."
        Remove-Item -LiteralPath $script:TempOutput -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:TempModeFile -Force -ErrorAction SilentlyContinue
    }
    if (!(Test-Path -LiteralPath $script:TempOutput)) {
        Log "Processing image with Video2X."
        Write-Host ""
        Write-Host "Video2X image enhancement started."
        Write-Host "Input:"
        Write-Host "  $script:InputImage"
        Write-Host "Output:"
        Write-Host "  $script:FinalOutput"
        Write-Host "Mode:"
        Write-Host "  $ModeName - $ModeDescription"

        $baseArgs = @("-i", $script:InputImage, "-o", $script:TempOutput, "-p", $Processor, "-s", "$Scale", "--realesrgan-model", $Model)
        $losslessArgs = $baseArgs + @("-c", "libx264rgb", "--pix-fmt", "rgb24", "-e", "crf=0", "-e", "preset=veryfast")
        $attemptUsed = "lossless RGB intermediate"
        $code = Invoke-Video2XImage $losslessArgs "lossless RGB intermediate"

        if ($code -ne 0 -and !(Test-EnhancedImage $script:InputImage $script:TempOutput $false)) {
            Log "Lossless intermediate failed. Retrying with Video2X default encoder."
            Remove-Item -LiteralPath $script:TempOutput -Force -ErrorAction SilentlyContinue
            $attemptUsed = "default Video2X encoder fallback"
            $code = Invoke-Video2XImage $baseArgs "default Video2X encoder fallback"
        }

        if ($code -ne 0 -and !(Test-EnhancedImage $script:InputImage $script:TempOutput $false)) {
            throw "Video2X failed. See $script:Video2XLogFile"
        }
        if ($code -ne 0) {
            Log "Video2X returned code $code, but the enhanced video frame is valid. Continuing."
        }
        Set-Content -LiteralPath $script:TempModeFile -Value @(
            (Get-ModeSignature)
            "intermediate=$attemptUsed"
            "created=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        ) -Encoding UTF8
    } else {
        Log "Using existing temp enhanced image."
    }
    if (!(Test-EnhancedImage $script:InputImage $script:TempOutput $false)) {
        Remove-Item -LiteralPath $script:TempOutput -Force -ErrorAction SilentlyContinue
        throw "Enhanced temp image failed validation."
    }
    Log "Extracting final still image from Video2X output."
    $tempInfo = Get-ImageInfo $script:TempOutput
    $filters = @()
    if ($TargetLongEdge -gt 0 -and ([Math]::Max($tempInfo.Width, $tempInfo.Height) -lt $TargetLongEdge)) {
        $factor = [double]$TargetLongEdge / [double]([Math]::Max($tempInfo.Width, $tempInfo.Height))
        $resizeW = Get-EvenDimension ($tempInfo.Width * $factor)
        $resizeH = Get-EvenDimension ($tempInfo.Height * $factor)
        $filters += "scale=${resizeW}:${resizeH}:flags=lanczos"
        Log "Applying final 4K RAW resize: $($tempInfo.Width)x$($tempInfo.Height) -> ${resizeW}x${resizeH}."
    }
    if (![string]::IsNullOrWhiteSpace($ExtractFilter)) {
        $filters += $ExtractFilter
    }
    $extractArgs = @("-hide_banner", "-y", "-i", $script:TempOutput)
    if ($filters.Count -gt 0) {
        $extractArgs += @("-vf", ($filters -join ","))
    }
    $extractArgs += @("-frames:v", "1", $script:ProjectOutput)
    $extractCode = Run-NativeLogged $script:FFmpeg $extractArgs $script:ExtractLogFile
    if ($extractCode -ne 0) { throw "Could not extract final PNG. See $script:ExtractLogFile" }
    Copy-Item -LiteralPath $script:ProjectOutput -Destination $script:FinalOutput -Force
    if (!(Test-EnhancedImage $script:InputImage $script:FinalOutput)) { throw "Final enhanced image failed validation." }
    $outInfo = Get-ImageInfo $script:FinalOutput
    $sizeMb = [Math]::Round((Get-Item -LiteralPath $script:FinalOutput).Length / 1MB, 2)
    Log "Final enhanced image validated: $script:FinalOutput ($($outInfo.Width)x$($outInfo.Height), $sizeMb MB)"
}

function Initialize-ImageProject([IO.FileInfo]$Image) {
    $script:InputImage = $Image.FullName
    $projectName = Safe-Name ([IO.Path]::GetFileNameWithoutExtension($script:InputImage))

    $script:ProjectDir = Join-Path $EnhancedRootDir $projectName
    $script:EnhancedDir = Join-Path $script:ProjectDir "enhanced"
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
    $script:ProjectOutput = Join-Path $script:EnhancedDir "$projectName`_enhanced$OutputExtension"
    $script:FinalOutput = Join-Path $EnhancedRootDir "$projectName`_enhanced$OutputExtension"

    New-Item -ItemType Directory -Force -Path $script:ProjectDir, $script:EnhancedDir, $script:TempDir, $script:LogsDir | Out-Null
    Set-Content -LiteralPath (Join-Path $script:ProjectDir "source_image.txt") -Value $script:InputImage -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $script:ProjectDir "enhancement_mode.txt") -Value @(
        "Mode: $ModeName"
        "Description: $ModeDescription"
        "Processor: $Processor"
        "Model: $Model"
        "Scale: ${Scale}x"
        "Target long edge: $TargetLongEdge"
        "Extract filter: $ExtractFilter"
    ) -Encoding UTF8
}

function Process-SelectedImage([IO.FileInfo]$Image, [int]$Index, [int]$Total) {
    Initialize-ImageProject $Image
    Remove-StaleLock $script:LockDir
    New-Item -ItemType Directory -Force -Path $script:LockDir | Out-Null
    try {
        Write-Host ""
        Write-Host "============================================================"
        Write-Host ("Image {0}/{1}: {2}" -f $Index, $Total, $Image.Name)
        Write-Host "============================================================"
        Log "============================================================"
        Log "Selected image: $script:InputImage"
        Log "Batch position: $Index/$Total"
        Log "Project: $script:ProjectDir"
        Log "FFmpeg: $script:FFmpeg"
        Log "FFprobe: $script:FFProbe"
        Log "Video2X: $script:Video2X"
        Log "Mode: $ModeName ($ModeDescription)"
        if (!(Test-ImageReadable $script:InputImage)) { throw "Input image is not readable." }
        Detect-Video2X
        Show-Estimate $script:InputImage
        Process-Image
        Write-Host ""
        Write-Host "DONE. Enhanced image:"
        Write-Host "  $script:FinalOutput"
        Write-Host ""
        Write-Host "Work files kept here:"
        Write-Host "  $script:ProjectDir"
        return [pscustomobject]@{ Image=$Image.Name; Status="OK"; Output=$script:FinalOutput; Error="" }
    } catch {
        Write-Host ""
        Write-Host "ERROR on image $($Image.Name): $($_.Exception.Message)" -ForegroundColor Red
        if ($script:LogFile) {
            try { Log "ERROR: $($_.Exception.Message)" } catch {}
            Write-Host "Log:"
            Write-Host "  $script:LogFile"
        }
        return [pscustomobject]@{ Image=$Image.Name; Status="FAILED"; Output=""; Error=$_.Exception.Message }
    } finally {
        if (Test-Path -LiteralPath $script:LockDir) { Remove-Item -LiteralPath $script:LockDir -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

try {
    Write-Header
    $script:FFmpeg = Find-Exe "ffmpeg.exe" @((Join-Path $ToolsDir "ffmpeg\bin\ffmpeg.exe"), (Join-Path $SiblingVideoToolsDir "ffmpeg\bin\ffmpeg.exe"))
    $script:FFProbe = Find-Exe "ffprobe.exe" @((Join-Path $ToolsDir "ffmpeg\bin\ffprobe.exe"), (Join-Path $SiblingVideoToolsDir "ffmpeg\bin\ffprobe.exe"))
    $script:Video2X = Find-Exe "video2x.exe" @((Join-Path $ToolsDir "video2x\video2x.exe"), (Join-Path $SiblingVideoToolsDir "video2x\video2x.exe"))

    $images = @(Get-ChildItem -LiteralPath $ToEnhanceDir -File | Where-Object {
        $SupportedExtensions -contains $_.Extension.ToLowerInvariant() -and
        $_.BaseName -notmatch '_(enhance|enhanced)$'
    } | Sort-Object Name)
    if ($images.Count -eq 0) {
        Write-Host "No images found in:"
        Write-Host "  $ToEnhanceDir"
        Write-Host "Add one or more images there, then rerun this BAT."
        exit 0
    }

    Write-Host "Found $($images.Count) image(s):"
    for ($i = 0; $i -lt $images.Count; $i++) {
        $mb = [Math]::Round($images[$i].Length / 1MB, 2)
        Write-Host ("  {0}. {1} ({2} MB)" -f ($i + 1), $images[$i].Name, $mb)
    }
    if ($images.Count -gt 1) {
        Write-Host "  all. Process all images"
    }
    Write-Host ""

    Select-EnhancementMode
    $selectedImages = Read-ImageSelection $images
    Write-Host ""
    Write-Host "Selected $($selectedImages.Count) image(s)."
    $results = @()
    for ($i = 0; $i -lt $selectedImages.Count; $i++) {
        $results += Process-SelectedImage $selectedImages[$i] ($i + 1) $selectedImages.Count
    }

    Write-Host ""
    Write-Host "============================================================"
    Write-Host "Summary"
    Write-Host "============================================================"
    $results | Format-Table Image, Status, Output -AutoSize | Out-String | Write-Host
    $failed = @($results | Where-Object { $_.Status -ne "OK" })
    if ($failed.Count -gt 0) {
        Write-Host "$($failed.Count) image(s) failed. Check their project logs." -ForegroundColor Red
        exit 1
    }
    Write-Host "All selected images finished successfully."
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
