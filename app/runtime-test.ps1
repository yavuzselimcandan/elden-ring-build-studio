$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'backend.ps1')
$s=Get-BuildBackendStatus -Root $PSScriptRoot
if($null -eq $s.gameVersion){throw 'game version probe failed'}
$bad=[pscustomobject]@{items=@([pscustomobject]@{category='weapon';itemId=1;quantity=1;upgrade=0;ashOfWarId=42});attributes=[pscustomobject]@{}}
try { Invoke-BuildPlan $bad $PSScriptRoot; throw 'unsupported ash request was accepted' } catch { if($_.Exception.Message -notmatch 'Ash of War'){throw} }
Write-Output 'runtime contract ok (live adapter not exercised)'
