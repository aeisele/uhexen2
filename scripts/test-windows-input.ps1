[CmdletBinding()]
param([string]$ToolchainPath)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
if (!$ToolchainPath) { $ToolchainPath = Join-Path $repo '.tools\w64devkit' }
$output = Join-Path $repo 'build\tests'
New-Item -ItemType Directory -Path $output -Force | Out-Null
$exe = Join-Path $output 'windows-input.exe'
$includes = @('engine\hexen2', 'engine\h2shared', 'common',
    'oslibs\windows\misc\include', 'oslibs\windows\dxsdk\include') |
    ForEach-Object { '-I' + (Join-Path $repo $_) }
& (Join-Path $ToolchainPath 'bin\gcc.exe') -O2 -fwhole-program `
    -DWIN32_LEAN_AND_MEAN -DDX_DLSYM @includes `
    (Join-Path $PSScriptRoot 'test-windows-input.c') '-Wl,--gc-sections' -luser32 -lwinmm -o $exe
if ($LASTEXITCODE -ne 0) { throw 'Input test compilation failed.' }
& $exe
if ($LASTEXITCODE -ne 0) { throw 'Input regression test failed.' }
