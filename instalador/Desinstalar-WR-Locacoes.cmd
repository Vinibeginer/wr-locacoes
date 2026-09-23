@echo off
chcp 65001 >nul
title Remover WR Locacoes
powershell -NoProfile -ExecutionPolicy Bypass -Command "$f='%~f0'; $s=[IO.File]::ReadAllText($f,[Text.Encoding]::UTF8); $i=$s.LastIndexOf('#INICIO'+'_POWERSHELL'); Invoke-Expression $s.Substring($i)"
echo.
pause
exit /b

#INICIO_POWERSHELL
# Remove os atalhos criados pelo instalador do WR Locações.
# Não apaga nenhum dado: contratos, cadastros e login ficam no sistema online.
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$Nome  = 'WR Locações'
$Pasta = Join-Path $env:LOCALAPPDATA 'WR Locacoes'
Write-Host ''
Write-Host '  WR LOCAÇÕES - remover aplicativo' -ForegroundColor White
Write-Host ''
$removidos = 0
foreach ($destino in @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('Programs'))) {
  $lnk = Join-Path $destino "$Nome.lnk"
  if (Test-Path -LiteralPath $lnk) { Remove-Item -LiteralPath $lnk -Force; $removidos++ }
}
if (Test-Path -LiteralPath $Pasta) { Remove-Item -LiteralPath $Pasta -Recurse -Force }
if ($removidos) { Write-Host "  $removidos atalho(s) removido(s). O sistema continua disponível pelo navegador." -ForegroundColor Green }
else { Write-Host '  Nenhum atalho do WR Locações encontrado neste computador.' -ForegroundColor Yellow }
