param (
    [ValidateSet("macOS", "iOS", "Windows")][string]$Platform,
    [switch]$debugging
)

function Get-PolicyDetails {
	param (
		$selected_policy
	)
    
	Write-Host "`nName: $($selected_policy.Name)" -ForegroundColor "Magenta"
	Write-Host "Id: $($selected_policy.Id)" -ForegroundColor "Magenta"

	switch ($selected_policy.ConfigType) {
	    "Legacy" {
		    $assignments = Get-MgBetaDeviceManagementDeviceConfigurationAssignment -DeviceConfigurationId $selected_policy.Id | Select-Object *, @{ Name = 'assign_or_exclude'; Expression = { $_.Target.AdditionalProperties['@odata.type'] -replace '#microsoft.graph.groupAssignmentTarget', 'Assigned Group' -replace '#microsoft.graph.exclusionGroupAssignmentTarget', 'Excluded Group' -replace '#microsoft.graph.allDevicesAssignmentTarget', 'Assigned All Devices'} } # Legacy
	    }
	    "Modern" {
		    $assignments = Get-MgBetaDeviceManagementConfigurationPolicyAssignment -DeviceManagementConfigurationPolicyId $selected_policy.Id | Select-Object *, @{ Name = 'assign_or_exclude'; Expression = { $_.Target.AdditionalProperties['@odata.type'] -replace '#microsoft.graph.groupAssignmentTarget', 'Assigned Group' -replace '#microsoft.graph.exclusionGroupAssignmentTarget', 'Excluded Group' -replace '#microsoft.graph.allDevicesAssignmentTarget', 'Assigned All Devices'} } # Modern
	    }
	    "Compliance" {
			$assignments = Get-MgBetaDeviceManagementDeviceCompliancePolicyAssignment -DeviceCompliancePolicyId $selected_policy.Id | Select-Object *, @{ Name = 'assign_or_exclude'; Expression = { $_.Target.AdditionalProperties['@odata.type'] -replace '#microsoft.graph.groupAssignmentTarget', 'Assigned Group' -replace '#microsoft.graph.exclusionGroupAssignmentTarget', 'Excluded Group' -replace '#microsoft.graph.allDevicesAssignmentTarget', 'Assigned All Devices'} } # Compliance
	    }
	    default {
	        Write-TnLogMessage "Unknown config type: $($selected_policy.ConfigType)"
	        continue
	    }
	}

    foreach ($a in $assignments | Sort-Object assign_or_exclude) {
				
		##	if ($debugging){
		##		write-output $a | format-list
		##		write-output ""
		##		write-output $a.Target.additionalproperties | format-list
		##	}
		
		if ($a.assign_or_exclude -eq "Assigned All Devices" ) {
	        Write-TnField -title "Assigned to" -value "All Devices"
		}
		
		if ($a.assign_or_exclude -eq "Assigned Group" ) {

			$groupId = $a.Target.additionalproperties['groupId']
		
	        $group = Get-MgBetaGroup -GroupId $groupId -ErrorAction SilentlyContinue
	        $groupName = if ($group.DisplayName) { $group.DisplayName } else { "Unknown group ($groupId)" }
			$group_members = (Get-MgBetaGroupMember -GroupId $groupId).AdditionalProperties.userPrincipalName	# doesn't get nested groups yet

	        Write-TnField -title "Assigned to" -value "$groupName [$groupId]"
	        Write-TnField -title "Group Members" -value "$group_members"
		}
		
		if ($a.assign_or_exclude -eq "Excluded Group" ) {

			$groupId = $a.Target.additionalproperties['groupId']
		
	        $group = Get-MgBetaGroup -GroupId $groupId -ErrorAction SilentlyContinue
	        $groupName = if ($group.DisplayName) { $group.DisplayName } else { "Unknown group ($groupId)" }
			$group_members = (Get-MgBetaGroupMember -GroupId $groupId).AdditionalProperties.userPrincipalName	# doesn't get nested groups yet

	        Write-TnField -title "Excluded from" -value "$groupName [$groupId]"
	        Write-TnField -title "Group Members" -value "$group_members"
		}
		
		if ($debugging){
	        Write-TnField -title "Assignment ID" -value $a.Id
	        Write-TnField -title "Intent" -value $a.'Intent' # generally apply or blank -- "what to do when applied"
	        Write-TnField -title "Source" -value $a.'Source' # "manually in Intune vs inherited from policy"
		}

    }
	
}



Write-TnLogMessage "Note: this script uses the MgGraph *Beta* Endpoints, as these features are not complete in the standard version which will return limited results."

Import-Module Microsoft.Graph.Beta.DeviceManagement
Import-Module Microsoft.Graph.Beta.Groups
Import-Module Tintern -DisableNameChecking -Force

$connect_MgGraph = Connect-MgGraph -Scopes "DeviceManagementConfiguration.Read.All", "Group.Read.All", "User.Read.All"

Write-TnLogMessage "Looking for $Platform configuration profiles..."

$platformTypeMap = @{
    macOS   = 'macOS'
    iOS     = 'iOS'
    Windows = 'windows'
}

## $all_policies = Get-MgBetaDeviceManagementDeviceConfiguration -Property * | Select-Object *, @{
##     Name = 'odata.type'
##     Expression = { $_.AdditionalProperties['@odata.type'] -replace '#microsoft.graph.', '' }
## }

$legacy_policies = Get-MgBetaDeviceManagementDeviceConfiguration -Property * | Select-Object *, @{ Name = 'Platform'; Expression = { $_.AdditionalProperties['@odata.type'] -replace '#microsoft.graph.', '' } }, @{Name = 'ConfigType'; Expression = { "Legacy" }}

$modern_policies = Get-MgBetaDeviceManagementConfigurationPolicy -Property * | Select-Object *,`
    @{Name = 'DisplayName'; Expression = { $_.Name }},  # Rename 'Name' → 'DisplayName'
    @{Name = 'Platform'; Expression = { $_.Platforms }},
    @{Name = 'ConfigType'; Expression = { "Modern" }}

$compliance_policies = Get-MgBetaDeviceManagementDeviceCompliancePolicy -Property * | Select-Object *, @{ Name = 'Platform'; Expression = { $_.AdditionalProperties['@odata.type'] -replace '#microsoft.graph.', '' } }, @{Name = 'ConfigType'; Expression = { "Compliance" }}

## (Get-MgBetaDeviceManagementDeviceCompliancePolicy -DeviceCompliancePolicyId f5ab30ad-86b9-44cd-b6ab-f3efee8e7d26).AdditionalProperties | format-list

$all_policies = $legacy_policies + $modern_policies + $compliance_policies

$indexed_policies = @()
$i = 1

foreach ($policy in $all_policies | Sort-Object Platform, DisplayName) {

	if ($Platform) {
	    if ($policy.'Platform' -like "*$($platformTypeMap[$Platform])*") {
	        $indexed_policies += [PSCustomObject]@{
	            Index     = $i
	            Name      = $policy.DisplayName
	            Id        = $policy.Id
	            Platform = $policy.'Platform'
	            ConfigType = $policy.'ConfigType'
	        }
		$i++
	    }
	} else {
		$indexed_policies += [PSCustomObject]@{
		    Index     = $i
		    Name      = $policy.DisplayName
		    Id        = $policy.Id
		    Platform = $policy.'Platform'
            ConfigType = $policy.'ConfigType'
		}
		$i++
	}

}

$indexed_policies | Format-Table Index, Platform, ConfigType, Name, Id

if (-not $indexed_policies) {
    Write-TnLogMessage "No policies found for $Platform"
    exit
}



## TO DO
## Loop throught every policy and get the assignments for each, and populate one big object with all of them.



while ($true) {

	Write-Host ""
	
	$selection = Read-Host "Enter either the number of the policy to inspect; 'exportJSON' or 'exportCSV' to export results; or 'exit' to quit"

    if ($selection -eq 'exit') { break }

    if ($selection -eq 'exportJSON') {
        $indexed_policies | ConvertTo-Json -Depth 5 | Out-File "./policies.json"
        Write-TnLogMessage "Exported to policies.json"
        continue
    }

    if ($selection -eq 'exportCSV') {
        $indexed_policies | Export-Csv -NoTypeInformation -Path "./policies.csv"
        Write-TnLogMessage "Exported to policies.csv"
        continue
    }

    if ($selection -eq 'all') {

		foreach ($selected_policy in $indexed_policies) {

			Get-PolicyDetails $selected_policy
			
		}

        continue
    }

	if ($selection -match '^\d+$') {
	    $selected_policy = $indexed_policies | Where-Object { $_.Index -eq [int]$selection }
	} else {
	    Write-TnLogMessage "Invalid selection"
	    continue
	}
	
	Get-PolicyDetails $selected_policy

}