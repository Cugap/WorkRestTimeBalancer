#Requires -Version 5.1
<#
.SYNOPSIS
    Собирает приложения WorkRestTimeBalancer и складывает готовые файлы в dist/.

.DESCRIPTION
    Одна команда из корня репозитория собирает Android APK и/или Windows-сборку.
    Результат всегда оказывается в одной папке dist/ в корне репозитория:

        dist/android/work_rest_time_balancer-release.apk
        dist/windows/work_rest_time_balancer/work_rest_time_balancer.exe

.PARAMETER Target
    all (по умолчанию), android или windows.

.PARAMETER Mode
    release (по умолчанию) или debug.

.PARAMETER SplitPerAbi
    Для release-сборки Android сделать отдельные APK под каждую ABI.

.EXAMPLE
    .\build.ps1

.EXAMPLE
    .\build.ps1 -Mode debug -Target windows

.EXAMPLE
    .\build.ps1 -Target android -SplitPerAbi
#>
[CmdletBinding()]
param(
    [ValidateSet('all', 'android', 'windows')]
    [string]$Target = 'all',

    [ValidateSet('debug', 'release')]
    [string]$Mode = 'release',

    [switch]$SplitPerAbi
)

$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
$appDir = Join-Path $root 'app'
$distDir = Join-Path $root 'dist'
$mode = $Mode.ToLowerInvariant()

if (-not (Test-Path (Join-Path $appDir 'pubspec.yaml'))) {
    throw "Не найден Flutter-проект: $appDir"
}

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'flutter не найден в PATH. Установите Flutter: https://docs.flutter.dev/get-started/install/windows'
}

function Invoke-Flutter {
    param([string[]]$FlutterArguments)

    Write-Host ''
    Write-Host "> flutter $($FlutterArguments -join ' ')" -ForegroundColor Cyan
    & flutter @FlutterArguments
    if ($LASTEXITCODE -ne 0) {
        throw "flutter $($FlutterArguments -join ' ') завершился с кодом $LASTEXITCODE"
    }
}

function Copy-BuildOutput {
    param(
        [string]$Source,
        [string]$Destination
    )

    if (-not (Test-Path $Source)) {
        throw "Не найдена папка сборки: $Source"
    }

    if (Test-Path $Destination) {
        Remove-Item $Destination -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null

    Copy-Item -Path $Source -Destination $Destination -Recurse -Force
}

Push-Location $appDir
try {
    Invoke-Flutter -FlutterArguments @('pub', 'get')

    if ($Target -eq 'all' -or $Target -eq 'android') {
        $apkSourceDir = Join-Path $appDir 'build\app\outputs\flutter-apk'

        # Очищаем APK прошлых сборок, чтобы в dist не попали чужие ABI и режимы.
        if (Test-Path $apkSourceDir) {
            Get-ChildItem -Path $apkSourceDir -Filter '*.apk' | Remove-Item -Force
        }

        $apkArguments = @('build', 'apk', "--$mode")

        # На этой машине Gradle падает на инкрементальном Kotlin-кеше
        # (см. README, «Решение проблем»); собираем без него.
        $apkArguments += @('-P', 'kotlin.incremental=false')

        if ($SplitPerAbi) {
            if ($mode -eq 'release') {
                $apkArguments += '--split-per-abi'
            }
            else {
                Write-Warning '-SplitPerAbi действует только для release; для debug собирается один APK на все ABI.'
            }
        }

        Invoke-Flutter -FlutterArguments $apkArguments

        $apkDistDir = Join-Path $distDir 'android'
        if (Test-Path $apkDistDir) {
            Remove-Item $apkDistDir -Recurse -Force
        }
        New-Item -ItemType Directory -Force -Path $apkDistDir | Out-Null

        $apks = @(Get-ChildItem -Path $apkSourceDir -Filter '*.apk')
        if ($apks.Count -eq 0) {
            throw "После сборки не найдено ни одного APK в $apkSourceDir"
        }

        foreach ($apk in $apks) {
            # app-debug.apk -> work_rest_time_balancer-debug.apk
            $name = $apk.Name -replace '^app-', 'work_rest_time_balancer-'
            Copy-Item -Path $apk.FullName -Destination (Join-Path $apkDistDir $name) -Force
        }
    }

    if ($Target -eq 'all' -or $Target -eq 'windows') {
        Invoke-Flutter -FlutterArguments @('build', 'windows', "--$mode")

        $configuration = if ($mode -eq 'debug') { 'Debug' } else { 'Release' }
        $windowsSourceDir = Join-Path $appDir "build\windows\x64\runner\$configuration"
        $windowsDistDir = Join-Path $distDir 'windows\work_rest_time_balancer'

        Copy-BuildOutput -Source $windowsSourceDir -Destination $windowsDistDir
    }
}
finally {
    Pop-Location
}

Write-Host ''
Write-Host 'Готово:' -ForegroundColor Green

if ($Target -eq 'all' -or $Target -eq 'android') {
    Get-ChildItem -Path (Join-Path $distDir 'android') -Filter '*.apk' |
        ForEach-Object { Write-Host "  $($_.FullName)" }
}

if ($Target -eq 'all' -or $Target -eq 'windows') {
    Write-Host "  $(Join-Path $distDir 'windows\work_rest_time_balancer')"
}
