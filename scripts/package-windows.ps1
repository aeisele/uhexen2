[CmdletBinding()]
param(
    [string]$Version,
    [string]$BuildDirectory,
    [string]$OutputDirectory,
    [ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')]
    [string]$SourceRepository = 'aeisele/uhexen2'
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$commit = git -C $repo rev-parse HEAD
if ($LASTEXITCODE -ne 0) { throw 'Cannot identify the source commit.' }
if (!$Version) { $Version = 'dev-' + $commit.Substring(0, 12) }
if ($Version -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$') { throw 'Invalid package version.' }
if ($env:GITHUB_REPOSITORY) { $SourceRepository = $env:GITHUB_REPOSITORY }
if (!$BuildDirectory) { $BuildDirectory = Join-Path $repo 'build\win64' }
if (!$OutputDirectory) { $OutputDirectory = Join-Path $repo 'build\packages' }

# Package an explicit file list. Never archive the playing directory itself:
# it may contain copyrighted game data, personal saves, logs, or config.cfg.
$files = [ordered]@{}
foreach ($name in @('glh2.exe', 'Play-Hexen-II.cmd', 'Play-Hexen-II-Borderless.cmd',
    'libFLAC-8.dll', 'libmad-0.dll', 'libmikmod-3.dll', 'libmpg123-0.dll',
    'libogg-0.dll', 'libopus-0.dll', 'libopusfile-0.dll', 'libvorbis-0.dll',
    'libvorbisfile-3.dll', 'libxmp.dll')) {
    $files[$name] = Join-Path $BuildDirectory $name
}
$files['README.txt'] = Join-Path $repo 'docs\windows-release.txt'
$files['COPYING.txt'] = Join-Path $repo 'docs\COPYING'
$files['AUTHORS.txt'] = Join-Path $repo 'docs\AUTHORS'
$files['docs/windows-modernization.txt'] = Join-Path $repo 'docs\windows-modernization.txt'
$files['licenses/libtimidity-LGPL.txt'] = Join-Path $repo 'libs\timidity\COPYING'
$files['licenses/libtimidity-Artistic.txt'] = Join-Path $repo 'libs\timidity\COPYING.artistic'
foreach ($file in Get-ChildItem -LiteralPath (Join-Path $repo 'docs\windows-licenses') -File) {
    $files['licenses/' + $file.Name] = $file.FullName
}
foreach ($file in $files.Values) {
    if (!(Test-Path -LiteralPath $file -PathType Leaf)) { throw "Required package file is missing: $file" }
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$zipPath = Join-Path $OutputDirectory "hexen2-$Version-windows-x64.zip"
$checksumPath = "$zipPath.sha256"
# CreateNew prevents a second invocation from silently replacing a release.
$stream = [IO.File]::Open($zipPath, [IO.FileMode]::CreateNew)
$zip = $null
try {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create)
    foreach ($entry in $files.GetEnumerator()) {
        [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $entry.Value, $entry.Key)
    }
    $info = $zip.CreateEntry('BUILD-INFO.txt')
    $writer = [IO.StreamWriter]::new($info.Open())
    try {
        $writer.WriteLine("Package: $Version")
        $writer.WriteLine("Source commit: $commit")
        $writer.WriteLine("Source: https://github.com/$SourceRepository/tree/$commit")
        $writer.WriteLine("Source archive: https://github.com/$SourceRepository/archive/$commit.zip")
        $writer.WriteLine('Build: scripts/build-windows.ps1 -Bootstrap (optimized Windows x64 OpenGL)')
    } finally { $writer.Dispose() }
} finally {
    if ($zip) { $zip.Dispose() }
    $stream.Dispose()
}
$hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
"$hash  $([IO.Path]::GetFileName($zipPath))" | Set-Content -LiteralPath $checksumPath -Encoding ascii
Write-Host "Packaged $zipPath"
Write-Host "Checksum $checksumPath"
