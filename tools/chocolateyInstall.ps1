
$ErrorActionPreference = 'Stop';

$packageName = 'jenkins'
$zipFile = "jenkins.zip"
$toolsDir = "$(Split-Path -parent $MyInvocation.MyCommand.Definition)"

Expand-Archive .\payload\jenkins.zip -DestinationPath .

$packageArgs = @{
  packageName   = $packageName
  unzipLocation = $toolsDir
  fileType      = 'msi'
  url           = $msiPath
  softwareName  = 'jenkins*' #part or all of the Display Name as you see it in Programs and Features. It should be enough to be unique
  silentArgs    = "/qn /norestart /l*v `"$($env:TEMP)\$($packageName).$($env:chocolateyPackageVersion).MsiInstall.log`"" # ALLUSERS=1 DISABLEDESKTOPSHORTCUT=1 ADDDESKTOPICON=0 ADDSTARTMENU=0
  validExitCodes= @(0, 3010, 1641)
}

Install-ChocolateyPackage @packageArgs # https://chocolatey.org/docs/helpers-install-chocolatey-package
