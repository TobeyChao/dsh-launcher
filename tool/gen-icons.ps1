# Export the shared PNG masters for Windows and macOS (Python + Pillow required).
$ErrorActionPreference = 'Stop'
$script = Join-Path $PSScriptRoot 'gen_icons.py'
if (Get-Command py -ErrorAction SilentlyContinue) {
  & py -3 $script
} else {
  & python $script
}
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
