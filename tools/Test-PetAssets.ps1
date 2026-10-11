[CmdletBinding()]
param([string]$Root=(Split-Path -Parent $PSScriptRoot),[string]$CatalogPath='catalog.json')
$ErrorActionPreference='Stop'
$repoRoot=$Root
Import-Module (Join-Path $PSScriptRoot 'PetAssets.psm1') -Force
Add-Type -AssemblyName PresentationCore
$definition='public static class PetPixelChecks { public static bool Valid(byte[] data,int width,int height) {bool transparent=false,solid=false;for(int y=0;y<height;y++) for(int x=0;x<width;x++){int alpha=data[(y*width+x)*4+3];if(alpha==0)transparent=true;if(alpha>=250)solid=true;if((x==0||y==0||x==width-1||y==height-1)&&alpha>=64)return false;}return transparent&&solid;}}'
if(-not ('PetPixelChecks' -as [type])){Add-Type -TypeDefinition $definition}
$count=0
function Check([bool]$ok,[string]$message){if(-not $ok){throw "ASSET VALIDATION FAILED: $message"};$script:count++;Write-Host " [PASS] $message"}
$catalogText=Get-Content -LiteralPath $(if([IO.Path]::IsPathRooted($CatalogPath)){$CatalogPath}else{Join-Path $repoRoot $CatalogPath}) -Raw -Encoding utf8
Check (Test-Json -Json $catalogText -SchemaFile (Join-Path $repoRoot 'schemas/catalog.schema.json')) 'catalog schema validated'
$catalog=$catalogText|ConvertFrom-Json
if($catalog.items.Count -eq 0){
 $petsRoot=Join-Path $repoRoot 'pets'
 $remaining=if(Test-Path -LiteralPath $petsRoot){@(Get-ChildItem -LiteralPath $petsRoot -Recurse -File -Force)}else{@()}
 Check ($remaining.Count -eq 0) 'empty catalog has no remaining asset files'
 Write-Host "PASS: $count asset assertions (empty catalog)"
 return
}
$sources=@(Get-PetAssetSources -Root $repoRoot)
Check ($sources.Count -eq $catalog.items.Count) 'catalog covers all source directories'
$seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$mapping=[ordered]@{idle='idle.png';blink='blink.png';react='react.png';drag='drag.png';'point.E'='point_E.png';'point.SE'='point_SE.png';'point.S'='point_S.png';'point.SW'='point_SW.png';'point.W'='point_W.png';'point.NW'='point_NW.png';'point.N'='point_N.png';'point.NE'='point_NE.png'}
foreach($item in $catalog.items){
 Check ($seen.Add($item.id)) 'unique pack id'
 $dir=Resolve-PetDirectory -Root $repoRoot -Relative $item.directory
 $text=Get-Content -LiteralPath (Join-Path $dir 'asset-info.json') -Raw -Encoding utf8
 Check (Test-Json -Json $text -SchemaFile (Join-Path $repoRoot 'schemas/asset-info.schema.json')) "$($item.id): info schema"
 $info=$text|ConvertFrom-Json
 Check ($info.id -eq $item.id -and $info.version -eq $item.version) 'catalog id/version agree'
 Check ($info.publishable -eq $item.publishable) 'catalog publication flag agrees'
 if($info.publishable -ne $true){Check ([string]::IsNullOrEmpty($item.downloadUrl)) 'private pack has no public download URL'}
 Check (Test-Path -LiteralPath (Join-Path $dir 'README.md') -PathType Leaf) 'import instructions present'
 $expected=Get-Content -LiteralPath (Join-Path $dir 'frame-sha256.json') -Raw | ConvertFrom-Json
 foreach($state in $mapping.Keys){
  $name=$mapping[$state];Check ($info.frames.$state -ceq $name) "frame mapping $state"
  $file=Join-Path $dir $name
  Check ((Test-Path -LiteralPath $file -PathType Leaf) -and (Get-Item -LiteralPath $file).Length -lt 10MB) "$name exists within size limit"
  Check (-not ((Get-Item -LiteralPath $file).Attributes -band [IO.FileAttributes]::ReparsePoint)) "$name not reparse"
  $bytes=[IO.File]::ReadAllBytes($file)
  Check ($bytes.Length -gt 26 -and $bytes[24] -eq 8 -and $bytes[25] -eq 6) "$name RGBA8 PNG"
  $stream=[IO.MemoryStream]::new($bytes)
  try {
   $decoder=[Windows.Media.Imaging.BitmapDecoder]::Create($stream,[Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat,[Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
   $frame=$decoder.Frames[0]
   Check ($frame.PixelWidth -eq 512 -and $frame.PixelHeight -eq 512) "$name 512 canvas"
   $bitmap=[Windows.Media.Imaging.FormatConvertedBitmap]::new($frame,[Windows.Media.PixelFormats]::Bgra32,$null,0)
   $pixels=[byte[]]::new(512*512*4);$bitmap.CopyPixels($pixels,512*4,0)
   Check ([PetPixelChecks]::Valid($pixels,512,512)) "$name true transparency and no clipped solid edge"
  }finally{$stream.Dispose()}
  Check ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() -eq $expected.$name) "$name tracked source checksum"
 }
}
Write-Host "PASS: $count asset assertions"
