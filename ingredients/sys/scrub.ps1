<#
.name 
    scrub
.description
    Selectively delete items from the Kitchen History, or perform a total wipe with `-All`.
    Useful for removing specific entries without affecting the entire history, or for starting fresh.
    if binaries have been found and not in path, scrub will propmp intdivial deletion or if -NoPrompt is used, it will delete all broken entries.
.status
    wip
.platform
    win64, linux64, osx64
.authors
    @PsChef
.dependencies
    pwsh
#>

param(
    [switch]$All
)

if ($All) {
    $Confirm = Read-Host "WIPE ALL HISTORY? This cannot be undone. [y/N]"
    if ($Confirm -match "^[Yy]") {
        @{ Installed = @{} } | ConvertTo-Json | Set-Content $global:ChefConfigFile
        Write-KitchenLog Success "Kitchen history has been nuked."
        return
    }
}

# Fetch history as a list for the menu
$History = invoke-pschef status -Raw

if ($null -eq $History -or $History.Count -eq 0) {
    Write-KitchenLog Warning "Nothing to scrub. The kitchen is already pristine."
    return
}

# Launch the Menu for Selection
$Title = "KITCHEN SCRUBBER"
$Subtitle = "Select an item to FORGET (Delete from history)"
$Selection = Show-ChefInteractiveMenu -Data $History -Title $Title -Subtitle $Subtitle

if ($null -eq $Selection) {
    Write-KitchenLog Info "Scrub cancelled."
    return
}

# Perform the Deletion
$KeyToDelete = "$($Selection.Pantry)/$($Selection.Ingredient)"

$Confirm = Read-Host "Are you sure you want to forget '$KeyToDelete'? [y/N]"
if ($Confirm -match "^[Yy]") {
    # We reach into the state engine directly
    $State = Get-KitchenState
    if ($State.Installed.psobject.Properties[$KeyToDelete]) {
        $State.Installed.psobject.Properties.Remove($KeyToDelete)
        
        # Save back
        $State | ConvertTo-Json -Depth 5 | Set-Content $global:ChefConfigFile
        
        Write-KitchenLog Success "Successfully forgotten: $KeyToDelete"
        
        # Recursive call to allow scrubbing more items
        $GoAgain = Read-Host "Scrub another? [y/N]"
        if ($GoAgain -match "^[Yy]") {
            Invoke-PsChef -Mode "prep" -Pantry "sys" -Ingredient "scrub"
        }
    }
}
else {
    Write-KitchenLog Info "Scrub aborted."
}