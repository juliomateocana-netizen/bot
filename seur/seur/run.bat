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

:: Solicitar y configurar el dominio
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$cfg = Get-Content 'config.json' -Raw -Encoding UTF8 | ConvertFrom-Json; " ^
  "$actual = if ($cfg.publicUrl) { $cfg.publicUrl } else { 'http://localhost:3000' }; " ^
  "Write-Host ('  Dominio actual: ' + $actual) -ForegroundColor Cyan; " ^
  "Write-Host ''; " ^
  "$nuevo = Read-Host '  Introduce el dominio (o pulsa Enter para mantener)'; " ^
  "if ($nuevo -and $nuevo.Trim()) { " ^
  "  $nuevo = $nuevo.Trim().TrimEnd('/'); " ^
  "  if (-not $nuevo.StartsWith('http://') -and -not $nuevo.StartsWith('https://')) { $nuevo = 'https://' + $nuevo }; " ^
  "  $cfg.publicUrl = $nuevo; " ^
  "  $cfg.base_url = $nuevo + '/a/'; " ^
  "  $cfg | ConvertTo-Json -Depth 4 | Set-Content 'config.json' -Encoding UTF8; " ^
  "  Write-Host ('  ✅ Dominio configurado a: ' + $nuevo) -ForegroundColor Green; " ^
  "  Start-Process $nuevo; " ^
  "} else { " ^
  "  Start-Process $actual; " ^
  "}"

echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'powershell' -and $_.CommandLine -like '*server.ps1*' } | ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force } catch {} }"
powershell -NoProfile -ExecutionPolicy Bypass -File "server.ps1"

echo.
echo  Servidor detenido.
pause
