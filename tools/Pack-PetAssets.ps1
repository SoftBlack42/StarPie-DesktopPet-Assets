[CmdletBinding()]
param([string]$OutputDirectory='dist',[switch]$AllowPrivateDraft,[string]$PackId)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'PetAssets.psm1') -Force
$root=Split-Path -Parent $PSScriptRoot
$out=if([IO.Path]::IsPathRooted($OutputDirectory)){$OutputDirectory}else{[IO.Path]::GetFullPath((Join-Path $root $OutputDirectory))}
Export-PetAssets -Root $root -OutputDirectory $out -AllowPrivateDraft:$AllowPrivateDraft -PackId $PackId
