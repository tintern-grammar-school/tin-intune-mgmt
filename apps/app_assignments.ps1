param([switch]$debugging,
	[switch]$check_assignments,
	[switch]$add_assignment,
	[switch]$delete_assignment,
	[string]$app_name
	)

function Get-TimeStamp {
	# Source: https://www.gngrninja.com/script-ninja/2016/2/12/powershell-quick-tip-simple-logging-with-timestamps)
	# Returns date and time in format: [2020-02-18 12:12:57]
    return "[{0:dd/MM/yy} {0:HH:mm:ss}]" -f (Get-Date)
}

function Get-FSdate {
	# Returns date in format: 2020-02-18
  return "{0:yyyy-MM-dd}" -f (Get-Date)  
}

function logger($message) {
	# Outputs logging to both file and stdout
	# To log file
	$log_filepath = "/Users/Shared/logs/intune_app_assignments_$(Get-FSdate).log"
	Write-Output "$(Get-TimeStamp) $message" | Out-file $log_filepath -append
	# To stdout
	if ($debugging) {
		Write-Host "$(Get-TimeStamp) Log: $message" -ForegroundColor Yellow
	} else {
		Write-Host "$message"
	}
}

function Get-AppByName {
    param([string]$app_name)

	if ($debugging){
		$apps = Get-MgDeviceAppManagementMobileApp -All | Where-Object { $_.DisplayName -like "*$app_name*" }
	} else {
		$apps = Get-MgDeviceAppManagementMobileApp -All | Where-Object { $_.DisplayName -like "*$app_name*" } 2>$null			
	}

	# Normalize the Additional Properties -> @odata.type value for the platform into a key pair
	foreach ($app in $apps) {
	    $app | Add-Member -NotePropertyName 'Platform' -NotePropertyValue ($app.AdditionalProperties['@odata.type'] -replace '^#microsoft.graph.', '') -Force
	    $app | Add-Member -NotePropertyName 'Architectures' -NotePropertyValue ($app.AdditionalProperties['ApplicableArchitectures']) -Force
	}

	if($debugging){
		Write-Host "Apps Found in Intune:"
		$found_apps = $apps | ConvertTo-Json -Depth 5
		Write-Host $found_apps
	}
	
    if (-not $apps) {
        logger "`nNo apps found."
		return
    }

    if ($apps.Count -gt 1) {
        Write-Host "`nMultiple apps found:`n"

        $index = 1
        foreach ($app in $apps) {
			$platform = $app.AdditionalProperties.'@odata.type' -replace '^#microsoft.graph.', ''

			$platform = $app.AdditionalProperties

            if ($debugging) {
                Write-Host "$index. $($app.DisplayName) ($app.Platform | $($app.Id))"
            } else {
                Write-Host "$index. $($app.DisplayName) ($app.Platform)"
            }
            $index++
        }

        $selected = Read-Host "`nEnter the number of the app you want to use"
		Write-Host ""
        return $apps[$selected - 1]
    }

    return $apps
}

function Get-AppAssignments {
    param([string]$app_id,
		[string]$app_name
	)

	$assignments = Get-MgDeviceAppManagementMobileAppAssignment -MobileAppId $app_id
	
	#logger "Assignment for $app_name ($app_id) found with ID(s): $($assignments.id)"
	
	return $assignments
}

function Show-AppAssignment {
    param(
        [string]$app_id,
        [string]$app_name,
		[string]$assignment_id
    )

    $assignment = Get-MgDeviceAppManagementMobileAppAssignment -MobileAppId $app_id -MobileAppAssignmentId $assignment_id

	if($debugging){
		$assignment
	}	
	
	# See assignment target details
	if($debugging){
		Write-Host "Target:"
		$target= $assignment.Target | ConvertTo-Json -Depth 5
		Write-Host $target
	}

	$group_id = $assignment.Target.AdditionalProperties.groupId
	$group = Get-MgGroup -GroupId $group_id
	
	Write-TnField -title "`nAssignment: " -value $assignment_id
	Write-TnField -title "Target Group: " -value $group.DisplayName
	Write-TnField -title "Assignment Type: " -value $assignment.Intent	
	
}



function Modify-AppAssignment {
    param(
        [string]$app_id,
        [string]$app_name
    )

    $groups = Get-MgGroup -Top 1000
    $matching_groups = $groups | Where-Object { $_.DisplayName -like "*Intune*" }

    $matching_groups | Format-Table Id, DisplayName

	do {
		Write-Host "Enter group ID" -ForegroundColor Green
		$group_id = Read-Host
		$valid = $matching_groups.Id -contains $group_id
		if (-not $valid) { Write-Host "Invalid group ID. Try again." -ForegroundColor Red }
	} until ($valid)	
	
    $intent = Read-Host "Enter install intent ('required' or 'available')"

	# logger $group_id
	# logger $intent

    if ($intent -notin @("required", "available")) {
        Write-Host "Invalid intent."
        return
    }

	$assignment = @{
	    "@odata.type"   = "#microsoft.graph.mobileAppAssignment"
	    installIntent   = $intent
	    target          = @{
	        "@odata.type" = "#microsoft.graph.groupAssignmentTarget"
	        groupId       = $group_id
	    }
	}
	
	if($debugging){
		$assignment	
	}
	
	try {
	    $result = New-MgDeviceAppManagementMobileAppAssignment -MobileAppId $app_id -BodyParameter $assignment -ErrorAction Stop

	    if ($result) {
	        Write-Host "Assignment created." -ForegroundColor Green
	    } else {
	        Write-Host "Assignment may not have been created." -ForegroundColor Yellow
	    }
	}

	catch {
	    Write-Host "Failed to create assignment. Error: $_" -ForegroundColor Red
	}
		
}

# Feature to Add -- Search for App by Name
## Feature to Add -- when multiple apps are returned, show a list (numbered 1-X for ppl to select from)

# Feature to Add -- List all Apps by Platform (e.g. macOS PKG or DMG)
# Feature to Add -- Search for Group to Assign by Name
## When selecting which group, show numbered 1-X for ppl to select from

## SCRIPT RUNTIME LOGIC STARTS HERE

if (-not $app_name) {
	$app_name = Read-Host "Enter App Name"
}

Write-Host "`nWelcome to the Intune App Assignments script.`n"

# Import-Module Microsoft.Graph.DeviceManagement

# Ensure you're connected
if (-not (Get-MgUser 2>$null)) {
    Write-Host "Connecting to Microsoft Graph..."
    Connect-MgGraph -Scopes "DeviceManagementApps.ReadWrite.All", "Group.ReadWrite.All"
}

Write-TnField -title "App Name Supplied: " -value $app_name

$app = Get-AppByName -app_name $app_name

Write-TnField -title "App Name Found: " -value $app.DisplayName
Write-TnField -title "App ID: " -value $app.Id
Write-TnField -title "App Platform: " -value $app.Platform


while ($true) {
	
	if ($check_assignments) {
		$choice = "1"
	} elseif ($add_assignment) {
		$choice = "2"
	} elseif ($delete_assignment) {
		$choice = "3"
	} else {
		Write-Host ""
		Write-Host "Menu"
		Write-Host "----"
		Write-Host "1) Check Assignments for $($app.DisplayName)"
		Write-Host "2) Add Assignment for $($app.DisplayName)"
		Write-Host "3) Delete Assignment for $($app.DisplayName)"
		Write-Host "4) Switch App to Use"
		Write-Host "q) Quit"
		Write-Host ""
		$choice = Read-Host "Select an option (1-4) or q"
	}
    
    switch ($choice) {
        '1' {
						    			
			$assignments = Get-AppAssignments -app_id $($app.Id) -app_name $($app.DisplayName)

			if (-not $assignments) {
			    Write-Host "`nNo assignments found for $($app.DisplayName)." -ForegroundColor Yellow
			    $add = Read-Host "Would you like to add an assignment now? (y/n)"
			    if ($add -eq 'y') {
			        Modify-AppAssignment -app_id $app.Id
			    }
			    continue
			}
			
			if ($($assignments.Count) -gt 1) {
				Write-Host "`n$($assignments.Count) assignments found for $($app.DisplayName):"				
			} else {
				Write-Host "`n$($assignments.Count) assignment found for $($app.DisplayName):"
			}

			
			foreach ($assignment in $assignments) {
			    Show-AppAssignment -app_id $($app.Id) -app_name $($app.DisplayName) -assignment_id $($assignment.Id)
			}			
		    
			Write-Host ""
            #Pause
			continue

        }

        '2' {

            Modify-AppAssignment -app_id $app.Id

		    Write-Host ""

            #Pause
			continue
        }
		
		'3' {

		    $assignments = Get-AppAssignments -app_id $app.Id -app_name $app.DisplayName

		    if (-not $assignments) {
		        Write-Host "`nNo assignments found for $($app.DisplayName)." -ForegroundColor Yellow
		        continue
		    }

		    $assignments | ForEach-Object {
		        Write-TnField "`nAssignment ID: " $_.Id -ForegroundColor Cyan
		        $group_id = $_.Target.AdditionalProperties.groupId
		        $group = Get-MgGroup -GroupId $group_id -ErrorAction SilentlyContinue
		        if ($group) {
		             Write-TnField "Group: " $group.DisplayName
		        }
		    }

		    $assignment_id = Read-Host "Enter Assignment ID to delete"
		    try {
		        Remove-MgDeviceAppManagementMobileAppAssignment -MobileAppId $app.Id -MobileAppAssignmentId $assignment_id -ErrorAction Stop
		        Write-Host "Assignment deleted successfully." -ForegroundColor Green
		    } catch {
		        Write-Host "Failed to delete assignment: $_" -ForegroundColor Red
		    }

		    continue
		}
		
        '4' {
				$app_name = Read-Host "Enter App Name"
				Write-TnField -title "App Name Supplied: " -value $app_name
            	
				$app = Get-AppByName -app_name $app_name
				Write-TnField -title "App Name Found: " -value $app.DisplayName
				Write-TnField -title "App ID: " -value $app.Id
				Write-TnField -title "App Platform: " -value $app.Platform
	        	continue
			}
		
        'q' {
            return
        }
		
        default {
            Write-Host "Invalid option." -ForegroundColor Red
        }
    }
}