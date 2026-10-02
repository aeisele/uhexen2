[CmdletBinding()]
param(
    [switch]$Bootstrap,
    [switch]$DebugBuild,
    [string]$ToolchainPath,
    [ValidateRange(1, 64)][int]$Jobs = 8
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$toolsDir = Join-Path $repo '.tools'
if (!$ToolchainPath) { $ToolchainPath = Join-Path $toolsDir 'w64devkit' }
$compiler = Join-Path $ToolchainPath 'bin\gcc.exe'

if (!(Test-Path -LiteralPath $compiler)) {
    if (!$Bootstrap) {
        throw 'Compiler missing. Run scripts\build-windows.ps1 -Bootstrap to download the portable toolchain, or supply -ToolchainPath.'
    }
    $version = '2.10.0'
    $sha256 = '18d0a4c71a166f8401ab6305781bec5882b40b5e06ba9807c61cb5f3b3c6325e'
    New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null
    $archive = Join-Path $toolsDir "w64devkit-x64-$version.7z.exe"
    if (!(Test-Path -LiteralPath $archive)) {
        Invoke-WebRequest "https://github.com/skeeto/w64devkit/releases/download/v$version/w64devkit-x64-$version.7z.exe" -OutFile $archive
    }
    if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $sha256) {
        throw "Checksum mismatch for $archive. Remove that archive before retrying."
    }
    # The archive is a GUI executable: explicitly wait for extraction to finish.
    $extract = Start-Process -FilePath $archive -ArgumentList @('-y', "-o`"$toolsDir`"") -WindowStyle Hidden -Wait -PassThru
    if ($extract.ExitCode -ne 0) { throw "Extraction failed: $($extract.ExitCode)" }
    $ToolchainPath = Join-Path $toolsDir 'w64devkit'
    $compiler = Join-Path $ToolchainPath 'bin\gcc.exe'
}

$ToolchainPath = (Resolve-Path -LiteralPath $ToolchainPath).Path
$compiler = Join-Path $ToolchainPath 'bin\gcc.exe'
$savedPath = $env:PATH
try {
    $env:PATH = "$(Join-Path $ToolchainPath 'bin');$savedPath"
    & $compiler --version | Select-Object -First 1
    $makeArgs = @('-s', '-B', '-C', (Join-Path $repo 'engine\hexen2'),
        'glh2', 'W64BUILD=1', "-j$Jobs")
    if ($DebugBuild) { $makeArgs += 'DEBUG=1' }
    # Rebuild all objects: the legacy Makefile shares them between renderers
    # and does not track changes to compiler options or headers.
    & (Join-Path $ToolchainPath 'bin\make.exe') @makeArgs
    if ($LASTEXITCODE -ne 0) { throw "Build failed: $LASTEXITCODE" }
    $output = Join-Path $repo 'build\win64'
    New-Item -ItemType Directory -Path $output -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $repo 'engine\hexen2\glh2.exe') -Destination $output
    Get-ChildItem -LiteralPath (Join-Path $repo 'oslibs\windows\codecs\x64') -Filter '*.dll' |
        Copy-Item -Destination $output
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'play-windows.cmd') -Destination (Join-Path $output 'Play-Hexen-II.cmd')
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'play-borderless.cmd') -Destination (Join-Path $output 'Play-Hexen-II-Borderless.cmd')
    Write-Host "Built $output\glh2.exe"
} finally {
    $env:PATH = $savedPath
}
