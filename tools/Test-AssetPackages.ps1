[CmdletBinding()]
param(
    [string]$OutputDirectory = 'dist',
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [switch]$AllowPrivateDraft
)

$ErrorActionPreference = 'Stop'
$repoRoot = $Root

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
Import-Module (Join-Path $PSScriptRoot 'PetAssets.psm1') -Force

$passCount = 0
function Assert-Pkg([bool]$cond, [string]$msg) {
    if (-not $cond) { throw "PACKAGE VALIDATION FAILED: $msg" }
    $script:passCount++
    Write-Host " [PASS] $msg"
}

Write-Host "============================================================"
Write-Host " StarPie Desktop Pet Asset Package Gate (Test-AssetPackages)"
Write-Host "============================================================"

$catalogPath = Join-Path $repoRoot 'catalog.json'
$catalog = [pscustomobject]@{items=@(Get-PetAssetSources -Root $repoRoot | ForEach-Object {[pscustomobject]@{id=$_.Id;version=$_.Version;directory=$_.Directory;publishable=$_.Info.publishable}})}

Write-Host '--- Actual exporter refusal before writing ---'
$requiresPrivate=@($catalog.items | Where-Object {$_.publishable -ne $true}).Count -gt 0
if($requiresPrivate){
 $refusalOutput=Join-Path ([IO.Path]::GetTempPath()) ('pet-denied-'+[guid]::NewGuid().ToString('N'))
 $denied=$false
 try {Export-PetAssets -Root $repoRoot -OutputDirectory $refusalOutput | Out-Null} catch {$denied=$true;Assert-Pkg ($_.Exception.Message -match 'Refusing public export') 'Actual exporter rejects private public packaging'}
 Assert-Pkg $denied 'Public packaging refused by actual exporter'
 Assert-Pkg (-not(Test-Path -LiteralPath $refusalOutput)) 'Refusal creates no files or directory'
}else{Assert-Pkg $true 'Catalog contains only confirmed public selections'}
if(-not $AllowPrivateDraft){throw 'Private package tests require explicit -AllowPrivateDraft'}

Write-Host "--- 2. Deterministic Private Draft Export Gate ---"
$resolvedOutputDir = if ([System.IO.Path]::IsPathRooted($OutputDirectory)) { $OutputDirectory } else { Join-Path $repoRoot $OutputDirectory }
New-Item -ItemType Directory -Path $resolvedOutputDir -Force | Out-Null

$tempVerifyDir = Join-Path ([System.IO.Path]::GetTempPath()) ('pet-zip-verify-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempVerifyDir -Force | Out-Null

try {
    $firstReceipts=@(Export-PetAssets -Root $repoRoot -OutputDirectory $resolvedOutputDir -AllowPrivateDraft)
    $repeatReceipts=@(Export-PetAssets -Root $repoRoot -OutputDirectory $tempVerifyDir -AllowPrivateDraft)
    foreach ($item in $catalog.items) {
        $packDir = Join-Path $repoRoot $item.directory
        $zipName = "StarPie-PetAsset-$($item.id)-PRIVATE_DRAFT-$($item.version).zip"
        $destZip = Join-Path $resolvedOutputDir $zipName

        # Package 1st time
        # First archive produced by actual exporter above
        Assert-Pkg (Test-Path -LiteralPath $destZip) "$($item.id): Private draft zip created"
        $sha1 = (Get-FileHash -LiteralPath $destZip -Algorithm SHA256).Hash.ToLowerInvariant()
        $size1 = (Get-Item -LiteralPath $destZip).Length

        # Package 2nd time to verify deterministic byte-for-byte reproducibility
        $repeatZip = Join-Path $tempVerifyDir $zipName
        # Repeat archive produced by actual exporter above
        $sha2 = (Get-FileHash -LiteralPath $repeatZip -Algorithm SHA256).Hash.ToLowerInvariant()
        Assert-Pkg ($sha1 -eq $sha2) "$($item.id): Deterministic zip hash matches exactly across repeat runs ($sha1)"

        # Verify zip contents isolation
        $extractDir = Join-Path $tempVerifyDir ("extracted-" + $item.id)
        [System.IO.Compression.ZipFile]::ExtractToDirectory($destZip, $extractDir)
        $extractedFiles = Get-ChildItem -LiteralPath $extractDir -Recurse -File

        Assert-Pkg ($extractedFiles.Count -eq 14) "$($item.id): Exactly 14 files inside private draft zip (12 PNGs + asset-info + README)"
        Assert-Pkg (Test-Path -LiteralPath (Join-Path $extractDir 'README.md')) "$($item.id): README.md included in private draft zip"
        Assert-Pkg (Test-Path -LiteralPath (Join-Path $extractDir 'asset-info.json')) "$($item.id): asset-info.json included in private draft zip"

        $hasDll = @($extractedFiles | Where-Object { $_.Extension -eq '.dll' }).Count -gt 0
        Assert-Pkg (-not $hasDll) "$($item.id): No DLLs present in asset zip"
        $hasPdb = @($extractedFiles | Where-Object { $_.Extension -eq '.pdb' }).Count -gt 0
        Assert-Pkg (-not $hasPdb) "$($item.id): No PDBs present in asset zip"

        # Verify 12 frame hashes match source files
        $pngs = @($extractedFiles | Where-Object { $_.Extension -eq '.png' })
        Assert-Pkg ($pngs.Count -eq 12) "$($item.id): Exactly 12 PNG frames present"
        foreach ($png in $pngs) {
            $srcPng = Join-Path $packDir $png.Name
            $srcHash = (Get-FileHash -LiteralPath $srcPng -Algorithm SHA256).Hash.ToLowerInvariant()
            $zipHash = (Get-FileHash -LiteralPath $png.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            Assert-Pkg ($srcHash -eq $zipHash) "$($item.id)/$($png.Name): Frame hash in zip matches source byte-for-byte"
        }

        Write-Host "Draft package ready: $zipName [SHA256: $sha1, Size: $size1 bytes]"
    }

    Write-Host '--- 3. Deterministic Public Packages ---'
    foreach($item in @($catalog.items | Where-Object publishable -EQ $true)) {
        $first=@(Export-PetAssets -Root $repoRoot -PackId $item.id -OutputDirectory (Join-Path $resolvedOutputDir 'public'))[0]
        $second=@(Export-PetAssets -Root $repoRoot -PackId $item.id -OutputDirectory (Join-Path $tempVerifyDir 'public'))[0]
        Assert-Pkg (-not $first.PrivateDraft -and $first.AssetName -ceq "StarPie-PetAsset-$($item.id)-$($item.version).zip") 'public name has no draft marker'
        Assert-Pkg ($first.Sha256 -ceq $second.Sha256 -and $first.Size -eq $second.Size) 'public package reproducibility'
        Assert-Pkg ($first.Sha256 -ceq (Get-FileHash -LiteralPath $first.Path -Algorithm SHA256).Hash.ToLowerInvariant()) 'public receipt checksum agrees'
        $zip=[IO.Compression.ZipFile]::OpenRead($first.Path)
        try {
            Assert-Pkg ($zip.Entries.Count -eq 14) 'public package contains exactly 14 files'
            Assert-Pkg (@($zip.Entries | Where-Object FullName -Like '*.png').Count -eq 12) 'public package contains 12 PNG frames'
            foreach($entry in $zip.Entries) {
                Assert-Pkg ($entry.FullName -notmatch '[/\\]' -and $entry.FullName -match '^(idle|blink|react|drag|point_[A-Z]{1,2})\.png$|^(asset-info\.json|README\.md)$') 'public package has only root whitelisted files'
            }
        } finally {$zip.Dispose()}
    }
    Write-Host "------------------------------------------------------------"
    Write-Host "PASS: $passCount asset package assertions verified successfully!"
}
finally {
    $resolvedTemp=[IO.Path]::GetFullPath($tempVerifyDir)
    if([IO.Path]::GetDirectoryName($resolvedTemp) -ne [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar) -or -not [IO.Path]::GetFileName($resolvedTemp).StartsWith('pet-zip-verify-')){throw 'Unexpected verification temp path'}
    if (Test-Path -LiteralPath $tempVerifyDir) {
        Remove-Item -LiteralPath $tempVerifyDir -Recurse -Force
    }
}
