$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'Flutter no está en el PATH. Instala Flutter y abre una terminal nueva.'
}
function Invoke-Flutter {
    param([string[]]$Arguments)
    & flutter @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Flutter ha fallado con código $LASTEXITCODE." }
}
# ARMARIO_SIGNING_KEY debe apuntar a la clave externa conservada para actualizar.
if (-not $env:ARMARIO_SIGNING_KEY) {
    throw 'Configura ARMARIO_SIGNING_KEY con la clave privada conservada antes de compilar.'
}
Invoke-Flutter -Arguments @('pub', 'get')
Invoke-Flutter -Arguments @('analyze')
Invoke-Flutter -Arguments @('test')
Invoke-Flutter -Arguments @('build', 'apk', '--release', '--target-platform', 'android-arm64')
Write-Host 'APK generado: build/app/outputs/flutter-apk/app-release.apk'
