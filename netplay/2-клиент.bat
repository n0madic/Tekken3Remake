@echo off
rem Клиент сетевого боя: подключается к серверу. Порт по умолчанию 31313.
set /p IP=IP компьютера сервера (например 192.168.1.10):
start "" "%~dp0remake\export\windows-full\tekken3pc.exe" --join=%IP%
