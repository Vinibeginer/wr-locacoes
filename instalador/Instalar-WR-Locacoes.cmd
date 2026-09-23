@echo off
chcp 65001 >nul
title Instalador WR Locacoes
powershell -NoProfile -ExecutionPolicy Bypass -Command "$f='%~f0'; $s=[IO.File]::ReadAllText($f,[Text.Encoding]::UTF8); $i=$s.LastIndexOf('#INICIO'+'_POWERSHELL'); Invoke-Expression $s.Substring($i)"
echo.
pause
exit /b

#INICIO_POWERSHELL
# Instalador do WR Locações para Windows.
# Cria atalhos "WR Locações" na área de trabalho e no menu Iniciar que abrem o sistema
# em janela própria (sem barra do navegador), usando o Google Chrome ou o Microsoft Edge.
# Não precisa de administrador e não altera nada no navegador nem no banco de dados.
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$Nome   = 'WR Locações'
$Url    = 'https://vinibeginer.github.io/wr-locacoes/'
$Pasta  = Join-Path $env:LOCALAPPDATA 'WR Locacoes'

Write-Host ''
Write-Host '  ==============================================' -ForegroundColor DarkCyan
Write-Host '     WR LOCAÇÕES - instalação do aplicativo' -ForegroundColor White
Write-Host '  ==============================================' -ForegroundColor DarkCyan
Write-Host ''
try {
  # 1. Navegador: Chrome se houver, senão Edge (vem com o Windows)
  $navegadores = @(
    @{ n = 'Google Chrome';  p = "$env:ProgramFiles\Google\Chrome\Application\chrome.exe" },
    @{ n = 'Google Chrome';  p = "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe" },
    @{ n = 'Google Chrome';  p = "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe" },
    @{ n = 'Microsoft Edge'; p = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe" },
    @{ n = 'Microsoft Edge'; p = "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe" }
  )
  $nav = $navegadores | Where-Object { $_.p -and (Test-Path -LiteralPath $_.p) } | Select-Object -First 1
  if (-not $nav) { throw 'Nenhum navegador compatível encontrado. Instale o Google Chrome ou o Microsoft Edge e rode o instalador de novo.' }
  Write-Host "  [1/3] Navegador encontrado: $($nav.n)" -ForegroundColor Green

  # 2. Ícone do sistema
  New-Item -ItemType Directory -Force -Path $Pasta | Out-Null
  $icone = Join-Path $Pasta 'wr-locacoes.ico'
  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072
    Invoke-WebRequest -Uri ($Url + 'icons/wr-locacoes.ico') -OutFile $icone -UseBasicParsing
  } catch { $icone = $null }
  if ($icone -and (Test-Path -LiteralPath $icone)) {
    $iconeAtalho = "$icone,0"; Write-Host '  [2/3] Ícone baixado' -ForegroundColor Green
  } else {
    $iconeAtalho = "$($nav.p),0"; Write-Host '  [2/3] Sem internet para baixar o ícone; usando o ícone do navegador' -ForegroundColor Yellow
  }

  # 3. Atalhos na área de trabalho e no menu Iniciar
  $shell = New-Object -ComObject WScript.Shell
  foreach ($destino in @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('Programs'))) {
    $atalho = $shell.CreateShortcut((Join-Path $destino "$Nome.lnk"))
    $atalho.TargetPath       = $nav.p
    $atalho.Arguments        = "--app=$Url"
    $atalho.WorkingDirectory = Split-Path -Parent $nav.p
    $atalho.IconLocation     = $iconeAtalho
    $atalho.Description      = 'WR Locações - controle de locação de equipamentos'
    $atalho.Save()
  }
  Write-Host '  [3/3] Atalhos criados na área de trabalho e no menu Iniciar' -ForegroundColor Green
  Write-Host ''
  Write-Host '  Instalação concluída! Abrindo o WR Locações...' -ForegroundColor White
  Write-Host '  Dica: com o aplicativo aberto, clique com o botão direito no ícone da barra de tarefas' -ForegroundColor Gray
  Write-Host '  e escolha "Fixar na barra de tarefas".' -ForegroundColor Gray
  Start-Process -FilePath $nav.p -ArgumentList "--app=$Url"
} catch {
  Write-Host ''
  Write-Host "  ERRO: $($_.Exception.Message)" -ForegroundColor Red
}
