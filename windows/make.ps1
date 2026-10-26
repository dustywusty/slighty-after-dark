<#
.SYNOPSIS
    Builds, verifies, and installs the Windows screen saver.

.DESCRIPTION
    The Windows counterpart of the repository Makefile:

        .\windows\make.ps1 build       # Build a Release .scr
        .\windows\make.ps1 verify      # Build, then load every saver offscreen
        .\windows\make.ps1 install     # Verify, then install for the current user
        .\windows\make.ps1 uninstall
        .\windows\make.ps1 clean

    Requires Build Tools for Visual Studio 2026 (or Visual Studio) with the
    "Desktop development with C++" workload.
#>
[CmdletBinding()]
param(
    [ValidateSet('build', 'verify', 'install', 'uninstall', 'clean')]
    [string]$Target = 'build',
    [ValidateSet('x64', 'ARM64')]
    [string]$Architecture = $(if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'ARM64' } else { 'x64' }),
    [string]$Configuration = 'Release'
)

$ErrorActionPreference = 'Stop'

$RepositoryRoot = Split-Path -Parent $PSScriptRoot
$BuildDirectory = Join-Path $RepositoryRoot "Build\windows\$Architecture"
$ProductName = 'Slightly After Dark.scr'
$Product = Join-Path $BuildDirectory "$Configuration\$ProductName"
$InstallDirectory = Join-Path $env:LOCALAPPDATA 'Programs\Slightly After Dark'
$InstalledProduct = Join-Path $InstallDirectory $ProductName

function Find-CMake {
    $command = Get-Command cmake -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path $vswhere) {
        $installation = & $vswhere -latest -products '*' `
            -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
            -property installationPath
        if ($installation) {
            $cmake = Join-Path $installation 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
            if (Test-Path $cmake) {
                return $cmake
            }
        }
    }
    throw 'CMake was not found. Install Build Tools for Visual Studio with "Desktop development with C++".'
}

function Invoke-Checked([string]$FilePath, [string[]]$Arguments) {
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$FilePath exited with code $LASTEXITCODE"
    }
}

function Invoke-Build {
    $submodule = Join-Path $RepositoryRoot 'shared\after-dark-css\all\base.css'
    if (-not (Test-Path $submodule)) {
        Invoke-Checked git @('-C', $RepositoryRoot, 'submodule', 'update', '--init', '--recursive')
    }
    $cmake = Find-CMake
    Invoke-Checked $cmake @('-S', (Join-Path $RepositoryRoot 'windows'), '-B', $BuildDirectory, '-A', $Architecture)
    Invoke-Checked $cmake @('--build', $BuildDirectory, '--config', $Configuration)
}

function Invoke-Verify {
    Invoke-Build
    $log = New-TemporaryFile
    try {
        $process = Start-Process -FilePath $Product -ArgumentList '/verify' -Wait -PassThru `
            -NoNewWindow -RedirectStandardOutput $log
        Get-Content $log
        if ($process.ExitCode -ne 0) {
            throw "Verification failed with exit code $($process.ExitCode)"
        }
    } finally {
        Remove-Item $log -ErrorAction SilentlyContinue
    }
}

switch ($Target) {
    'build' {
        Invoke-Build
        Write-Host "Built $Product"
    }
    'verify' {
        Invoke-Verify
    }
    'install' {
        Invoke-Verify
        Get-Process -Name 'Slightly After Dark' -ErrorAction SilentlyContinue | Stop-Process -Force
        New-Item -ItemType Directory -Force $InstallDirectory | Out-Null
        Copy-Item $Product $InstalledProduct -Force
        # The same handler Explorer uses for right-click > Install: selects the
        # screen saver and opens Screen Saver Settings.
        Start-Process rundll32.exe -ArgumentList "desk.cpl,InstallScreenSaver `"$InstalledProduct`""
        Write-Host "Installed $InstalledProduct"
    }
    'uninstall' {
        Get-Process -Name 'Slightly After Dark' -ErrorAction SilentlyContinue | Stop-Process -Force
        Remove-Item $InstallDirectory -Recurse -Force -ErrorAction SilentlyContinue
        # Windows may record the selection as an 8.3 path, so rather than
        # comparing paths, clear it once it no longer points at a file.
        $desktop = 'HKCU:\Control Panel\Desktop'
        $selected = (Get-ItemProperty $desktop -Name 'SCRNSAVE.EXE' -ErrorAction SilentlyContinue).'SCRNSAVE.EXE'
        if ($selected -and -not (Test-Path -LiteralPath $selected)) {
            Remove-ItemProperty $desktop -Name 'SCRNSAVE.EXE'
        }
        Write-Host "Removed $InstalledProduct"
    }
    'clean' {
        Remove-Item $BuildDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}
