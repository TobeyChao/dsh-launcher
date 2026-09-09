# 构建 Windows 启动器(需在 Windows 机器上执行)。
#
# 前置:Flutter SDK(在 PATH)+ Visual Studio 桌面开发工作负载(flutter build windows 需要)。
# 产物:launcher/build/windows/x64/runner/Release/(DSHLauncher.exe,无运行时嵌入)。
$ErrorActionPreference = "Stop"

$LauncherDir = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

Write-Host "[1/2] 构建 Windows launcher(flutter build windows --release)..."
Push-Location $LauncherDir
& flutter build windows --release
if ($LASTEXITCODE -ne 0) { Pop-Location; exit 1 }
Pop-Location

$ReleaseDir = Join-Path $LauncherDir "build\windows\x64\runner\Release"
if (-not (Test-Path (Join-Path $ReleaseDir "dsh_launcher.exe"))) {
  Write-Host "[error] launcher 产物缺失: $ReleaseDir\dsh_launcher.exe" -ForegroundColor Red
  exit 1
}

Write-Host "[2/2] 完成:$ReleaseDir(分发整个 Release 目录;本地使用,未签名勿分发)"
