
$ErrorActionPreference = 'Stop';

$packageName = 'jenkins'

$fileName = "jenkins.zip"

$toolsDir = "$(Split-Path -parent $MyInvocation.MyCommand.Definition)"
$zipFilePath = "$toolsDir\..\payload\$fileName.zip"
$msiPath = "$toolsDir\..\payload\$fileName.msi"

Write-Host "toolsDir: $toolsDir"
Write-Host "zipFilePath: $zipFilePath"
Write-Host "msiPath: $msiPath"

Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory($zipFilePath, $msiPath)

$packageArgs = @{
  packageName   = $packageName
  fileType      = 'msi'
  file           = $msiPath
  silentArgs    = "/qn /norestart /l*v `"$($env:TEMP)\$($packageName).$($env:chocolateyPackageVersion).MsiInstall.log`"" # ALLUSERS=1 DISABLEDESKTOPSHORTCUT=1 ADDDESKTOPICON=0 ADDSTARTMENU=0
  validExitCodes= @(0, 3010, 1641)
}

Write-Host "packageArgs: ($packageArgs | Out-string)"

Install-ChocolateyInstallPackage @packageArgs
