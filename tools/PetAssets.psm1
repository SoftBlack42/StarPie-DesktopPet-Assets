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


function Export-PetAssets {
    param([string]$Root,[string]$OutputDirectory,[switch]$AllowPrivateDraft,[string]$PackId)
    $catalogText=Get-Content -LiteralPath (Join-Path $Root 'catalog.json') -Raw -Encoding utf8
    if(-not(Test-Json -Json $catalogText -SchemaFile (Join-Path $Root 'schemas/catalog.schema.json'))){throw 'Catalog schema validation failed'}
    $catalog=$catalogText | ConvertFrom-Json
    if($catalog.schemaVersion -ne 1 -or -not $catalog.items){throw 'Invalid asset catalog'}
    $selected=@($catalog.items)
    if(-not [string]::IsNullOrWhiteSpace($PackId)) {
        $selected=@($catalog.items | Where-Object {$_.id -ceq $PackId})
        if($selected.Count -ne 1){throw "Unknown or duplicate selected asset pack: $PackId"}
    }
    $plans=@()
    foreach($item in $selected){
        $dir=Resolve-PetDirectory -Root $Root -Relative $item.directory
        $infoText=Get-Content -LiteralPath (Join-Path $dir 'asset-info.json') -Raw -Encoding utf8
        if(-not(Test-Json -Json $infoText -SchemaFile (Join-Path $Root 'schemas/asset-info.schema.json'))){throw 'Asset schema validation failed'}
        $info=$infoText | ConvertFrom-Json
        if($info.id -ne $item.id -or $info.version -ne $item.version -or $info.publishable -ne $item.publishable){throw 'Asset/catalog metadata mismatch'}
        if(-not $AllowPrivateDraft -and $info.publishable -ne $true){throw 'Refusing public export: pack is marked private; use -AllowPrivateDraft for a private review package'}
        if($item.id -notmatch '^[a-z0-9][a-z0-9._-]*$' -or $item.version -notmatch '^\d+\.\d+\.\d+$'){throw 'Unsafe asset id/version'}
        foreach($name in @('idle.png','blink.png','react.png','drag.png','point_E.png','point_SE.png','point_S.png','point_SW.png','point_W.png','point_NW.png','point_N.png','point_NE.png','asset-info.json','README.md')){
            $file=Join-Path $dir $name
            if(-not(Test-Path -LiteralPath $file -PathType Leaf) -or ((Get-Item -LiteralPath $file).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw "Missing or reparse asset file: $name"}
        }
        $suffix=if($AllowPrivateDraft){'-PRIVATE_DRAFT'}else{''}
        $plans+= [pscustomobject]@{Directory=$dir;Name="StarPie-PetAsset-$($item.id)$suffix-$($item.version).zip"}
    }
    # The entire catalog is authorized before creating any output directory/file.
    $out=[IO.Path]::GetFullPath($OutputDirectory)
    for($cursor=$out;$cursor;$cursor=[IO.Path]::GetDirectoryName($cursor)){if((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Reparse output directory refused'}}
    [void][IO.Directory]::CreateDirectory($out)
    foreach($plan in $plans){
        $target=Join-Path $out $plan.Name;$temp=Join-Path $out ('.pet-package-'+[guid]::NewGuid().ToString('N')+'.tmp')
        try {New-DeterministicPetZip -SourceDirectory $plan.Directory -DestinationZipPath $temp;[IO.File]::Move($temp,$target,$true)} finally {if(Test-Path -LiteralPath $temp){[IO.File]::Delete($temp)}}
        [pscustomobject]@{Path=$target;Sha256=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant();PrivateDraft=[bool]$AllowPrivateDraft}
    }
}
Export-ModuleMember -Function Resolve-PetDirectory,Export-PetAssets
