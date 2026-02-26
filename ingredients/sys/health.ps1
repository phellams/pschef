<#
.SYNOPSIS
    Audit system health by verifying binaries for all previously prepped items.
.AUTHOR
    @PsChef
#>

# ------------------------------
# pschef required functions
# ------------------------------
$History = Invoke-pschef status -Raw

if($null -eq $History -or $History.Count -eq 0) {
    Write-KitchenLog Warning "Kitchen is pristine. No history to audit."
    return
}
# ------------------------------


Write-KitchenLog Task "Auditing $($History.Count) served dishes..."
$BrokenCount = 0
$CurrentIdx = 0

foreach ($Item in $History) {
    $CurrentIdx++
    # Ensure we actually have an ingredient name
    if ([string]::IsNullOrWhiteSpace($Item.Ingredient)) { continue }
    
    $Binary = $Item.Ingredient
    Show-SousChef -Message "Checking $Binary..." -Current $CurrentIdx -Total $History.Count

    # Perform the check
    if(-not (Get-Command $Binary -ErrorAction SilentlyContinue)) {
        Write-KitchenLog Error "Cold Stove! Dish '$($Item.Pantry)/$Binary' missing from PATH."
        $BrokenCount++
    }
}

Show-SousChef -Message "Audit Complete." -Complete

if($BrokenCount -gt 0) {
    Write-KitchenLog Warning "Found $BrokenCount inconsistencies. Re-prep suggested."
} else {
    Write-KitchenLog Success "All systems nominal. Kitchen is healthy."
}