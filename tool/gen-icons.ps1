# 生成 DSH Launcher 图标:assets/icons/tray_icon.ico / tray_icon.png,
# windows/runner/resources/app_icon.ico。重新设计品牌后运行本脚本即可再生成。
Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$iconsDir = Join-Path $root 'assets\icons'
New-Item -ItemType Directory -Force -Path $iconsDir | Out-Null

function New-DsBitmap([int]$size) {
  $bmp = New-Object System.Drawing.Bitmap($size, $size)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias
  $g.Clear([System.Drawing.Color]::Transparent)

  # 圆角方块(半径 18%)+ 蓝渐变(DSH 品牌:accent #3B5BE0 → primary #243B7A)
  $r = [float]($size * 0.18)
  $path = New-Object System.Drawing.Drawing2D.GraphicsPath
  $pad = [float]($size * 0.04)
  $w = [float]($size - 2 * $pad)
  $path.AddArc($pad, $pad, $r * 2, $r * 2, 180, 90)
  $path.AddArc($pad + $w - $r * 2, $pad, $r * 2, $r * 2, 270, 90)
  $path.AddArc($pad + $w - $r * 2, $pad + $w - $r * 2, $r * 2, $r * 2, 0, 90)
  $path.AddArc($pad, $pad + $w - $r * 2, $r * 2, $r * 2, 90, 90)
  $path.CloseFigure()

  $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    (New-Object System.Drawing.PointF(0, 0)),
    (New-Object System.Drawing.PointF($size, $size)),
    [System.Drawing.Color]::FromArgb(255, 59, 91, 224),
    [System.Drawing.Color]::FromArgb(255, 36, 59, 122))
  $g.FillPath($brush, $path)

  # "DS" 字标
  $font = New-Object System.Drawing.Font('Segoe UI', [float]($size * 0.42), [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
  $sf = New-Object System.Drawing.StringFormat
  $sf.Alignment = [System.Drawing.StringAlignment]::Center
  $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
  $g.DrawString('DS', $font, [System.Drawing.Brushes]::White, (New-Object System.Drawing.RectangleF(0, 0, $size, $size)), $sf)

  $font.Dispose(); $sf.Dispose(); $brush.Dispose(); $path.Dispose(); $g.Dispose()
  return $bmp
}

function Save-PngBytes([System.Drawing.Bitmap]$bmp, [uint32]$size) {
  $ms = New-Object System.IO.MemoryStream
  $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
  $bytes = $ms.ToArray()
  $ms.Dispose()
  return $bytes
}

# C# 助手组装 ICO(PNG 内嵌,避免 PowerShell BinaryWriter 绑定问题)
Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.IO;
public static class IcoBuilder {
  public static byte[] Build(byte[][] datas, int[] sizes) {
    using (var outMs = new MemoryStream())
    using (var bw = new BinaryWriter(outMs)) {
      bw.Write((ushort)0); bw.Write((ushort)1); bw.Write((ushort)sizes.Length);
      int offset = 6 + 16 * sizes.Length;
      for (int i = 0; i < sizes.Length; i++) {
        int s = sizes[i];
        bw.Write((byte)(s >= 256 ? 0 : s)); bw.Write((byte)(s >= 256 ? 0 : s));
        bw.Write((byte)0); bw.Write((byte)0);
        bw.Write((ushort)1); bw.Write((ushort)32);
        bw.Write((uint)datas[i].Length); bw.Write((uint)offset);
        offset += datas[i].Length;
      }
      foreach (var d in datas) bw.Write(d);
      bw.Flush();
      return outMs.ToArray();
    }
  }
}
"@

# 托盘 PNG(256)
$png = New-DsBitmap 256
$png.Save((Join-Path $iconsDir 'tray_icon.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$png.Dispose()

# ICO(16/32/48/64/128/256,Png 内嵌 ICO,Windows Vista+ 支持)
$sizes = @(16, 32, 48, 64, 128, 256)
$datas = @()
foreach ($s in $sizes) {
  $bmp = New-DsBitmap $s
  $datas += , (Save-PngBytes $bmp $s)
  $bmp.Dispose()
}
$icoBytes = [IcoBuilder]::Build($datas, $sizes)
[System.IO.File]::WriteAllBytes((Join-Path $iconsDir 'tray_icon.ico'), $icoBytes)
Write-Output "tray_icon.ico: $($icoBytes.Length) bytes"

# 应用图标:替换 Flutter Windows runner 模板图标
$appIcon = Join-Path $root 'windows\runner\resources\app_icon.ico'
if (Test-Path $appIcon) {
  Copy-Item -Force (Join-Path $iconsDir 'tray_icon.ico') $appIcon
  Write-Output "app icon replaced: $appIcon"
} else {
  Write-Output "[warn] app icon path missing: $appIcon"
}

Write-Output "icons written to: $iconsDir"
