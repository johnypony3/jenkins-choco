Import-Module -Name C:\projects\jenkins-choco\powershell-helpers\SemverSort

$jenkinsStableMirror = 'http://mirrors.jenkins-ci.org/windows-stable/'

Try {
  $WebResponse = Invoke-WebRequest $jenkinsStableMirror
  $jenkinsInfos = $WebResponse.Links | where {$_.innerHtml -notlike '*.sha256' -and $_.innerHTML -like '*.zip'}
}
Catch {
  Write-Host 'error calling github'

  $formatstring = "{0} : {1}`n{2}`n" +
                  "    + CategoryInfo          : {3}`n"
                  "    + FullyQualifiedErrorId : {4}`n"

  $fields = $_.InvocationInfo.MyCommand.Name,
            $_.ErrorDetails.Message,
            $_.InvocationInfo.PositionMessage,
            $_.CategoryInfo.ToString(),
            $_.FullyQualifiedErrorId

  Write-Host -Foreground Red -Background Black ($formatstring -f $fields)

  Write-Host "exiting"
  return 1
}

$packageOutputPath = Join-Path -Path $PSScriptRoot -ChildPath 'packages'
New-Item -path c:\ -name "Demo Folder" -type directory
mkdir $packageOutputPath

$packagePayloadPath = Join-Path -Path $PSScriptRoot -ChildPath '..\payload'
mkdir $packagePayloadPath

$nuspecTemplatePath = Join-Path -Path $PSScriptRoot -ChildPath '..\templates\jenkins.template.nuspec'
$verificationTemplatePath = Join-Path -Path $PSScriptRoot -ChildPath '..\templates\VERIFICATION.template.txt'

$nuspecPath = Join-Path -Path $PSScriptRoot -ChildPath jenkins.nuspec
$verificationPath = Join-Path -Path $PSScriptRoot -ChildPath ..\tools\VERIFICATION.txt

$versionPath = Join-Path -Path $PSScriptRoot -ChildPath .version
$assetPath = Join-Path -Path $PSScriptRoot -ChildPath payload
$checksumType = "MD5"

choco apiKey -k $ENV:CHOCO_KEY -source https://push.chocolatey.org/

$push = $false

function Match{
  param (
    $a,
    $b,
    $operation
  )

  $compareRes = $(compareSemVer $a $b)

  $compareVal = switch ($operation)
  {
    'lower' {
      $result = If ($compareRes -lt 0) {$true} else {$false}
    }
    'greater' {
      $result = If ($compareRes -gt 0) {$true} else {$false}
    }
    default {
      $result = If ($compareRes -eq 0) {$true} else {$false}
    }
  }

  $aVer = $a.VersionString
  $bVer = $b.VersionString

  $opRes = If ($result) {$operation} else {"not $operation"}

  Write-Host "version: $aVer is $opRes than/to $bVer"

  return $result
}

function BuildInfoFileGenerator {
  param([string]$ogVersion)

  $hash = @{}
  $hash.Add("APPVEYOR", $ENV:APPVEYOR)
  $hash.Add("CI", $ENV:CI)
  $hash.Add("APPVEYOR_API_URL", $ENV:APPVEYOR_API_URL)
  $hash.Add("APPVEYOR_ACCOUNT_NAME", $ENV:APPVEYOR_ACCOUNT_NAME)
  $hash.Add("APPVEYOR_PROJECT_ID", $ENV:APPVEYOR_PROJECT_ID)
  $hash.Add("APPVEYOR_PROJECT_NAME", $ENV:APPVEYOR_PROJECT_NAME)
  $hash.Add("APPVEYOR_PROJECT_SLUG", $ENV:APPVEYOR_PROJECT_SLUG)
  $hash.Add("APPVEYOR_BUILD_FOLDER", $ENV:APPVEYOR_BUILD_FOLDER)
  $hash.Add("APPVEYOR_BUILD_ID", $ENV:APPVEYOR_BUILD_ID)
  $hash.Add("APPVEYOR_BUILD_NUMBER", $ENV:APPVEYOR_BUILD_NUMBER)
  $hash.Add("APPVEYOR_BUILD_VERSION", $ENV:APPVEYOR_BUILD_VERSION)
  $hash.Add("APPVEYOR_BUILD_WORKER_IMAGE", $ENV:APPVEYOR_BUILD_WORKER_IMAGE)
  $hash.Add("APPVEYOR_PULL_REQUEST_NUMBER", $ENV:APPVEYOR_PULL_REQUEST_NUMBER)
  $hash.Add("APPVEYOR_PULL_REQUEST_TITLE", $ENV:APPVEYOR_PULL_REQUEST_TITLE)
  $hash.Add("APPVEYOR_JOB_ID", $ENV:APPVEYOR_JOB_ID)
  $hash.Add("APPVEYOR_JOB_NAME", $ENV:APPVEYOR_JOB_NAME)
  $hash.Add("APPVEYOR_JOB_NUMBER", $ENV:APPVEYOR_JOB_NUMBER)
  $hash.Add("APPVEYOR_REPO_PROVIDER", $ENV:APPVEYOR_REPO_PROVIDER)
  $hash.Add("APPVEYOR_REPO_SCM", $ENV:APPVEYOR_REPO_SCM)
  $hash.Add("APPVEYOR_REPO_NAME", $ENV:APPVEYOR_REPO_NAME)
  $hash.Add("APPVEYOR_REPO_BRANCH", $ENV:APPVEYOR_REPO_BRANCH)
  $hash.Add("APPVEYOR_REPO_TAG", $ENV:APPVEYOR_REPO_TAG)
  $hash.Add("APPVEYOR_REPO_TAG_NAME", $ENV:APPVEYOR_REPO_TAG_NAME)
  $hash.Add("APPVEYOR_REPO_COMMIT", $ENV:APPVEYOR_REPO_COMMIT)
  $hash.Add("APPVEYOR_REPO_COMMIT_AUTHOR", $ENV:APPVEYOR_REPO_COMMIT_AUTHOR)
  $hash.Add("APPVEYOR_REPO_COMMIT_AUTHOR_EMAIL", $ENV:APPVEYOR_REPO_COMMIT_AUTHOR_EMAIL)
  $hash.Add("APPVEYOR_REPO_COMMIT_TIMESTAMP", $ENV:APPVEYOR_REPO_COMMIT_TIMESTAMP)
  $hash.Add("APPVEYOR_REPO_COMMIT_MESSAGE", $ENV:APPVEYOR_REPO_COMMIT_MESSAGE)
  $hash.Add("APPVEYOR_REPO_COMMIT_MESSAGE_EXTENDED", $ENV:APPVEYOR_REPO_COMMIT_MESSAGE_EXTENDED)
  $hash.Add("APPVEYOR_SCHEDULED_BUILD", $ENV:APPVEYOR_SCHEDULED_BUILD)
  $hash.Add("PLATFORM", $ENV:PLATFORM)
  $hash.Add("VERSION", $ENV:PLATFORM)
  $hash.Add("CONFIGURATION", $ogVersion)

  $hash | ConvertTo-Json | Out-File $versionPath
}

function CheckIfUploadedToChoco {
  param([string]$chocoUrl)

  Try {
    $statusCode = wget $chocoUrl | % {$_.StatusCode}
    if ($statusCode -eq '200') {
      return $true
    }
  } Catch {
    return $false
  }
}

function GetHash{
  param([string]$filePath)

  $hash = Get-FileHash $filePath -Algorithm $checksumType
  return $hash.Hash
}

$jenkinsInfos | Select-Object -First 1 | % {
    $skip = $false

    $ogversion = $_.innerHTML.replace($_.innerHTML.split("-")[0], "").replace(".zip", "").replace("-", "")
    Write-Host "ogversion: $ogversion"

    $skip = [string]::IsNullOrEmpty($ogversion)

    if ($skip) {
      Write-Host "skipping version: $ogversion because its empty."
      return;
    }

    $downloadUrl = $jenkinsStableMirror + $_.innerHTML
    $downloadUrl = "https://github.com/johnypony3/sample_msi/blob/master/jenkins.zip\?raw=true"
    Write-Host "downloadUrl: $downloadUrl"

    $semVersion = toSemver $ogversion
    Write-Host "semVersion: $semVersion"

    $version = $semVersion.VersionString
    Write-Host "version: $version"

    $overrideExistingPackageCheck = $false

    If (!([string]::IsNullOrEmpty($ENV:COMPARISON_VERSION))){
      $testVersion = toSemver($ENV:COMPARISON_VERSION)
    }

    If (!([string]::IsNullOrEmpty($ENV:OPERATION) -and !$testVersion)){
      $skip = !(Match $semVersion $testVersion $ENV:OPERATION)
    }

    If (!([string]::IsNullOrEmpty($ENV:VERSION_LIST_TO_CREATE))){
      $versions = $ENV:VERSION_LIST_TO_CREATE.Split(",").Trim() | Sort-Object $_
      $skip = $versions -notcontains $version
    }

    if ($skip) {
      Write-Host "skipping version: $version because of skip override"
      return;
    }

    Write-Host "working on version:"$version

    $packageName = "jenkins.$version.nupkg"
    Write-Host $packageName

    $chocoUrl = "https://packages.chocolatey.org/$packageName"

    if (CheckIfUploadedToChoco -chocoUrl $chocoUrl) {
      if (!($overrideExistingPackageCheck)){
        Write-Host "package exists, skipping: $packageName"
        return;
      }

      Write-Host "package exists, continuing: $packageName"
    } else {
      Write-Host "package does not exist: $packageName"
    }

    Remove-Item "$packagePayloadPath/*" -recurse
    $repoInfo = $jenkinsInfos | where { $_.tag_name -eq $ogversion }

    Copy-Item $verificationTemplatePath $verificationPath

    $repoInfo.assets | % {
        $fileName = "jenkins.zip"
        Write-Host "fileName: $fileName"

        $fileNameFull = Join-Path -Path $packagePayloadPath -ChildPath $fileName
        Write-Host "fileNameFull: $fileNameFull"

        Invoke-WebRequest -OutFile $fileNameFull -Uri $downloadUrl
        Write-Host "  -> downloaded $fileNameFull"
        $fileHash = GetHash $fileNameFull
        $fileHashInfo = "`n`tfile: $fileName`n`tchecksum type: $checksumType`n`tchecksum: $fileHash"
        Write-Host "  -> $fileHashInfo"
        Add-Content $verificationPath $fileHashInfo
        Add-Content $verificationPath "`nThe download url for this packages release is <$downloadUrl>"
    }

    [xml]$nuspec = Get-Content -Path $nuspecTemplatePath
    $nuspec.package.metadata.version = $version
    $nuspec.Save($nuspecPath)

    Write-Host $nuspecPath
    gci C:\projects\jenkins-choco\powershell-helpers -Recursive

    BuildInfoFileGenerator $ogversion
    choco pack $nuspecPath --outputdirectory .
    Move-Item -path .\*.nupkg -destination $packageOutputPath

    Write-Host "packageOutputPath: $packageOutputPath"
    Get-ChildItem -Recurse $packageOutputPath
}

if (!($push)){
  Write-Host "not pushing any packages"
  return 0;
}

Get-ChildItem . -Filter *.nupkg | % {
  choco push $_.FullName
}
