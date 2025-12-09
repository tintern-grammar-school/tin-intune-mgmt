param(
    [Parameter(Mandatory)]
    [string]$vault_api_creds_name,

    [Parameter(Mandatory)]
    [string]$mobileconfig_path,

    [Parameter(Mandatory)]
    [string]$display_name,

    [string]$description = '',

    [Parameter(Mandatory)]
    [string]$group_match       # e.g. "Intune Rebuild"
)

Import-Module Microsoft.Graph.DeviceManagement -ErrorAction Stop
Import-Module Microsoft.Graph.Groups -ErrorAction Stop
Import-Module Tintern -ErrorAction Stop   # contains Connect-TnGraphAppCert

# --- Auth ---
Connect-TnGraphAppCert -vault_api_creds_name "$vault_api_creds_name"

# --- Read & Base64 the mobileconfig ---
$bytes = [IO.File]::ReadAllBytes((Resolve-Path $mobileconfig_path))
$b64   = [Convert]::ToBase64String($bytes)
$fname = Split-Path $mobileconfig_path -Leaf

$body = @{
    "@odata.type"   = "#microsoft.graph.macOSCustomConfiguration"
    displayName     = $display_name
    description     = $description
    payloadName     = $fname
    payloadFileName = $fname
    payload         = $b64
}

$profile = New-MgDeviceManagementDeviceConfiguration -BodyParameter $body
$profile_id = $profile.Id

Write-Host "Created profile: $display_name ($profile_id)"
Write-Host ""

# --- Find matching groups ---
$groups = Get-MgGroup -All |
    Where-Object { $_.DisplayName -like "*$group_match*" } |
    Sort-Object DisplayName

if (-not $groups) {
    Write-Warning "No groups matched '$group_match'."
    exit
}

# Build indexed list
$i = 1
$indexed = foreach ($g in $groups) {
    [PSCustomObject]@{
        Index       = $i
        DisplayName = $g.DisplayName
        Id          = $g.Id
    }
    $i++
}

function Show-List {
    $indexed | Select-Object Index, DisplayName | Format-Table -AutoSize
}

Show-List
Write-Host "`nChoose group numbers to assign. Type 'list' to re-display, 'exit' to quit.`n"

while ($true) {
    $raw = Read-Host "Group number ('list' / 'exit')"
    $x   = $raw.Trim()

    if (-not $x) { continue }

    $lower = $x.ToLowerInvariant()

    if ($lower -eq 'exit') { break }
    if ($lower -eq 'list') { Show-List; continue }

    if ($x -notmatch '^\d+$') {
        Write-Warning "Invalid input. Enter a number, 'list', or 'exit'."
        continue
    }

    $idx = [int]$x
    $sel = $indexed | Where-Object { $_.Index -eq $idx }

    if (-not $sel) {
        Write-Warning "Invalid index."
        continue
    }

    $assign = @{
        "@odata.type" = "#microsoft.graph.deviceConfigurationAssignment"
        target        = @{
            "@odata.type" = "#microsoft.graph.groupAssignmentTarget"
            groupId       = $sel.Id
        }
    }

    New-MgDeviceManagementDeviceConfigurationAssignment `
        -DeviceConfigurationId $profile_id `
        -BodyParameter $assign | Out-Null

    Write-Host "Assigned to: $($sel.DisplayName)"
}