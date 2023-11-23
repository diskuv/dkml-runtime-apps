<#
.Synopsis
    Find a DkML compatible Visual Studio and writes the location into the DkML home.
.Parameter DkmlPath
    The directory containing .dkmlroot
.Parameter AuditOnly
    Advanced.

    When specified the location of Visual Studio is not written into the DkML home.
.Example
    PS> cache-vsstudio.ps1
#>

[CmdletBinding()]
param (
    [string]
    $DkmlPath,
    [switch]
    $AuditOnly
)

$ErrorActionPreference = "Stop"
$InformationPreference = "Continue"

$HereScript = $MyInvocation.MyCommand.Path
$HereDir = (get-item $HereScript).Directory
if (!$DkmlPath) {
    $DkmlPath = $HereDir.Parent.Parent.FullName
}
if (!(Test-Path -Path $DkmlPath\.dkmlroot)) {
    throw "Could not locate the DkML scripts. Thought DkmlPath was $DkmlPath"
}

$PSDefaultParameterValues = @{'Out-File:Encoding' = 'utf8'} # for Tee-Object. https://stackoverflow.com/a/58920518

$dsc = [System.IO.Path]::DirectorySeparatorChar
$env:PSModulePath += "$([System.IO.Path]::PathSeparator)$DkmlPath${dsc}vendor${dsc}drd${dsc}src${dsc}windows"
Import-Module Machine

# ----------------------------------------------------------------
# Installation prefix

# Match set_dkmlparenthomedir() in crossplatform-functions.sh
if ($env:LOCALAPPDATA) {
    $DkmlParentHomeDir = "$env:LOCALAPPDATA\Programs\DkML"
} elseif ($env:XDG_DATA_HOME) {
    $DkmlParentHomeDir = "$env:XDG_DATA_HOME/dkml"
} elseif ($env:HOME) {
    $DkmlParentHomeDir = "$env:HOME/.local/share/dkml"
}

# Two birds with one stone:
# 1. Create DkML home directory (parts of this script assume the
#    directory exists).
# 2. PowerShell 5's [System.IO.File]::WriteAllText() requires an absolute
#    path. And getting an absolute path requires that the directory exist first.
if (!(Test-Path -Path $DkmlParentHomeDir)) { New-Item -Path $DkmlParentHomeDir -ItemType Directory | Out-Null }

# ----------------------------------------------------------------
# Utilities

# PowerShell 5.1 (the default on Windows 10) writes UTF-8 with BOM.
# Confer: https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.management/set-content?view=powershell-5.1
# https://stackoverflow.com/a/5596984 is a solution.
$Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $False

# ----------------------------------------------------------------
# BEGIN Visual Studio Setup PowerShell Module

Import-VSSetup -TempPath "$env:TEMP\vssetup"
$CompatibleVisualStudios = Get-CompatibleVisualStudios -ErrorIfNotFound -VcpkgCompatibility:$VcpkgCompatibility
$ChosenVisualStudio = ($CompatibleVisualStudios | Select-Object -First 1)
$VisualStudioProps = Get-VisualStudioProperties -VisualStudioInstallation $ChosenVisualStudio

Write-Information "Configuring DkML to use the compatible Visual Studio found at: $($VisualStudioProps.InstallPath)"

if (!$AuditOnly) {
    $VisualStudioDirPath = "$DkmlParentHomeDir\vsstudio.dir.txt"
    $VisualStudioJsonPath = "$DkmlParentHomeDir\vsstudio.json"
    $VisualStudioVcVarsVerPath = "$DkmlParentHomeDir\vsstudio.vcvars_ver.txt"
    $VisualStudioWinSdkVerPath = "$DkmlParentHomeDir\vsstudio.winsdk.txt"
    $VisualStudioMsvsPreferencePath = "$DkmlParentHomeDir\vsstudio.msvs_preference.txt"
    $VisualStudioCMakeGeneratorPath = "$DkmlParentHomeDir\vsstudio.cmake_generator.txt"
    [System.IO.File]::WriteAllText($VisualStudioDirPath, "$($VisualStudioProps.InstallPath)", $Utf8NoBomEncoding)
    [System.IO.File]::WriteAllText($VisualStudioJsonPath, ($CompatibleVisualStudios | ConvertTo-Json -Depth 5), $Utf8NoBomEncoding)
    [System.IO.File]::WriteAllText($VisualStudioVcVarsVerPath, "$($VisualStudioProps.VcVarsVer)", $Utf8NoBomEncoding)
    [System.IO.File]::WriteAllText($VisualStudioWinSdkVerPath, "$($VisualStudioProps.WinSdkVer)", $Utf8NoBomEncoding)
    [System.IO.File]::WriteAllText($VisualStudioMsvsPreferencePath, "$($VisualStudioProps.MsvsPreference)", $Utf8NoBomEncoding)
    [System.IO.File]::WriteAllText($VisualStudioCMakeGeneratorPath, "$($VisualStudioProps.CMakeGenerator)", $Utf8NoBomEncoding)
}

# END Visual Studio Setup PowerShell Module
# ----------------------------------------------------------------
