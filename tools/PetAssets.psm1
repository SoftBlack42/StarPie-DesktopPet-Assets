Set-StrictMode -Version Latest
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
function Resolve-PetDirectory {
    param([string]$Root,[string]$Relative)
    if([IO.Path]::IsPathRooted($Relative) -or $Relative.Contains(':') -or $Relative -match '(^|[\\/])\.\.([\\/]|$)'){throw 'Pet directory must stay inside repository'}
    $full=[IO.Path]::GetFullPath((Join-Path $Root $Relative));$prefix=[IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
    if(-not $full.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Pet directory escapes repository'}
    for($cursor=$full;$cursor;$cursor=[IO.Path]::GetDirectoryName($cursor)){if((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Reparse pet directory refused'}}
    return $full
}
function New-DeterministicPetZip {
    param(
        [string]$SourceDirectory,
        [string]$DestinationZipPath
    )

    $parent = Split-Path -Parent $DestinationZipPath
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $fixedTimestamp = [DateTime]::new(1980, 1, 1, 0, 0, 0, [DateTimeKind]::Unspecified)
    $allowedNames = @(
        'idle.png', 'blink.png', 'react.png', 'drag.png',
        'point_E.png', 'point_SE.png', 'point_S.png', 'point_SW.png',
        'point_W.png', 'point_NW.png', 'point_N.png', 'point_NE.png',
        'asset-info.json', 'README.md'
    )

    $files = Get-ChildItem -LiteralPath $SourceDirectory -File | Where-Object { $allowedNames -contains $_.Name } | Sort-Object Name

    $archiveStream = [System.IO.File]::Open($DestinationZipPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    try {
        $archive = New-Object System.IO.Compression.ZipArchive($archiveStream, [System.IO.Compression.ZipArchiveMode]::Create, $false)
        try {
            foreach ($file in $files) {
                $entry = $archive.CreateEntry($file.Name, [System.IO.Compression.CompressionLevel]::Optimal)
                $entry.LastWriteTime = $fixedTimestamp

                $entryStream = $entry.Open()
                try {
                    $inputStream = [System.IO.File]::OpenRead($file.FullName)
                    try {
                        $inputStream.CopyTo($entryStream)
                    }
                    finally {
                        $inputStream.Dispose()
                    }
                }
                finally {
                    $entryStream.Dispose()
                }
            }
        }
        finally {
            $archive.Dispose()
        }
    }
    finally {
        $archiveStream.Dispose()
    }
}


function Get-PetAssetSources {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root)

    $names=@('idle.png','blink.png','react.png','drag.png','point_E.png','point_SE.png','point_S.png','point_SW.png','point_W.png','point_NW.png','point_N.png','point_NE.png','asset-info.json','README.md')
    $pets=Join-Path $Root 'pets'
    if(-not(Test-Path -LiteralPath $pets)){return}
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($folder in @(Get-ChildItem -LiteralPath $pets -Directory -Force | Sort-Object Name)) {
        $relative='pets/'+$folder.Name
        $directory=Resolve-PetDirectory -Root $Root -Relative $relative
        $infoFile=Join-Path $directory 'asset-info.json'
        if(-not(Test-Path -LiteralPath $infoFile -PathType Leaf) -or ((Get-Item -LiteralPath $infoFile -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -or (Get-Item -LiteralPath $infoFile).Length -gt 1MB){throw "Missing, oversized or reparse metadata: $relative"}
        $text=Get-Content -LiteralPath $infoFile -Raw -Encoding utf8
        if(-not(Test-Json -Json $text -SchemaFile (Join-Path $Root 'schemas\asset-info.schema.json'))){throw "Invalid asset metadata: $relative"}
        $info=$text | ConvertFrom-Json
        if($info.id -cnotmatch '^[a-z0-9][a-z0-9._-]*$' -or $info.version -notmatch '^\d+\.\d+\.\d+$'){throw "Unsafe asset id/version: $relative"}
        if(-not $seen.Add($info.id)){throw "Duplicate asset id: $($info.id)"}
        $digest=[Security.Cryptography.IncrementalHash]::CreateHash([Security.Cryptography.HashAlgorithmName]::SHA256)
        try {
            foreach($name in @($names | Sort-Object)) {
                $file=Join-Path $directory $name
                if(-not(Test-Path -LiteralPath $file -PathType Leaf) -or ((Get-Item -LiteralPath $file -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw "Missing or reparse asset file: $relative/$name"}
                $hash=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
                $digest.AppendData([Text.Encoding]::UTF8.GetBytes("$name`n$hash`n"))
            }
            $fingerprint=[Convert]::ToHexString($digest.GetHashAndReset()).ToLowerInvariant()
        } finally {$digest.Dispose()}
        [pscustomobject]@{
            Id=[string]$info.id; Version=[string]$info.version; Directory=$relative
            FullDirectory=$directory; Info=$info; SourceFingerprint=$fingerprint
            AssetName="StarPie-PetAsset-$($info.id)-$($info.version).zip"
            ReleaseTag="pet-$($info.id)-v$($info.version)"
        }
    }
}

function Get-PetCatalogPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')][string]$Repository='Star-Pie/StarPie-DesktopPet-Assets',
        [object[]]$Receipts=@()
    )
    $previous=$null
    $catalogPath=Join-Path $Root 'catalog.json'
    if(Test-Path -LiteralPath $catalogPath) {
        $text=Get-Content -LiteralPath $catalogPath -Raw -Encoding utf8
        if(-not(Test-Json -Json $text -SchemaFile (Join-Path $Root 'schemas\catalog.schema.json'))){throw 'Invalid previous catalog'}
        $previous=$text | ConvertFrom-Json
    }
    $oldItems=@{}
    $order=@{}
    if($previous) {
        foreach($item in @($previous.items)) {
            if($oldItems.ContainsKey($item.id)){throw "Duplicate previous catalog id: $($item.id)"}
            $oldItems[$item.id]=$item; $order[$item.id]=$order.Count
        }
    }
    $receiptsById=@{}
    foreach($receipt in $Receipts) {
        if($receiptsById.ContainsKey($receipt.Id)){throw "Duplicate receipt: $($receipt.Id)"}
        $receiptsById[$receipt.Id]=$receipt
    }
    $sources=@(Get-PetAssetSources -Root $Root | Sort-Object @{Expression={if($order.ContainsKey($_.Id)){$order[$_.Id]}else{[int]::MaxValue}}},Directory)
    $items=@(); $releases=@()
    foreach($source in $sources) {
        $info=$source.Info
        $item=[ordered]@{
            id=$source.Id; name=[string]$info.name; version=$source.Version
            format='starpie-desktop-pet-legacy-png'; formatVersion=1; directory=$source.Directory
            canvas=$info.canvas; framesCount=12; preview='idle.png'; publishable=[bool]$info.publishable
        }
        if($info.PSObject.Properties['maintainer']){$item.maintainer=$info.maintainer}
        if($info.PSObject.Properties['license']){$item.license=$info.license}
        $old=$oldItems[$source.Id]
        if($old -and ([version]$source.Version -lt [version]$old.version)){throw "Version downgrade refused: $($source.Id)"}
        $sameVersion=$old -and $old.version -ceq $source.Version
        $published=$sameVersion -and $old.PSObject.Properties['downloadUrl'] -and -not [string]::IsNullOrWhiteSpace($old.downloadUrl)
        if($published -and $info.publishable) {
            foreach($field in @('releaseTag','downloadUrl','packageSha256','packageSize')) {
                if(-not $old.PSObject.Properties[$field]){throw "Incomplete published metadata: $($source.Id)"}
                $item[$field]=$old.$field
            }
        }
        $currentRelease=$info.publishable -and $published -and $old.releaseTag -ceq $source.ReleaseTag
        if($currentRelease -and $old.PSObject.Properties['sourceFingerprint']) {
            if($old.sourceFingerprint -cne $source.SourceFingerprint){throw "Published content changed without a version bump: $($source.Id) $($source.Version)"}
            $item.sourceFingerprint=$source.SourceFingerprint
        }
        if($receiptsById.ContainsKey($source.Id)) {
            $receipt=$receiptsById[$source.Id]
            if(-not $info.publishable -or $receipt.PrivateDraft -or $receipt.Version -cne $source.Version -or $receipt.AssetName -cne $source.AssetName -or $receipt.ReleaseTag -cne $source.ReleaseTag -or $receipt.SourceFingerprint -cne $source.SourceFingerprint -or $receipt.Sha256 -cnotmatch '^[a-f0-9]{64}$' -or $receipt.Size -le 0){throw "Invalid or stale public receipt: $($source.Id)"}
            $item.releaseTag=$source.ReleaseTag
            $item.downloadUrl="https://github.com/$Repository/releases/download/$($source.ReleaseTag)/$($source.AssetName)"
            $item.packageSha256=$receipt.Sha256; $item.packageSize=$receipt.Size
            $item.sourceFingerprint=$source.SourceFingerprint
            [void]$receiptsById.Remove($source.Id)
        } elseif($info.publishable -and (-not $currentRelease -or -not $old.PSObject.Properties['sourceFingerprint'])) {
            # Legacy shared Releases are retained until the independent package is published.
            $releases+=$source
        }
        $items+=[pscustomobject]$item
    }
    if($receiptsById.Count){throw 'Receipt does not correspond to a current source asset'}
    $catalog=[ordered]@{
        schemaVersion=1; catalog='starpie-desktop-pet-assets'; maintainer='SoftBlack42'
        updatedAtUtc=if($previous -and $previous.PSObject.Properties['updatedAtUtc']){$previous.updatedAtUtc}else{''}; items=@($items)
    }
    if($previous -and $previous.PSObject.Properties['bundle']) {
        $bundle=[ordered]@{}
        foreach($property in $previous.bundle.PSObject.Properties){$bundle[$property.Name]=$property.Value}
        $bundle.historical=$true
        $catalog.bundle=[pscustomobject]$bundle
    }
    $oldComparable=if($previous){($previous | Select-Object -ExcludeProperty updatedAtUtc | ConvertTo-Json -Depth 30 -Compress)}else{''}
    $newComparable=([pscustomobject]$catalog | Select-Object -ExcludeProperty updatedAtUtc | ConvertTo-Json -Depth 30 -Compress)
    if($oldComparable -cne $newComparable){$catalog.updatedAtUtc=[DateTime]::UtcNow.ToString('o')}
    [pscustomobject]@{Catalog=[pscustomobject]$catalog; Releases=@($releases)}
}

function Update-PetReadmeContent {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Content,[Parameter(Mandatory)]$Catalog)
    $start='<!-- PET-ASSETS:START -->'; $end='<!-- PET-ASSETS:END -->'
    if(([regex]::Matches($Content,[regex]::Escape($start))).Count -ne 1 -or ([regex]::Matches($Content,[regex]::Escape($end))).Count -ne 1){throw 'README must contain one PET-ASSETS marker pair'}
    if($Content.IndexOf($start) -ge $Content.IndexOf($end)){throw 'README marker order is invalid'}
    $public=@($Catalog.items | Where-Object publishable -EQ $true)
    $lines=@($start,"当前提供 **$($public.Count)** 套桌宠形象。每套包含常驻、眨眼、点击反馈、悬空拖动和八方向姿态，共 12 张 512×512 透明 PNG。",'','| 形象 | 预览 | 单独下载 |','| --- | --- | --- |')
    foreach($item in $public) {
        $name=[Net.WebUtility]::HtmlEncode([string]$item.name).Replace('|','&#124;').Replace("`r",' ').Replace("`n",' ')
        $preview=($item.directory.Split('/') | ForEach-Object {[uri]::EscapeDataString($_)}) -join '/'
        $download="v$($item.version)（待发布）"
        if($item.PSObject.Properties['downloadUrl'] -and $item.downloadUrl) {
            $uri=[uri]$item.downloadUrl
            if($uri.Scheme -ne 'https' -or $uri.Host -ne 'github.com' -or $uri.UserInfo -or $uri.Query -or $uri.Fragment -or $uri.AbsolutePath -notmatch '^/[^/]+/[^/]+/releases/download/'){throw "Unsafe download URL: $($item.id)"}
            $download="[v$($item.version)]($($item.downloadUrl))"
        }
        $lines+="| $name | <img src=`"$preview/idle.png`" alt=`"$name`" width=`"120`"> | $download |"
    }
    $lines+=$end
    $replacement=$lines -join "`n"
    $pattern='(?s)'+[regex]::Escape($start)+'.*?'+[regex]::Escape($end)
    [regex]::Replace($Content.Replace("`r`n","`n"),$pattern,[Text.RegularExpressions.MatchEvaluator]{param($match) $replacement})
}

function Export-PetAssets {
    [CmdletBinding()]
    param([string]$Root,[string]$OutputDirectory,[switch]$AllowPrivateDraft,[string]$PackId)
    $selected=@(Get-PetAssetSources -Root $Root)
    if(-not [string]::IsNullOrWhiteSpace($PackId)) {
        $selected=@($selected | Where-Object Id -CEQ $PackId)
        if($selected.Count -ne 1){throw "Unknown or duplicate selected asset pack: $PackId"}
    }
    foreach($source in $selected) {
        if(-not $AllowPrivateDraft -and -not $source.Info.publishable){throw 'Refusing public export: pack is marked private; use -AllowPrivateDraft for a private review package'}
    }
    if(-not $selected.Count){return}
    $out=[IO.Path]::GetFullPath($OutputDirectory)
    for($cursor=$out;$cursor;$cursor=[IO.Path]::GetDirectoryName($cursor)){if((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Reparse output directory refused'}}
    [void][IO.Directory]::CreateDirectory($out)
    foreach($source in $selected) {
        $name=if($AllowPrivateDraft){"StarPie-PetAsset-$($source.Id)-PRIVATE_DRAFT-$($source.Version).zip"}else{$source.AssetName}
        $target=Join-Path $out $name; $temp=Join-Path $out ('.pet-package-'+[guid]::NewGuid().ToString('N')+'.tmp')
        try {New-DeterministicPetZip -SourceDirectory $source.FullDirectory -DestinationZipPath $temp;[IO.File]::Move($temp,$target,$true)} finally {if(Test-Path -LiteralPath $temp){[IO.File]::Delete($temp)}}
        [pscustomobject]@{
            Id=$source.Id; Version=$source.Version; AssetName=$name; ReleaseTag=$source.ReleaseTag
            Path=$target; Sha256=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
            Size=(Get-Item -LiteralPath $target).Length; SourceFingerprint=$source.SourceFingerprint
            PrivateDraft=[bool]$AllowPrivateDraft
        }
    }
}
Export-ModuleMember -Function Resolve-PetDirectory,Get-PetAssetSources,Get-PetCatalogPlan,Update-PetReadmeContent,Export-PetAssets
