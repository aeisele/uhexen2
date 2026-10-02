[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$testDir = Join-Path $repo ('build\tests\package-' + [guid]::NewGuid().ToString('N'))
$inputDir = Join-Path $testDir 'input'
$outputDir = Join-Path $testDir 'output'
New-Item -ItemType Directory -Path (Join-Path $inputDir 'data1') -Force | Out-Null
$binaries = @('glh2.exe', 'Play-Hexen-II.cmd', 'Play-Hexen-II-Borderless.cmd',
    'libFLAC-8.dll', 'libmad-0.dll', 'libmikmod-3.dll', 'libmpg123-0.dll',
    'libogg-0.dll', 'libopus-0.dll', 'libopusfile-0.dll', 'libvorbis-0.dll',
    'libvorbisfile-3.dll', 'libxmp.dll')
foreach ($name in $binaries) { 'test fixture' | Set-Content -LiteralPath (Join-Path $inputDir $name) }
foreach ($name in @('data1\pak0.pak', 'data1\config.cfg', 'data1\saved.gip', 'debug_h2.log', 'unexpected.dll')) {
    'must not be distributed' | Set-Content -LiteralPath (Join-Path $inputDir $name)
}
$params = @{ BuildDirectory = $inputDir; OutputDirectory = $outputDir; Version = 'v1.5.10-test.1' }
& (Join-Path $PSScriptRoot 'package-windows.ps1') @params
$zipPath = Join-Path $outputDir 'hexen2-v1.5.10-test.1-windows-x64.zip'
$expectedHash = (Get-FileHash -LiteralPath $zipPath).Hash.ToLowerInvariant()
$checksum = (Get-Content -LiteralPath "$zipPath.sha256" -Raw).Trim()
if ($checksum -cne "$expectedHash  $([IO.Path]::GetFileName($zipPath))") { throw 'ZIP checksum does not match.' }
$zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
try {
    $entries = @($zip.Entries.FullName)
    foreach ($name in ($binaries + @('README.txt', 'COPYING.txt', 'AUTHORS.txt', 'BUILD-INFO.txt'))) {
        if ($entries -cnotcontains $name) { throw "Required entry missing: $name" }
    }
    foreach ($name in $entries) {
        if ($name -cmatch '(^data1/|\.pak$|\.cfg$|\.gip$|\.log$|unexpected\.dll$)') { throw "Private file packaged: $name" }
    }
    $reader = [IO.StreamReader]::new($zip.GetEntry('BUILD-INFO.txt').Open())
    try { $info = $reader.ReadToEnd() } finally { $reader.Dispose() }
    $commit = git -C $repo rev-parse HEAD
    if (!$info.Contains("Source commit: $commit")) { throw 'Incorrect source commit in package.' }
} finally { $zip.Dispose() }
$failed = $false
try { & (Join-Path $PSScriptRoot 'package-windows.ps1') @params } catch { $failed = $true }
if (!$failed) { throw 'An existing package was overwritten.' }
$params.Version = '..\invalid'
$failed = $false
try { & (Join-Path $PSScriptRoot 'package-windows.ps1') @params } catch { $failed = $true }
if (!$failed) { throw 'An invalid version was accepted.' }
$params.Version = 'missing-runtime'
Remove-Item -LiteralPath (Join-Path $inputDir 'libogg-0.dll')
$failed = $false
try { & (Join-Path $PSScriptRoot 'package-windows.ps1') @params } catch { $failed = $true }
if (!$failed) { throw 'An incomplete runtime was packaged.' }
if (Test-Path -LiteralPath (Join-Path $outputDir 'hexen2-missing-runtime-windows-x64.zip')) { throw 'Incomplete package was left behind.' }
'PASS: runtime files, source metadata, checksum, private data exclusion, duplicate/invalid versions, missing runtime rejection.'
