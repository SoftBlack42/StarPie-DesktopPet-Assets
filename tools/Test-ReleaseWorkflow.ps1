#Requires -Version 7.2
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'PetAssets.psm1') -Force
$repo=Split-Path -Parent $PSScriptRoot
$temp=Join-Path ([IO.Path]::GetTempPath()) ('pet-release-tests-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
$checks=0
function Check([bool]$Condition,[string]$Message) {
    if(-not $Condition){throw "RELEASE TEST FAILED: $Message"}
    $script:checks++;Write-Host " [PASS] $Message"
}
function Reject([scriptblock]$Action,[string]$Pattern,[string]$Message) {
    $failed=$false
    try {& $Action | Out-Null} catch {
        $failed=$true
        Check ($_.Exception.Message -match $Pattern) "$Message (expected reason)"
    }
    Check $failed $Message
}
function Save-Json([string]$Path,$Value) {
    [IO.File]::WriteAllText($Path,((ConvertTo-Json -InputObject $Value -Depth 30)+"`n"),[Text.UTF8Encoding]::new($false))
}
$priorGh=Get-Item Function:\gh -ErrorAction SilentlyContinue
try {
    $root=Join-Path $temp 'repository'
    [void][IO.Directory]::CreateDirectory((Join-Path $root 'pets'))
    Copy-Item -LiteralPath (Join-Path $repo 'schemas') -Destination $root -Recurse
    $source=@(Get-PetAssetSources -Root $repo)[0]
    Copy-Item -LiteralPath $source.FullDirectory -Destination (Join-Path $root 'pets/public') -Recurse
    $infoPath=Join-Path $root 'pets/public/asset-info.json'
    $info=Get-Content -LiteralPath $infoPath -Raw | ConvertFrom-Json
    $info.id='local.fixture.public';$info.name='Fixture | <pack>';$info.version='1.0.0'
    Save-Json $infoPath $info
    [IO.File]::WriteAllText((Join-Path $root 'README.md'),"# Header`n<!-- PET-ASSETS:START -->`nold table`n<!-- PET-ASSETS:END -->`nKeep this footer.`n")
    $empty=[ordered]@{schemaVersion=1;catalog='starpie-desktop-pet-assets';maintainer='SoftBlack42';updatedAtUtc='2026-01-01T00:00:00Z';items=@()}
    $catalogPath=Join-Path $root 'catalog.json'
    Save-Json $catalogPath $empty
    $plan=Get-PetCatalogPlan -Root $root
    Check ($plan.Releases.Count -eq 1 -and $plan.Releases[0].ReleaseTag -ceq 'pet-local.fixture.public-v1.0.0') 'new source automatically creates an independent release plan'
    Check ($plan.Catalog.items[0].name -ceq $info.name -and -not $plan.Catalog.items[0].PSObject.Properties['downloadUrl']) 'metadata comes from asset-info, with no unverified download link'
    $readme=Update-PetReadmeContent -Content (Get-Content -LiteralPath (Join-Path $root 'README.md') -Raw) -Catalog $plan.Catalog
    Check ($readme.Contains('Fixture &#124; &lt;pack&gt;') -and $readme.Contains('pets/public/idle.png') -and $readme.Contains('Keep this footer.')) 'README escapes names, uses idle preview, and preserves outside content'
    Reject {Update-PetReadmeContent -Content 'no markers' -Catalog $plan.Catalog} 'marker pair' 'missing README markers fail instead of overwriting user content'
    $package=@(Export-PetAssets -Root $root -OutputDirectory (Join-Path $temp 'packages'))[0]
    $repeat=@(Export-PetAssets -Root $root -OutputDirectory (Join-Path $temp 'repeat'))[0]
    Check ($package.Sha256 -ceq $repeat.Sha256 -and $package.Size -eq $repeat.Size) 'public package is byte-for-byte reproducible'
    $published=Get-PetCatalogPlan -Root $root -Receipts @($package)
    Save-Json $catalogPath $published.Catalog
    Check ((Get-PetCatalogPlan -Root $root).Releases.Count -eq 0) 'same published version is not repackaged'
    Check ($published.Catalog.items[0].packageSha256 -ceq $package.Sha256 -and $published.Catalog.items[0].downloadUrl.EndsWith($package.AssetName)) 'catalog links and hashes match the actual receipt'
    $stale=$package.PSObject.Copy();$stale.SourceFingerprint='0'*64
    Reject {Get-PetCatalogPlan -Root $root -Receipts @($stale)} 'stale public receipt' 'stale package receipt is rejected'
    $owned=Get-PetCatalogPlan -Root $root
    Check ([DateTimeOffset]$owned.Catalog.updatedAtUtc -eq [DateTimeOffset]$published.Catalog.updatedAtUtc) 'unchanged metadata retains its timestamp, avoiding bot commit churn'
    $sameReadme=Update-PetReadmeContent -Content $readme -Catalog $plan.Catalog
    Check ($sameReadme -ceq $readme) 'README generation is idempotent'
    $withdrawn=Get-Content -LiteralPath $infoPath -Raw | ConvertFrom-Json
    $withdrawn.publishable=$false;Save-Json $infoPath $withdrawn
    $withdrawal=Get-PetCatalogPlan -Root $root
    Check ($withdrawal.Releases.Count -eq 0 -and -not $withdrawal.Catalog.items[0].PSObject.Properties['downloadUrl']) 'withdrawing publication removes the listing without touching historical Releases'
    $withdrawn.publishable=$true;Save-Json $infoPath $withdrawn
    $originalInfo=Get-Content -LiteralPath $infoPath -Raw
    $info.name='changed without bump';Save-Json $infoPath $info
    Reject {Get-PetCatalogPlan -Root $root} 'without a version bump' 'same-version payload edits fail'
    $info.version='1.0.1';Save-Json $infoPath $info
    Check ((Get-PetCatalogPlan -Root $root).Releases[0].Version -ceq '1.0.1') 'version bump selects only the updated pack'
    $info.version='0.9.0';Save-Json $infoPath $info
    Reject {Get-PetCatalogPlan -Root $root} 'downgrade' 'version downgrade is refused'
    [IO.File]::WriteAllText($infoPath,$originalInfo)
    $legacy=$published.Catalog | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $legacy.items[0].releaseTag='pets-2026.10.10.1'
    $legacy.items[0].downloadUrl='https://github.com/Star-Pie/StarPie-DesktopPet-Assets/releases/download/pets-2026.10.10.1/'+$package.AssetName
    $legacy.items[0].PSObject.Properties.Remove('sourceFingerprint')
    Save-Json $catalogPath $legacy
    $migration=Get-PetCatalogPlan -Root $root
    Check ($migration.Releases.Count -eq 1 -and $migration.Catalog.items[0].releaseTag -ceq 'pets-2026.10.10.1') 'legacy links remain valid until independent publication succeeds'
    Copy-Item -LiteralPath (Join-Path $root 'pets/public') -Destination (Join-Path $root 'pets/private') -Recurse
    $privatePath=Join-Path $root 'pets/private/asset-info.json'
    $private=Get-Content -LiteralPath $privatePath -Raw | ConvertFrom-Json
    $private.id='local.fixture.private';$private.name='PRIVATE MUST NOT APPEAR';$private.publishable=$false
    Save-Json $privatePath $private
    $mixed=Get-PetCatalogPlan -Root $root
    $readme=Update-PetReadmeContent -Content (Get-Content -LiteralPath (Join-Path $root 'README.md') -Raw) -Catalog $mixed.Catalog
    Check ($mixed.Releases.Count -eq 1 -and $mixed.Catalog.items.Count -eq 2 -and -not $readme.Contains($private.name)) 'private assets are validated but never released or shown'
    $denied=Join-Path $temp 'denied'
    Reject {Export-PetAssets -Root $root -OutputDirectory $denied} 'Refusing public export' 'public export refuses mixed private selections'
    Check (-not(Test-Path -LiteralPath $denied)) 'authorization refusal occurs before any output directory is created'
    $private.id=$info.id;Save-Json $privatePath $private
    Reject {Get-PetCatalogPlan -Root $root} 'Duplicate asset id' 'duplicate source IDs are rejected'
    $private.id='local.fixture.private';Save-Json $privatePath $private
    Save-Json $catalogPath $empty
    $global:PetReleaseMock=[pscustomobject]@{Calls=[Collections.Generic.List[object]]::new();Releases=@{};ApiError=$false;Orphan=$false}
    function global:gh {
        $arguments=@($args)
        $global:LASTEXITCODE=0
        $state=$global:PetReleaseMock
        $state.Calls.Add($arguments)
        if($arguments[0] -eq 'api') {
            if($state.ApiError){$global:LASTEXITCODE=1;return 'gh: rate limited (HTTP 403)'}
            if($arguments[1] -match '/releases/tags/(.+)$') {
                $tag=[uri]::UnescapeDataString($Matches[1])
                if($state.Releases.ContainsKey($tag)){return ($state.Releases[$tag] | ConvertTo-Json -Depth 20)}
            } elseif($arguments[1] -match '/git/ref/tags/' -and $state.Orphan){return '{"object":{"sha":"orphan"}}'}
            $global:LASTEXITCODE=1;return 'gh: Not Found (HTTP 404)'
        }
        $tag=$arguments[2]
        if($arguments[0] -ne 'release'){throw 'Unexpected mock command'}
        if($arguments[1] -eq 'create') {
            if($state.Releases.ContainsKey($tag)){throw 'Mock refusing existing release'}
            $state.Releases[$tag]=[pscustomobject]@{draft=$true;prerelease=$false;tag_name=$tag;assets=@()}
        }
        if($arguments[1] -in @('create','upload')) {
            foreach($arg in $arguments) {
                if((Test-Path -LiteralPath $arg -PathType Leaf) -and ([IO.Path]::GetFileName($arg) -eq 'SHA256SUMS.txt' -or $arg.EndsWith('.zip'))) {
                    $file=Get-Item -LiteralPath $arg
                    $state.Releases[$tag].assets+= [pscustomobject]@{name=$file.Name;size=$file.Length;digest='sha256:'+(Get-FileHash -LiteralPath $arg -Algorithm SHA256).Hash.ToLowerInvariant();sourcePath=$file.FullName}
                }
            }
            return ''
        }
        if($arguments[1] -eq 'edit'){$state.Releases[$tag].draft=$false;return ''}
        if($arguments[1] -eq 'download') {
            $name=$arguments[[array]::IndexOf($arguments,'--pattern')+1]
            $directory=$arguments[[array]::IndexOf($arguments,'--dir')+1]
            $asset=@($state.Releases[$tag].assets | Where-Object name -CEQ $name)[0]
            Copy-Item -LiteralPath $asset.sourcePath -Destination (Join-Path $directory $name)
            return ''
        }
        throw 'Unexpected mock release command'
    }
    $publish=Join-Path $PSScriptRoot 'Publish-PetAssets.ps1'
    $dry=Join-Path $temp 'dry-run'
    $null=& $publish -Root $root -OutputDirectory $dry -DryRun 6>&1
    Check ($global:PetReleaseMock.Calls.Count -eq 0 -and $global:PetReleaseMock.Releases.Count -eq 0) 'dry-run makes zero GitHub calls'
    Check (Test-Path -LiteralPath (Join-Path $dry 'catalog.json')) 'dry-run produces proposed catalog and README'
    Check ((Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json).items.Count -eq 0) 'dry-run never writes repository metadata'
    $output=Join-Path $temp 'publication'
    $null=& $publish -Root $root -OutputDirectory $output -TargetCommit ('a'*40) 6>&1
    $state=$global:PetReleaseMock
    $tag='pet-local.fixture.public-v1.0.0'
    Check ($state.Releases.Count -eq 1 -and -not $state.Releases[$tag].draft) 'each public pack gets its own public Release'
    Check (($state.Releases[$tag].assets.name | Sort-Object) -join ',' -ceq 'SHA256SUMS.txt,StarPie-PetAsset-local.fixture.public-1.0.0.zip') 'Release uploads ZIP and checksum only, never catalog or README'
    $staged=Get-Content -LiteralPath (Join-Path $output 'catalog.json') -Raw | ConvertFrom-Json
    $publicItem=@($staged.items | Where-Object id -CEQ 'local.fixture.public')[0]
    Check ($publicItem.releaseTag -ceq $tag -and $publicItem.packageSha256 -ceq $package.Sha256) 'published metadata matches verified package'
    $state.Calls.Clear()
    $null=& $publish -Root $root -OutputDirectory (Join-Path $temp 'retry') -TargetCommit ('a'*40) 6>&1
    Check (@($state.Calls | Where-Object {$_[0] -eq 'release' -and $_[1] -in @('create','upload','edit')}).Count -eq 0) 'retry after lost metadata push reuses matching published assets without remote writes'
    $state.Releases[$tag].draft=$true
    $state.Releases[$tag].assets=@($state.Releases[$tag].assets | Where-Object name -Like '*.zip')
    $state.Calls.Clear()
    $null=& $publish -Root $root -OutputDirectory (Join-Path $temp 'resume-draft') -TargetCommit ('a'*40) 6>&1
    Check (-not $state.Releases[$tag].draft -and $state.Releases[$tag].assets.Count -eq 2) 'interrupted draft resumes missing checksum upload and publishes'
    $state.Releases[$tag].assets[0].digest=$null
    $null=& $publish -Root $root -OutputDirectory (Join-Path $temp 'download-verify') -TargetCommit ('a'*40) 6>&1
    Check (@($state.Calls | Where-Object {$_[0] -eq 'release' -and $_[1] -eq 'download'}).Count -gt 0) 'missing GitHub digest falls back to downloading and hashing the asset'
    $state.Releases[$tag].assets[0].digest='sha256:'+('0'*64)
    $state.Calls.Clear()
    Reject {& $publish -Root $root -OutputDirectory (Join-Path $temp 'collision') -TargetCommit ('a'*40) 6>&1} 'checksum mismatch' 'existing same-tag different bytes fail closed'
    Check (@($state.Calls | Where-Object {$_[0] -eq 'release' -and $_[1] -in @('create','upload','edit')}).Count -eq 0) 'collision does not overwrite any remote asset'
    $state.ApiError=$true;$state.Calls.Clear()
    Reject {& $publish -Root $root -OutputDirectory (Join-Path $temp 'api-error') -TargetCommit ('a'*40) 6>&1} 'HTTP 403' 'API permission or rate-limit errors are not treated as missing Releases'
    $state.ApiError=$false;$state.Releases.Clear();$state.Orphan=$true
    Reject {& $publish -Root $root -OutputDirectory (Join-Path $temp 'orphan') -TargetCommit ('a'*40) 6>&1} 'Tag exists without' 'orphaned tags are never silently reused'
    Check ((Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json).items.Count -eq 0) 'publication scripts only stage metadata and never commit or push themselves'
    $emptyRoot=Join-Path $temp 'empty-repository'
    [void][IO.Directory]::CreateDirectory($emptyRoot)
    Copy-Item -LiteralPath (Join-Path $repo 'schemas') -Destination $emptyRoot -Recurse
    Save-Json (Join-Path $emptyRoot 'catalog.json') $empty
    $emptyPlan=Get-PetCatalogPlan -Root $emptyRoot
    Check ($emptyPlan.Releases.Count -eq 0 -and $emptyPlan.Catalog.items.Count -eq 0) 'empty repositories generate a valid empty catalog without fake releases'
    Reject {Get-PetCatalogPlan -Root $emptyRoot -Receipts @($package)} 'does not correspond' 'unknown receipts cannot introduce phantom assets'
    Write-Host "PASS: $checks release/catalog/README assertions; mocked GitHub only."
} finally {
    if($priorGh){Set-Item Function:\global:gh $priorGh.ScriptBlock}else{Remove-Item Function:\gh -ErrorAction SilentlyContinue}
    Remove-Variable PetReleaseMock -Scope Global -ErrorAction SilentlyContinue
    $resolved=[IO.Path]::GetFullPath($temp)
    $parent=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar)
    if([IO.Path]::GetDirectoryName($resolved) -cne $parent -or -not [IO.Path]::GetFileName($resolved).StartsWith('pet-release-tests-')){throw 'Unexpected test cleanup path'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
