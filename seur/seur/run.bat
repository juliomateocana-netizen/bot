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

powershell -NoProfile -ExecutionPolicy Bypass -Command "$cfg = Get-Content 'config.json' -Raw -Encoding UTF8 | ConvertFrom-Json; $actual = if ($cfg.publicUrl) { $cfg.publicUrl } else { 'http://localhost:3000' }; Write-Host ('  Dominio actual: ' + $actual) -ForegroundColor Cyan; Write-Host '  (Puedes cambiar el dominio en Telegram con /url [enlace])' -ForegroundColor Gray; Write-Host ''; Start-Process $actual;"

echo  Iniciando servidor...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "server.ps1"

echo.
echo  Servidor detenido.
pause
