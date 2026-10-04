param([ValidateSet('win-x64','win-arm64')][string]$Runtime = "win-$([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant())")
$ErrorActionPreference = 'Stop'
$destination = Join-Path $PSScriptRoot '../.build/windows'
dotnet publish (Join-Path $PSScriptRoot 'Blindly4.csproj') -c Release -r $Runtime --self-contained true -o $destination
if ($LASTEXITCODE -ne 0) { throw 'Blindly4 build failed' }
Write-Host "Blindly4: $destination/blindly4.exe"
