function Get-BuildBackendStatus {
    $version=(Get-Item -LiteralPath 'D:\Games\ELDEN RING\Game\eldenring.exe').VersionInfo.FileVersion
    [pscustomobject]@{ready=$false;gameVersion=$version;tableVersion='2.7.0.0';message="Game $version; table 2.7.0.0. No verified compatible write adapter installed."}
}
function Invoke-BuildPlan {
    param($Plan,$Root)
    [pscustomobject]@{ok=$false;applied=$false;message=(Get-BuildBackendStatus).message}
}
