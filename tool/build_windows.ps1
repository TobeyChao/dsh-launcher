# 构建 Windows 启动器(需在 Windows 机器上执行)。
#
# 前置:Flutter SDK(用 FLUTTER 环境变量指定,或自动探测)、Visual Studio 桌面开发工作负载
#       (flutter build windows 需要)。
# 产物:build/windows/x64/runner/Release/(dsh_launcher.exe,无运行时嵌入;
#      分发时复制整个 Release 目录,本地使用、未签名勿分发)。
$ErrorActionPreference = "Stop"

$LauncherDir = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

# Flutter 定位:环境变量优先,其次 PATH,最后常见安装位置。
function Get-FlutterExe {
  if ($env:FLUTTER) {
    $bat = Join-Path $env:FLUTTER "bin\flutter.bat"
    if (Test-Path $bat) { return $bat }
    return $env:FLUTTER
  }
  $cmd = Get-Command flutter -CommandType Application -ErrorAction SilentlyContinue |
    Select-Object -First 1
  if ($cmd) { return $cmd.Source }
  $candidates = @()
  if ($env:USERPROFILE) {
    $candidates += (Join-Path $env:USERPROFILE "development\flutter\bin\flutter.bat")
    $candidates += (Join-Path $env:USERPROFILE "flutter\bin\flutter.bat")
    $candidates += (Join-Path $env:USERPROFILE "scoop\apps\flutter\current\bin\flutter.bat")
  }
  if ($env:LOCALAPPDATA) {
    $candidates += (Join-Path $env:LOCALAPPDATA "flutter\bin\flutter.bat")
  }
  $candidates += "C:\flutter\bin\flutter.bat"
  $candidates += "C:\src\flutter\bin\flutter.bat"
  foreach ($candidate in $candidates) {
    if (Test-Path $candidate) { return $candidate }
  }
  return $null
}

$Flutter = Get-FlutterExe
if (-not $Flutter) {
  Write-Host "[error] 未找到 Flutter SDK。请安装后重试,或用 FLUTTER 环境变量指定。" -ForegroundColor Red
  exit 1
}

Write-Host "[1/2] 构建 Windows launcher(flutter build windows --release)..."
Write-Host "      flutter: $Flutter"
Push-Location $LauncherDir
& $Flutter build windows --release
if ($LASTEXITCODE -ne 0) { Pop-Location; exit 1 }
Pop-Location

$ReleaseDir = Join-Path $LauncherDir "build\windows\x64\runner\Release"
if (-not (Test-Path (Join-Path $ReleaseDir "dsh_launcher.exe"))) {
  Write-Host "[error] launcher 产物缺失: $ReleaseDir\dsh_launcher.exe" -ForegroundColor Red
  exit 1
}

Write-Host "[2/2] 完成:$ReleaseDir(分发整个 Release 目录;本地使用,未签名勿分发)"
