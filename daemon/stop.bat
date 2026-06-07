@echo off
chcp 65001 > NUL
REM Stop script for the Clawdmeter BLE daemon (Docker) — Windows.

setlocal enabledelayedexpansion
cd /d "%~dp0"

set ENV_FILE=.env
set REMOVE_IMAGE=false

:parse_args
if "%~1"=="" goto end_parse
if /i "%~1"=="-e" ( set ENV_FILE=%~2 & shift & shift & goto parse_args )
if /i "%~1"=="--env" ( set ENV_FILE=%~2 & shift & shift & goto parse_args )
if /i "%~1"=="--rmi" ( set REMOVE_IMAGE=true & shift & goto parse_args )
if /i "%~1"=="-h" goto show_help
if "%~1"=="--help" goto show_help
echo ❌ Unknown option: %~1
exit /b 1

:show_help
echo Usage: %~nx0 [OPTIONS]
echo.
echo Options:
echo   -e, --env FILE   Use specified env file (default: .env)
echo   --rmi            Also remove the built image
echo   -h, --help       Show this help message
exit /b 0

:end_parse

set COMPOSE_ARGS=
if exist "%ENV_FILE%" set COMPOSE_ARGS=--env-file "%ENV_FILE%"

echo 🛑 Stopping Clawdmeter daemon...
if "%REMOVE_IMAGE%"=="true" (
    docker compose %COMPOSE_ARGS% down --rmi local --remove-orphans
) else (
    docker compose %COMPOSE_ARGS% down --remove-orphans
)

echo ✅ Stopped
endlocal
