@echo off
rem Build Artic.apk (release) and copy it to the project root.
set JAVA_HOME=D:\Softwares\jdk17\jdk-17.0.16+8
set ANDROID_HOME=D:\Softwares\Android
set PATH=D:\Softwares\flutter\bin;%PATH%
cd /d %~dp0

call flutter clean
call flutter pub get
call flutter build apk --release
if errorlevel 1 (
    echo Build failed.
    pause
    exit /b 1
)
copy /y build\app\outputs\flutter-apk\app-release.apk "%~dp0Artic.apk" >nul
echo Done: %~dp0Artic.apk
pause
