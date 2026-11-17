@echo off
rem Сервер сетевого боя: ждёт клиента на порту 31313 (можно переопределить первым аргументом).
set PORT=31313
if not "%~1"=="" set PORT=%~1
start "" "%~dp0remake\export\windows-full\tekken3pc.exe" --host=%PORT%
