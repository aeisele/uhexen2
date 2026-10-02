@echo off
setlocal
cd /d "%~dp0"
if not exist "data1\pak0.pak" (
    echo Copy the data1 folder from your Hexen II installation into this folder first.
    pause
    exit /b 1
)
glh2.exe -profile-startup %*
