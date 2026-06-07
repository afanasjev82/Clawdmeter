@echo off
chcp 65001 > NUL
REM Start script for the Clawdmeter BLE daemon (Docker) — Windows.
REM
REM NOTE: Docker Desktop on Windows runs in a VM and CANNOT access the host
REM Bluetooth radio, so the daemon will scan but never connect. This script is
REM for building/managing the image; the daemon only works on a Linux host.

setlocal enabledelayedexpansion
cd /d "%~dp0"

set ENV_FILE=.env
set DETACHED=false

:parse_args
if "%~1"=="" goto end_parse
if /i "%~1"=="-d" ( set DETACHED=true & shift & goto parse_args )
if /i "%~1"=="--detach" ( set DETACHED=true & shift & goto parse_args )
if /i "%~1"=="-e" ( set ENV_FILE=%~2 & shift & shift & goto parse_args )
if /i "%~1"=="--env" ( set ENV_FILE=%~2 & shift & shift & goto parse_args )
if /i "%~1"=="-h" goto show_help
if "%~1"=="--help" goto show_help
echo ❌ Unknown option: %~1
exit /b 1

:show_help
echo Usage: %~nx0 [OPTIONS]
echo.
echo Options:
echo   -d, --detach     Run in the background (detached)
echo   -e, --env FILE   Use specified env file (default: .env)
echo   -h, --help       Show this help message
exit /b 0

:end_parse

echo ⚠️  Docker Desktop on Windows can't reach the Bluetooth radio.
echo    The container will start but the daemon won't connect to the device.
echo    Deploy on a Linux host for it to actually work.

REM Seed .env from the example on first run.
if not exist "%ENV_FILE%" (
    if exist ".env.example" (
        echo 💡 %ENV_FILE% not found — creating it from .env.example
        copy /Y ".env.example" "%ENV_FILE%" > NUL
    )
)

set COMPOSE_ARGS=
if exist "%ENV_FILE%" set COMPOSE_ARGS=--env-file "%ENV_FILE%"

echo 🚀 Starting Clawdmeter daemon...

if "%DETACHED%"=="true" (
    echo ✅ Starting detached...
    docker compose %COMPOSE_ARGS% up -d --build --remove-orphans
    echo ✅ Up. Logs: docker compose logs -f
) else (
    echo ✅ Starting in foreground (Ctrl+C to stop)...
    docker compose %COMPOSE_ARGS% up --build --remove-orphans
)

endlocal
