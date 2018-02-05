
$ErrorActionPreference = 'Stop';

$packageName = 'jenkins'
$zipFile = "jenkins.$ChocolateyPackageVersion.zip"
$toolsDir = "$(Split-Path -parent $MyInvocation.MyCommand.Definition)"

Get-ChocolateyUnzip -FileFullPath $zipFile -Destination $toolsDir -PackageName $packageName
