@echo off
setlocal
chcp 65001 >nul
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0run-tests.ps1" %*
set "test_exit=%errorlevel%"
if not defined TESTS_NO_PAUSE pause
exit /b %test_exit%
