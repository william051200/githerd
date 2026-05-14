@echo off
REM githerd CLI shim - delegates to sync.bat in the same folder.
"%~dp0sync.bat" %*
exit /b %ERRORLEVEL%
