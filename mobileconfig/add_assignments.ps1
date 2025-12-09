param(
    [Parameter(Mandatory)]
    [string]$vault_api_creds_name,

    [Parameter(Mandatory)]
    [string]$group_match       # e.g. "Intune Rebuild"
)

Import-Module Microsoft.Graph.DeviceManagement -ErrorAction Stop
Import-Module Microsoft.Graph.Groups -ErrorAction Stop
Import-Module Tintern -ErrorAction Stop   # contains Connect-TnGraphAppCert

# --- Auth ---
Connect-TnGraphAppCert -vault_api_creds_name "$vault_api_creds_name"

Write-Host "`nLoading macOS profiles and groups...`n"

# ----------------------
# LOAD MAC PROFILES ONCE
# ----------------------
$mac_profiles = Get-MgDeviceManagementDeviceConfiguration -All |
    Where-Object {
        $_.AdditionalProperties.'@odata.type' -in @(
            '#microsoft.graph.macOSCustomConfiguration',
            '#microsoft.graph.macOSGeneralDeviceConfiguration'
        )
    } |
    Sort-Object DisplayName

if (-not $mac_profiles) {
    Write-Warning "No macOS profiles found."
    exit
}

# index profiles
$i = 1
$indexed_profiles = foreach ($p in $mac_profiles) {
    [PSCustomObject]@{
        Index       = $i
        Name        = $p.DisplayName
        Id          = $p.Id
        Type        = $p.AdditionalProperties.'@odata.type'
    }
    $i++
}

function Show-Profiles {
    $indexed_profiles |
        Select-Object Index, Name, Type |
        Format-Table -AutoSize
}

# ----------------------
# LOAD GROUPS ONCE
# ----------------------
$groups = Get-MgGroup -All |
    Where-Object { $_.DisplayName -like "*$group_match*" } |
    Sort-Object DisplayName

if (-not $groups) {
    Write-Warning "No groups matched '$group_match'."
    exit
}

$j = 1
$indexed_groups = foreach ($g in $groups) {
    [PSCustomObject]@{
        Index       = $j
        Name        = $g.DisplayName
        Id          = $g.Id
    }
    $j++
}

function Show-Groups {
    $indexed_groups |
        Select-Object Index, Name |
        Format-Table -AutoSize
}

# ----------------------
# LEVEL 1 LOOP — SELECT PROFILE
# ----------------------
while ($true) {

    Write-Host "`n=== macOS Configuration Profiles ===`n"
    Show-Profiles

    Write-Host "`nSelect a profile index."
    Write-Host "Type 'exit' to quit."
    Write-Host ""

    $raw = Read-Host "Profile number"
    $x = $raw.Trim().ToLowerInvariant()

    if ($x -eq 'exit') { exit }

    if ($x -notmatch '^\d+$') {
        Write-Warning "Invalid input."
        continue
    }

    $profile = $indexed_profiles | Where-Object { $_.Index -eq [int]$x }
    if (-not $profile) {
        Write-Warning "Invalid index."
        continue
    }

    Write-Host "`nSelected profile: $($profile.Name)`n"

    # ------------------------------------------------
    # LEVEL 2 LOOP — ASSIGN GROUPS (NO RELOAD)
    # ------------------------------------------------

    Write-Host "Matching groups:"
    Show-Groups
    Write-Host "`nChoose groups to assign."
    Write-Host "Type 'list' to show groups again."
    Write-Host "Type 'exit' to return to profile list."
    Write-Host ""

    while ($true) {

        $raw = Read-Host "Group number"
        $g = $raw.Trim().ToLowerInvariant()

        if ($g -eq 'exit') { break }       # ← go back to profile list
        if ($g -eq 'list') { Show-Groups; continue }

        if ($g -notmatch '^\d+$') {
            Write-Warning "Invalid input."
            continue
        }

        $sel = $indexed_groups | Where-Object { $_.Index -eq [int]$g }
        if (-not $sel) {
            Write-Warning "Invalid index."
            continue
        }

        # Assign group
        $assign = @{
            "@odata.type" = "#microsoft.graph.deviceConfigurationAssignment"
            target        = @{
                "@odata.type" = "#microsoft.graph.groupAssignmentTarget"
                groupId       = $sel.Id
            }
        }

        New-MgDeviceManagementDeviceConfigurationAssignment `
            -DeviceConfigurationId $profile.Id `
            -BodyParameter $assign | Out-Null

        Write-Host "Assigned → $($sel.Name)"
    }
}