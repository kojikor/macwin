$ErrorActionPreference = 'Stop'

function Get-FunctionScriptBlock([string]$Path, [string]$Name) {
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $Path, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count) {
        throw "PowerShell syntax errors in ${Path}: $($parseErrors -join '; ')"
    }
    $definition = $ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq $Name
    }, $true)
    if (-not $definition) {
        throw "Function '$Name' was not found in $Path"
    }
    [scriptblock]::Create($definition.Extent.Text)
}

$windowsScripts = Split-Path -Parent $PSScriptRoot
$installScript = Join-Path $windowsScripts 'install.ps1'
$uninstallScript = Join-Path $windowsScripts 'uninstall.ps1'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("macwin-installer-tests-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot | Out-Null

try {
    $base = Join-Path $tempRoot 'macwin'
    $pathCases = @(
        @{ Path = (Join-Path $base 'macwin.exe'); Expected = $true },
        @{ Path = (Join-Path (Join-Path $base 'nested') 'macwin-tray.exe'); Expected = $true },
        @{ Path = (Join-Path "${base}-old" 'macwin.exe'); Expected = $false },
        @{ Path = (Join-Path $base 'MACWIN.EXE'); Expected = $true }
    )

    foreach ($script in @($installScript, $uninstallScript)) {
        . (Get-FunctionScriptBlock $script 'Test-PathWithinFolder')
        foreach ($case in $pathCases) {
            $actual = Test-PathWithinFolder -Path $case.Path -Folder $base
            if ($actual -ne $case.Expected) {
                throw "Unexpected folder match for '$($case.Path)' against '$base'"
            }
        }
    }

    . (Get-FunctionScriptBlock $uninstallScript 'Get-DefaultDestination')
    $hadLocalAppData = Test-Path Env:LOCALAPPDATA
    $oldLocalAppData = $env:LOCALAPPDATA
    try {
        $env:LOCALAPPDATA = Join-Path $tempRoot 'local'
        $releaseRoot = Join-Path $tempRoot 'release'
        New-Item -ItemType Directory -Path $releaseRoot | Out-Null
        New-Item -ItemType File -Path (Join-Path $releaseRoot 'install.ps1') | Out-Null
        $expectedDefault = Join-Path $env:LOCALAPPDATA 'Programs\macwin'
        if ((Get-DefaultDestination $releaseRoot) -ne $expectedDefault) {
            throw 'The bundled uninstaller must keep the standard install destination.'
        }

        $installedRoot = Join-Path $tempRoot 'custom-install'
        New-Item -ItemType Directory -Path $installedRoot | Out-Null
        if ((Get-DefaultDestination $installedRoot) -ne $installedRoot) {
            throw 'The installed uninstaller must default to its own folder.'
        }
    } finally {
        if ($hadLocalAppData) {
            $env:LOCALAPPDATA = $oldLocalAppData
        } else {
            Remove-Item Env:LOCALAPPDATA -ErrorAction SilentlyContinue
        }
    }
} finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
}

Write-Host 'Windows installer scope tests passed.'
