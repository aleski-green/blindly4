param(
    [ValidateSet('win-x64','win-arm64')]
    [string]$Runtime = "win-$([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant())",
    [ValidateSet('msvc','gnullvm')]
    [string]$Toolchain = 'msvc'
)
$ErrorActionPreference = 'Stop'
$architecture = if ($Runtime -eq 'win-arm64') { 'aarch64' } else { 'x86_64' }
$target = "$architecture-pc-windows-$Toolchain"
$repo = Split-Path $PSScriptRoot -Parent
$build = Join-Path $repo '.build/rust'
$destination = Join-Path $PSScriptRoot '../.build/windows'
Push-Location $repo
try {
    cargo build --release --manifest-path (Join-Path $PSScriptRoot 'Cargo.toml') --target $target --target-dir $build
    if ($LASTEXITCODE -ne 0) { throw 'Blindly4 build failed' }
} finally {
    Pop-Location
}
New-Item -ItemType Directory -Path $destination -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $build "$target/release/blindly4.exe") -Destination $destination -Force
Copy-Item -LiteralPath (Join-Path $repo 'license') -Destination $destination -Recurse -Force
Copy-Item -LiteralPath (Join-Path $repo 'README.md') -Destination (Join-Path $destination 'README.md') -Force
Write-Host "Blindly4: $destination/blindly4.exe"
