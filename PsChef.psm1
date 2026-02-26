# =============================================================================
# FILE: PsChef.psm1
# =============================================================================

$ChefHome = Join-Path $HOME ".phellams" pschef
$GlobalConfigPath = Join-Path $ChefHome "config.json"
if (-not (Test-Path $ChefHome)) { New-Item -Type Directory $ChefHome -Force | Out-Null }

# --- 1. THE ARTISAN PALETTE (256-Color TUI Engine) ---

function Get-ChefPalette {
    $E = [char]27
    return @{
        Reset     = "$E[0m"
        CastIron  = "$E[38;5;234m" # Deep Grey
        Skillet   = "$E[38;5;237m" # Backgrounds
        Steel     = "$E[38;5;245m" # Text
        Rail      = "$E[38;5;239m" # Vertical Line
        Flame     = "$E[38;5;208m" # Orange Accent
        Herb      = "$E[38;5;150m" # Green (OK)
        Berry     = "$E[38;5;197m" # Red (Fail)
        Water     = "$E[38;5;39m"  # Blue (Info)
        Salt      = "$E[38;5;255m" # White
        Gold      = "$E[38;5;221m" # Yellow (Warn)
    }
}

function Get-ChefSize {
    try { $W = $Host.UI.RawUI.WindowSize.Width; return if ($W -gt 100) { 100 } else { $W - 2 } } catch { return 80 }
}

# --- 2. TUI COMPONENTS (Headers, Logs, Progress) ---

function Write-KitchenHeader {
    param([string]$Title, [string]$Subtitle)
    $P = Get-ChefPalette; $W = Get-ChefSize
    Write-Host "`n$($P.Rail)┌─$($P.Flame) $Title $($P.Rail)$('─' * ($W - $Title.Length - 5))┐$($P.Reset)"
    if ($Subtitle) { Write-Host "$($P.Rail)│ $($P.Steel)$Subtitle$(' ' * ($W - $Subtitle.Length - 4))$($P.Rail)│$($P.Reset)" }
    Write-Host "$($P.Rail)├$('─' * ($W - 2))┤$($P.Reset)"
}

function Write-KitchenFooter {
    param([string]$Message, [string]$Status="OK")
    $P = Get-ChefPalette; $W = Get-ChefSize
    $Color = if ($Status -eq "OK") { $P.Herb } else { $P.Berry }
    Write-Host "$($P.Rail)├$('─' * ($W - 2))┤$($P.Reset)"
    $Time = (Get-Date).ToString("HH:mm:ss")
    $Right = [Math]::Max(0, $W - $Message.Length - $Time.Length - 8)
    Write-Host "$($P.Rail)│ $($Color)$Status $($P.Salt)$Message$(' ' * $Right)$($P.Skillet)$Time $($P.Rail)│$($P.Reset)"
    Write-Host "$($P.Rail)└$('─' * ($W - 2))┘$($P.Reset)`n"
}

function Write-KitchenLog {
    param([ValidateSet("Info","Success","Warning","Error","Task","Debug")] $Level, [string]$Message)
    $P = Get-ChefPalette; $T = (Get-Date).ToString("HH:mm")
    $C = @{ Info=@{I="○";C=$P.Water}; Success=@{I="●";C=$P.Herb}; Warning=@{I="▲";C=$P.Gold}; Error=@{I="■";C=$P.Berry}; Task=@{I="│";C=$P.Flame} }[$Level]
    Write-Host "$($P.Rail)│  $($P.Skillet)$T $($C.C)$($C.I)  $($P.Steel)$Message$($P.Reset)"
}

function Show-SousChef {
    param([string]$Message, [int]$Current, [int]$Total, [switch]$Complete)
    $P = Get-ChefPalette; $W = Get-ChefSize; $E = [char]27
    if ($Complete) { Write-Host "`r$E[K" -NoNewline; Write-KitchenLog Success $Message; return }
    $BarSize = 20; $MsgSize = $W - $BarSize - 15
    if ($Message.Length -gt $MsgSize) { $Message = $Message.Substring(0, $MsgSize-3) + "..." }
    $Pct = [Math]::Floor(($Current / $Total) * 100); $Fill = [Math]::Floor(($Pct / 100) * $BarSize)
    $Bar = "$($P.Flame)$('━' * $Fill)$($P.Skillet)$('━' * ($BarSize - $Fill))$($P.Reset)"
    Write-Host "`r$($P.Rail)│  $($P.Flame)>>  $($P.Salt)$($Message.PadRight($MsgSize)) $Bar $($P.Flame)$Pct%$($P.Reset)$E[K" -NoNewline
}

# --- 3. KITCHEN API (Helpers & Dependencies) ---

function Check-Stove {
    param([Parameter(Mandatory)]$Tool)
    if (Get-Command $Tool -ErrorAction SilentlyContinue) { return }
    Write-KitchenLog Warning "The stove is cold! Missing tool: '$Tool'"
    $Fix = Get-ChildItem (Join-Path $PSScriptRoot "Ingredients") -Recurse -Filter "$Tool.ps1" | Select -First 1
    if ($Fix) {
        Write-KitchenLog Task "Found recipe: [$($Fix.Directory.Name)/$($Fix.BaseName)]"
        if ((Read-Host "Prep this now? [Y/n]") -match "^[Yy]") {
            Invoke-PsChef "prep" $Fix.Directory.Name $Fix.BaseName
            if (Get-Command $Tool -ErrorAction SilentlyContinue) { return }
        }
    }
    Write-KitchenLog Error "Critical Dependency Missing: $Tool"; throw "MissingTool"
}

function Measure-Ingredient { param($Value, $Name="Param") if([string]::IsNullOrWhiteSpace($Value)){ Write-KitchenLog Error "Missing: $Name"; throw "Stop" } }

function Require-Ingredient {
    param([string]$Pantry, [string]$Ingredient)
    $S = Get-KitchenState; if (-not $S.Installed."$Pantry/$Ingredient") {
        Write-KitchenLog Warning "Dependency Missing: $Pantry/$Ingredient"; Invoke-PsChef -Mode "prep" -Pantry $Pantry -Ingredient $Ingredient
    }
}

function Fetch-Mise { 
    param($Name, [hashtable]$Vars=@{}) 
    $P = if (Test-Path "$PWD\.pschef\Mise\$Name") { "$PWD\.pschef\Mise\$Name" } else { "$PSScriptRoot\Mise\$Name" }
    if(!(Test-Path $P)){throw "Mise Not Found: $Name"}
    $C = Get-Content $P -Raw; foreach($k in $Vars.Keys){$C = $C.Replace("{{$k}}", "$($Vars[$k])")}; return $C 
}

function Plate-Dish { 
    param($Structure) if(!(Get-Command New-Skeleton -EA SilentlyContinue)){ Write-KitchenLog Error "Missing New-Skeleton"; throw "Stop" }
    Write-KitchenLog Task "Plating dish..."; New-Skeleton -Structure $Structure; Write-KitchenLog Success "Dish Plated."
}

# --- 4. STATE ENGINE ---

function Get-KitchenState {
    $F = Join-Path $ChefHome "kitchen.state.json"; return if (Test-Path $F) { Get-Content $F -Raw | ConvertFrom-Json } else { @{Installed=@{}} }
}

function Set-KitchenState {
    param($Pantry, $Ingredient, $Meta)
    $S = Get-KitchenState; $S.Installed."$Pantry/$Ingredient" = @{ At=(Get-Date).ToString("yyyy-MM-dd HH:mm"); Meta=$Meta }
    $S | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $ChefHome "kitchen.state.json")
}

# --- 5. INTERACTIVE ENGINE (Viewport Menu) ---

function Show-ChefInteractiveMenu {
    param(
        [array]$Data,
        [string]$Title = "KITCHEN MENU",
        [string]$Subtitle = "Select an Item"
    )
    $P = Get-ChefPalette; $W = Get-ChefSize; $Sel = 0; $Max = $Data.Count - 1
    $E = [char]27; $ClearFromCursor = "$E[J"; $HomeCursor = "$E[H"

    try {
        $Host.UI.RawUI.CursorSize = 0
        # Initial Header Draw (Only once to prevent title flicker)
        Clear-Host
        Write-KitchenHeader $Title $Subtitle
        $MenuStartLine = 5 # Adjust based on your header height

        while ($true) {
            # Move cursor to the start of the menu list, not the top of the screen
            Write-Host "$E[$($MenuStartLine);1H" -NoNewline
            
            # Viewport Math
            $H = $Host.UI.RawUI.WindowSize.Height - 12
            $Start = 0
            if ($Sel -ge ($Start + $H)) { $Start = $Sel - $H + 1 }; if ($Sel -lt $Start) { $Start = $Sel }; $End = [Math]::Min(($Start + $H - 1), $Max)

            for ($i = $Start; $i -le $End; $i++) {
                $Itm = $Data[$i]
                # Label depends on if we are looking at Pantries or Ingredients
                $Label = if ($Itm.Name) { $Itm.Name } else { "$($Itm.Pantry)/$($Itm.Ingredient)" }
                $Label = $Label.PadRight(30)
                $D = if ($Itm.Desc) { $Itm.Desc }else { "" }; if ($D.Length -gt ($W - 40)) { $D = $D.Substring(0, ($W - 43)) + "..." }
                
                if ($i -eq $Sel) { 
                    Write-Host "$($P.Rail)│  $($P.Flame)>> $($P.Salt)$Label $($P.Skillet)$D$($P.Reset)$E[K" 
                }
                else { 
                    Write-Host "$($P.Rail)│     $($P.Steel)$Label $($P.Skillet)$D$($P.Reset)$E[K" 
                }
            }
            
            # Fill remaining viewport space with empty rail lines to prevent "ghosting"
            for ($j = ($End - $Start); $j -lt $H; $j++) { Write-Host "$($P.Rail)│$E[K" }
            
            Write-KitchenFooter "Item $($Sel+1) of $($Max+1) | [Esc] Back" "WAIT"

            $K = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            switch ($K.VirtualKeyCode) {
                38 { if ($Sel -gt 0) { $Sel-- }else { $Sel = $Max } } 
                40 { if ($Sel -lt $Max) { $Sel++ }else { $Sel = 0 } } 
                13 { return $Data[$Sel] } 
                27 { return $null } 
            }
        }
    }
    finally { $Host.UI.RawUI.CursorSize = 25 }
}
# --- 6. VISUALIZER (Workflow Tree) ---

function Show-ChefWorkflow {
    param([string]$RecipeName)
    $Path = Join-Path $PSScriptRoot "Recipes\$RecipeName.ps1"; if(!(Test-Path $Path)){return}
    $Steps = (& $Path).Sequence; $P = Get-ChefPalette
    Write-Host "`n$($P.Rail)┌─$($P.Flame) SERVICE FLOW: $($RecipeName.ToUpper()) $($P.Rail)┐$($P.Reset)"
    for ($i=0; $i -lt $Steps.Count; $i++) {
        $S = $Steps[$i]; $Last = ($i -eq $Steps.Count-1); $Tree = if($Last){"└──"}else{"├──"}; $Pipe = if($Last){"   "}else{"│  "}
        $Pms = ""; if($S.Params){$S.Params.Keys|ForEach{$Pms+="$_=$($S.Params[$_]) "}}
        Write-Host "$($P.Rail)│  $($P.Skillet)$Tree$($P.Reset) $($P.Brand)[$($i+1)]$($P.Reset) $($P.Success)$($S.Group)/$($S.Action)$($P.Reset) $($P.Steel)($Pms)$($P.Reset)"
        if(!$Last){Write-Host "$($P.Rail)│  $($P.Skillet)$Pipe$($P.Reset)"}
    }
    Write-Host "$($P.Rail)└──────────────────────────────┘$($P.Reset)`n"
}

# --- 7. REPO MANAGEMENT (Sync) ---

function Update-ChefStock {
    $ConfPath = Join-Path $ChefHome "config.json"; if(!(Test-Path $ConfPath)){return}
    $Conf = Get-Content $ConfPath -Raw | ConvertFrom-Json; $Cache = Join-Path (Split-Path $PSScriptRoot -Parent) "pschief-pantry"
    foreach ($Repo in $Conf.Global.Pantry) {
        $Local = Join-Path $Cache (($Repo -split "/")[-1] -replace ".git","")
        if (Test-Path $Local) { Set-Location $Local; git pull | Out-Null } else { git clone $Repo $Local | Out-Null }
        foreach ($f in @("Ingredients", "Recipes", "Mise")) {
            $Src = Join-Path $Local $f; if(Test-Path $Src){ Copy-Item "$Src\*" (Join-Path $PSScriptRoot $f) -Recurse -Force }
        }
    }
    Write-KitchenLog Success "Pantry stocked from community repos."
}

# --- 8. THE ROUTER (Central Command) ---

function Invoke-PsChef {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Position=0)] [string]$Mode,       # prep, cook, menu, flow, status, stock
        [Parameter(Position=1)] [string]$Pantry,     
        [Parameter(Position=2)] [string]$Ingredient, 
        [Parameter(ValueFromRemainingArguments)] [string[]]$Params
    )

    $Root = Join-Path $PSScriptRoot "Ingredients"

    # Route: Interactive / Menu
    if ($Mode -eq "menu-live" -or (-not $Mode)) {
        # 1. Level 1: Select Pantry
        $Pantries = Get-ChildItem $Root -Directory | ForEach-Object { 
            [PSCustomObject]@{ Name = $_.Name; Desc = "View all ingredients in $($_.Name)"; Type = "Pantry" } 
        }
        
        $PantryChoice = Show-ChefInteractiveMenu -Data $Pantries -Title "PANTRY SELECT"
        
        if ($PantryChoice) {
            # 2. Level 2: Select Ingredient in that Pantry
            $Items = Get-ChildItem (Join-Path $Root $PantryChoice.Name) -Filter "*.ps1" | ForEach-Object {
                $D = "No Desc"; Get-Content $_.FullName -Total 10 | ForEach { if ($_ -match "\.SYNOPSIS\s+(.*)") { $D = $Matches[1] } }
                [PSCustomObject]@{ Pantry = $PantryChoice.Name; Ingredient = $_.BaseName; Desc = $D; Type = "Ingredient" }
            }
            
            $IngChoice = Show-ChefInteractiveMenu -Data $Items -Title "INGREDIENT: $($PantryChoice.Name.ToUpper())"
            
            if ($IngChoice) {
                Invoke-PsChef -Mode "prep" -Pantry $IngChoice.Pantry -Ingredient $IngChoice.Ingredient
            }
            else {
                # If User Escaped, go back to Level 1
                Invoke-PsChef -Mode "menu-live"
            }
        }
        return
    }

    # Route: Utilities
    switch ($Mode) {
        "flow"   { Show-ChefWorkflow $Pantry; return }
        "status" { Get-KitchenState | ForEach-Object { $_.Installed.Keys | ForEach { [PSCustomObject]@{Dish=$_; At=$_.At} } } | Format-Table -AutoSize; return }
        "stock"  { Update-ChefStock; return }
        "cook"   { 
            $Recipe = & (Join-Path $PSScriptRoot "Recipes\$Pantry.ps1")
            Write-KitchenHeader "COOKING" $Pantry
            foreach ($S in $Recipe.Sequence) { Invoke-PsChef -Mode "prep" -Pantry $S.Group -Ingredient $S.Action -Params $S.Params }
            Write-KitchenFooter "Recipe Complete" "OK"; return
        }
    }

    # Route: Prep (The Executioner)
    if ($Mode -eq "prep") {
        $Target = if($Ingredient){$Ingredient}else{$Pantry}; $Script = Join-Path $Root "$Pantry\$Target.ps1"
        if (Test-Path $Script) {
            Write-KitchenHeader "PREP STATION" "$Pantry / $Target"
            try {
                if ($PSCmdlet.ShouldProcess("$Pantry/$Target", "Prep")) {
                    # Dependency Parsing
                    Get-Content $Script -Total 20 | ForEach { if($_ -match "\.DEPENDENCIES\s+(.*)") { ($Matches[1] -split ",").Trim() | ForEach { Check-Stove $_ } } }
                    & $Script @Params
                    Set-KitchenState $Pantry $Target @{Params=$Params}
                    Write-KitchenFooter "Dish Plated" "OK"
                }
            } catch { Write-KitchenLog Error $_.Exception.Message; Write-KitchenFooter "Chef Error" "FAIL" }
        } else { Write-KitchenLog Error "Ingredient not found." }
    }
}

# --- 9. COMPLETION & EXPORT ---
$ChefCompleter = {
    param($cmd, $param, $word, $ast, $bound)
    $Root = Join-Path $PSScriptRoot "Ingredients"
    if ($param -eq "Pantry") { return Get-ChildItem $Root -Directory | Where Name -like "$word*" | ForEach { [System.Management.Automation.CompletionResult]::new($_.Name, $_.Name, 'ParameterValue', $_.Name) } }
    if ($param -eq "Ingredient" -and $bound.ContainsKey("Pantry")) {
        $P = Join-Path $Root $bound["Pantry"]; if (Test-Path $P) { return Get-ChildItem $P -Filter "*.ps1" | Where BaseName -like "$word*" | ForEach { [System.Management.Automation.CompletionResult]::new($_.BaseName, $_.BaseName, 'ParameterValue', $_.BaseName) } }
    }
}
Register-ArgumentCompleter -CommandName "chef" -ParameterName "Pantry" -ScriptBlock $ChefCompleter
Register-ArgumentCompleter -CommandName "chef" -ParameterName "Ingredient" -ScriptBlock $ChefCompleter

Export-ModuleMember -Function *