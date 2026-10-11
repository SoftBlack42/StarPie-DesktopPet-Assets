#Requires -Version 7.2
[CmdletBinding()]
param(
    [string]$Root=(Split-Path -Parent $PSScriptRoot),
    [string]$OutputDirectory='dist/release',
    [ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')][string]$Repository='Star-Pie/StarPie-DesktopPet-Assets',
    [string]$TargetCommit=$env:GITHUB_SHA,
    [switch]$DryRun
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'PetAssets.psm1') -Force
if(-not $DryRun -and $TargetCommit -cnotmatch '^[a-f0-9]{40}$'){throw 'Publication requires an exact target commit SHA'}
$out=if([IO.Path]::IsPathRooted($OutputDirectory)){$OutputDirectory}else{Join-Path $Root $OutputDirectory}
[void][IO.Directory]::CreateDirectory($out)
& (Join-Path $PSScriptRoot 'Update-PetCatalog.ps1') -Root $Root -OutputDirectory (Join-Path $out 'validation') -Repository $Repository
& (Join-Path $PSScriptRoot 'Test-PetAssets.ps1') -Root $Root -CatalogPath (Join-Path $out 'validation/catalog.json')
$plan=Get-PetCatalogPlan -Root $Root -Repository $Repository
$receipts=@()
function Invoke-GitHub([string[]]$Arguments,[switch]$AllowNotFound) {
    $PSNativeCommandUseErrorActionPreference=$false
    $result=@(& gh @Arguments 2>&1)
    $code=$LASTEXITCODE
    $text=($result | ForEach-Object {"$_"}) -join "`n"
    if($code -ne 0) {
        if($AllowNotFound -and $text -match '\(HTTP 404\)'){return $null}
        throw "GitHub command failed (exit $code): $text"
    }
    return $text
}
function Get-Release([string]$Tag) {
    $json=Invoke-GitHub -Arguments @('api',"repos/$Repository/releases/tags/$([uri]::EscapeDataString($Tag))") -AllowNotFound
    if($json){return ($json | ConvertFrom-Json)}
    return $null
}
function Assert-ReleaseAssets($Release,[object[]]$Files,[string]$Tag) {
    foreach($file in $Files) {
        $asset=@($Release.assets | Where-Object name -CEQ $file.Name)
        if($asset.Count -ne 1 -or $asset[0].size -ne $file.Size){throw "Published asset missing or size mismatch: $Tag/$($file.Name)"}
        if($asset[0].PSObject.Properties['digest'] -and $asset[0].digest) {
            if($asset[0].digest -cne "sha256:$($file.Sha256)"){throw "Published asset checksum mismatch: $Tag/$($file.Name)"}
        } else {
            $verify=Join-Path $out ('verify-'+[guid]::NewGuid().ToString('N'))
            [void][IO.Directory]::CreateDirectory($verify)
            $null=Invoke-GitHub -Arguments @('release','download',$Tag,'--repo',$Repository,'--pattern',$file.Name,'--dir',$verify)
            $path=Join-Path $verify $file.Name
            if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $file.Sha256){throw "Downloaded asset checksum mismatch: $Tag/$($file.Name)"}
        }
    }
}
foreach($source in $plan.Releases) {
    $directory=Join-Path $out ('packages/'+$source.ReleaseTag)
    $receipt=@(Export-PetAssets -Root $Root -OutputDirectory $directory -PackId $source.Id)[0]
    $sumPath=Join-Path $directory 'SHA256SUMS.txt'
    [IO.File]::WriteAllText($sumPath,"$($receipt.Sha256)  $($receipt.AssetName)`n",[Text.Encoding]::ASCII)
    $notesPath=Join-Path $directory 'release-notes.md'
    $notes="# $($source.Info.name) v$($source.Version)`n`nID: ``$($source.Id)```n`n解压 ZIP 后，在桌宠插件的「管理桌宠 → 导入本地文件夹」选择解压目录。包包含 12 张 PNG、asset-info.json 和 README.md，不包含主程序、插件或用户数据。`n`nSHA-256: ``$($receipt.Sha256)```n"
    [IO.File]::WriteAllText($notesPath,$notes,[Text.UTF8Encoding]::new($false))
    $files=@([pscustomobject]@{Name=$receipt.AssetName;Path=$receipt.Path;Size=$receipt.Size;Sha256=$receipt.Sha256},[pscustomobject]@{Name='SHA256SUMS.txt';Path=$sumPath;Size=(Get-Item -LiteralPath $sumPath).Length;Sha256=(Get-FileHash -LiteralPath $sumPath -Algorithm SHA256).Hash.ToLowerInvariant()})
    if(-not $DryRun) {
        $release=Get-Release -Tag $source.ReleaseTag
        if(-not $release) {
            $tag=Invoke-GitHub -Arguments @('api',"repos/$Repository/git/ref/tags/$([uri]::EscapeDataString($source.ReleaseTag))") -AllowNotFound
            if($tag){throw "Tag exists without a Release; refusing overwrite: $($source.ReleaseTag)"}
            $null=Invoke-GitHub -Arguments @('release','create',$source.ReleaseTag,'--repo',$Repository,'--target',$TargetCommit,'--title',"$($source.Info.name) v$($source.Version)",'--notes-file',$notesPath,'--draft',$receipt.Path,$sumPath)
            $release=Get-Release -Tag $source.ReleaseTag
        } elseif($release.draft) {
            # Resume an interrupted draft only when every existing expected asset matches.
            $existing=@($files | Where-Object {$name=$_.Name; @($release.assets | Where-Object name -CEQ $name).Count -gt 0})
            Assert-ReleaseAssets -Release $release -Files $existing -Tag $source.ReleaseTag
            $missing=@($files | Where-Object {$name=$_.Name; @($release.assets | Where-Object name -CEQ $name).Count -eq 0})
            if($missing.Count){$null=Invoke-GitHub -Arguments (@('release','upload',$source.ReleaseTag,'--repo',$Repository)+@($missing | ForEach-Object Path))}
            $release=Get-Release -Tag $source.ReleaseTag
        }
        if(-not $release -or $release.prerelease){throw "Missing or unexpected prerelease: $($source.ReleaseTag)"}
        Assert-ReleaseAssets -Release $release -Files $files -Tag $source.ReleaseTag
        if($release.draft){$null=Invoke-GitHub -Arguments @('release','edit',$source.ReleaseTag,'--repo',$Repository,'--draft=false')}
        $release=Get-Release -Tag $source.ReleaseTag
        if(-not $release -or $release.draft -or $release.prerelease){throw "Release is not public: $($source.ReleaseTag)"}
    }
    $receipts+=$receipt
    Write-Host "$(if($DryRun){'DRY RUN'}else{'PUBLISHED'}): $($source.ReleaseTag)"
}
$receiptsPath=Join-Path $out 'receipts.json'
[IO.File]::WriteAllText($receiptsPath,((ConvertTo-Json -InputObject @($receipts) -Depth 12)+"`n"),[Text.UTF8Encoding]::new($false))
& (Join-Path $PSScriptRoot 'Update-PetCatalog.ps1') -Root $Root -OutputDirectory $out -Repository $Repository -ReceiptsPath $receiptsPath
Write-Host 'Generated repository metadata only; catalog.json and README.md are not Release assets.'
