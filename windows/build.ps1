$ErrorActionPreference = "Stop"

$projectDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$repositoryDirectory = Split-Path -Parent $projectDirectory
$compiler = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path -LiteralPath $compiler)) {
    $compiler = "C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe"
}
if (-not (Test-Path -LiteralPath $compiler)) {
    throw "The built-in Windows C# compiler was not found."
}

$distributionDirectory = Join-Path $projectDirectory "dist"
$distributionAssets = Join-Path $distributionDirectory "assets"
New-Item -ItemType Directory -Force -Path $distributionDirectory, $distributionAssets | Out-Null
Copy-Item -LiteralPath (Join-Path $repositoryDirectory "assets\messi.png") -Destination $distributionAssets -Force
Copy-Item -LiteralPath (Join-Path $repositoryDirectory "assets\enzo.png") -Destination $distributionAssets -Force
Copy-Item -LiteralPath (Join-Path $repositoryDirectory "assets\romero.png") -Destination $distributionAssets -Force
Copy-Item -LiteralPath (Join-Path $repositoryDirectory "assets\lisandro.png") -Destination $distributionAssets -Force
Copy-Item -LiteralPath (Join-Path $repositoryDirectory "assets\paredes.png") -Destination $distributionAssets -Force

& $compiler `
    /nologo `
    /target:winexe `
    /optimize+ `
    /platform:anycpu `
    /codepage:65001 `
    "/out:$distributionDirectory\ArgentinaFivePets.exe" `
    /reference:System.dll `
    /reference:System.Core.dll `
    /reference:System.Drawing.dll `
    /reference:System.Windows.Forms.dll `
    (Join-Path $projectDirectory "FivePetOverlay.cs")

if ($LASTEXITCODE -ne 0) {
    throw "Compilation failed with exit code $LASTEXITCODE."
}

Write-Output (Join-Path $distributionDirectory "ArgentinaFivePets.exe")
