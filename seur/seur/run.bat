@echo off
chcp 65001 >nul
title Wallapop bot 2.0
cd /d "%~dp0"

echo.
echo  ============================================
echo   WALLAPOP BOT 2.0
echo  ============================================
echo.

if not exist config.json (
  echo  Falta config.json con tu token del bot.
  echo.
  pause
  exit /b 1
)

:: Iniciar servidor sin confirmación de URL
echo   Iniciando servicio...


echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'powershell' -and $_.CommandLine -like '*server.ps1*' } | ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force } catch {} }"
powershell -NoProfile -ExecutionPolicy Bypass -File "server.ps1"

echo.
echo  Servidor detenido.
pause
