#Requires -Version 7.2
[CmdletBinding()]
param(
    [string]$Root=(Split-Path -Parent $PSScriptRoot),
    [string]$OutputDirectory='dist/metadata',
    [string]$Repository='Star-Pie/StarPie-DesktopPet-Assets',
    [string]$ReceiptsPath
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'PetAssets.psm1') -Force
$receipts=if($ReceiptsPath){@(Get-Content -LiteralPath $ReceiptsPath -Raw -Encoding utf8 | ConvertFrom-Json)}else{@()}
$plan=Get-PetCatalogPlan -Root $Root -Repository $Repository -Receipts $receipts
$readme=Update-PetReadmeContent -Content (Get-Content -LiteralPath (Join-Path $Root 'README.md') -Raw -Encoding utf8) -Catalog $plan.Catalog
$out=if([IO.Path]::IsPathRooted($OutputDirectory)){$OutputDirectory}else{Join-Path $Root $OutputDirectory}
[void][IO.Directory]::CreateDirectory($out)
[IO.File]::WriteAllText((Join-Path $out 'catalog.json'),(($plan.Catalog | ConvertTo-Json -Depth 30)+"`n"),[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $out 'README.md'),$readme,[Text.UTF8Encoding]::new($false))
Write-Host "Generated catalog and README; $($plan.Releases.Count) independent releases pending."
