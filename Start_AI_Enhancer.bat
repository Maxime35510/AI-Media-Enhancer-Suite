@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem ============================================================
rem  AI Media Enhancer - Unified Launcher
rem  Launches the video and image enhancement projects from one place.
rem ============================================================

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

set "VIDEO_START=%ROOT%\AI enhance videos\Start"
set "IMAGE_START=%ROOT%\AI enhance images\Start"

set "VIDEO_BAT=%VIDEO_START%\Start_Enhance_Videos.bat"
set "IMAGE_BAT=%IMAGE_START%\Start_Enhance_Images.bat"

set "VIDEO_INPUT=%VIDEO_START%\To Enhance"
set "IMAGE_INPUT=%IMAGE_START%\To Enhance"
set "VIDEO_OUTPUT=%VIDEO_START%\Enhanced"
set "IMAGE_OUTPUT=%IMAGE_START%\Enhanced"

set "VIDEO_FFMPEG=%VIDEO_START%\tools\ffmpeg\bin\ffmpeg.exe"
set "VIDEO_FFPROBE=%VIDEO_START%\tools\ffmpeg\bin\ffprobe.exe"
set "VIDEO_VIDEO2X=%VIDEO_START%\tools\video2x\video2x.exe"

set "IMAGE_FFMPEG=%IMAGE_START%\tools\ffmpeg\bin\ffmpeg.exe"
set "IMAGE_FFPROBE=%IMAGE_START%\tools\ffmpeg\bin\ffprobe.exe"
set "IMAGE_VIDEO2X=%IMAGE_START%\tools\video2x\video2x.exe"

call :EnsureBaseFolders

if /i "%~1"=="check" (
    call :CheckAll
    exit /b %ERRORLEVEL%
)

:MENU
cls
echo ============================================================
echo  AI MEDIA ENHANCER
echo ============================================================
echo Root:
echo   %ROOT%
echo.
echo  1. Enhance videos
echo  2. Enhance images
echo.
echo  3. Open video input folder
echo  4. Open image input folder
echo  5. Open video enhanced folder
echo  6. Open image enhanced folder
echo.
echo  7. Check projects and tools
echo  8. Open AI enhance root folder
echo  9. Exit
echo.
set "MENU_CHOICE="
set /p "MENU_CHOICE=Choose 1-9: "

if "%MENU_CHOICE%"=="1" goto LAUNCH_VIDEO
if "%MENU_CHOICE%"=="2" goto LAUNCH_IMAGE
if "%MENU_CHOICE%"=="3" call :OpenFolder "%VIDEO_INPUT%" & goto MENU
if "%MENU_CHOICE%"=="4" call :OpenFolder "%IMAGE_INPUT%" & goto MENU
if "%MENU_CHOICE%"=="5" call :OpenFolder "%VIDEO_OUTPUT%" & goto MENU
if "%MENU_CHOICE%"=="6" call :OpenFolder "%IMAGE_OUTPUT%" & goto MENU
if "%MENU_CHOICE%"=="7" call :CheckAll & pause & goto MENU
if "%MENU_CHOICE%"=="8" call :OpenFolder "%ROOT%" & goto MENU
if "%MENU_CHOICE%"=="9" exit /b 0

echo.
echo I did not understand that choice. Use a number from 1 to 9.
pause
goto MENU

:LAUNCH_VIDEO
cls
echo ============================================================
echo  VIDEO ENHANCER
echo ============================================================
call :CheckVideoProject
if errorlevel 1 (
    echo.
    echo The video project is not ready. Use option 7 for details.
    pause
    goto MENU
)
echo.
echo Starting video enhancer...
echo Put videos here if needed:
echo   %VIDEO_INPUT%
echo.
pushd "%VIDEO_START%"
call "%VIDEO_BAT%"
set "RUN_CODE=%ERRORLEVEL%"
popd
echo.
echo Video enhancer closed with code %RUN_CODE%.
pause
goto MENU

:LAUNCH_IMAGE
cls
echo ============================================================
echo  IMAGE ENHANCER
echo ============================================================
call :CheckImageProject
if errorlevel 1 (
    echo.
    echo The image project is not ready. Use option 7 for details.
    pause
    goto MENU
)
echo.
echo Starting image enhancer...
echo Put images here if needed:
echo   %IMAGE_INPUT%
echo.
pushd "%IMAGE_START%"
call "%IMAGE_BAT%"
set "RUN_CODE=%ERRORLEVEL%"
popd
echo.
echo Image enhancer closed with code %RUN_CODE%.
pause
goto MENU

:EnsureBaseFolders
if not exist "%VIDEO_INPUT%" mkdir "%VIDEO_INPUT%" >nul 2>nul
if not exist "%IMAGE_INPUT%" mkdir "%IMAGE_INPUT%" >nul 2>nul
if not exist "%VIDEO_OUTPUT%" mkdir "%VIDEO_OUTPUT%" >nul 2>nul
if not exist "%IMAGE_OUTPUT%" mkdir "%IMAGE_OUTPUT%" >nul 2>nul
exit /b 0

:OpenFolder
set "TARGET_FOLDER=%~1"
if not exist "%TARGET_FOLDER%" mkdir "%TARGET_FOLDER%" >nul 2>nul
if exist "%TARGET_FOLDER%" (
    explorer "%TARGET_FOLDER%"
) else (
    echo.
    echo Could not create or open:
    echo   %TARGET_FOLDER%
    echo.
    echo Fix: check that the parent folder exists and that Windows allows write access.
    pause
)
exit /b 0

:CheckAll
cls
echo ============================================================
echo  PROJECT AND TOOL CHECK
echo ============================================================
echo.
call :CheckVideoProject
set "VIDEO_STATUS=%ERRORLEVEL%"
echo.
call :CheckImageProject
set "IMAGE_STATUS=%ERRORLEVEL%"
echo.
if "%VIDEO_STATUS%"=="0" if "%IMAGE_STATUS%"=="0" (
    echo Overall status: OK
    echo Both projects are ready.
    echo.
    exit /b 0
) else (
    echo Overall status: needs attention
    echo Read the messages above. Each problem includes the direct fix.
    echo.
    exit /b 1
)

:CheckVideoProject
set "FAILED=0"
echo [Video project]
call :CheckFile "Main BAT" "%VIDEO_BAT%" || set "FAILED=1"
call :CheckFolder "Input folder" "%VIDEO_INPUT%" || set "FAILED=1"
call :CheckFolder "Enhanced folder" "%VIDEO_OUTPUT%" || set "FAILED=1"
call :CheckFile "FFmpeg" "%VIDEO_FFMPEG%" || set "FAILED=1"
call :CheckFile "FFprobe" "%VIDEO_FFPROBE%" || set "FAILED=1"
call :CheckFile "Video2X" "%VIDEO_VIDEO2X%" || set "FAILED=1"
if "%FAILED%"=="0" (
    echo Video project status: OK
    exit /b 0
)
echo Video project status: needs attention
echo Fix: restore the missing file or folder under:
echo   %VIDEO_START%
exit /b 1

:CheckImageProject
set "FAILED=0"
echo [Image project]
call :CheckFile "Main BAT" "%IMAGE_BAT%" || set "FAILED=1"
call :CheckFolder "Input folder" "%IMAGE_INPUT%" || set "FAILED=1"
call :CheckFolder "Enhanced folder" "%IMAGE_OUTPUT%" || set "FAILED=1"

rem Image project can use its own tools or the sibling video tools.
call :CheckToolWithSibling "FFmpeg" "%IMAGE_FFMPEG%" "%VIDEO_FFMPEG%" || set "FAILED=1"
call :CheckToolWithSibling "FFprobe" "%IMAGE_FFPROBE%" "%VIDEO_FFPROBE%" || set "FAILED=1"
call :CheckToolWithSibling "Video2X" "%IMAGE_VIDEO2X%" "%VIDEO_VIDEO2X%" || set "FAILED=1"

if "%FAILED%"=="0" (
    echo Image project status: OK
    exit /b 0
)
echo Image project status: needs attention
echo Fix: restore the missing file or folder under:
echo   %IMAGE_START%
exit /b 1

:CheckFile
set "LABEL=%~1"
set "FILEPATH=%~2"
if exist "%FILEPATH%" (
    echo   OK      %LABEL%
    exit /b 0
)
echo   MISSING %LABEL%
echo           %FILEPATH%
exit /b 1

:CheckFolder
set "LABEL=%~1"
set "FOLDERPATH=%~2"
if not exist "%FOLDERPATH%" mkdir "%FOLDERPATH%" >nul 2>nul
if exist "%FOLDERPATH%" (
    echo   OK      %LABEL%
    exit /b 0
)
echo   MISSING %LABEL%
echo           %FOLDERPATH%
exit /b 1

:CheckToolWithSibling
set "LABEL=%~1"
set "PRIMARY=%~2"
set "SIBLING=%~3"
if exist "%PRIMARY%" (
    echo   OK      %LABEL%
    exit /b 0
)
if exist "%SIBLING%" (
    echo   OK      %LABEL% via video project tools
    exit /b 0
)
echo   MISSING %LABEL%
echo           Expected one of:
echo           %PRIMARY%
echo           %SIBLING%
exit /b 1
