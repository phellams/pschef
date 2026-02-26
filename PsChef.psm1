<# MODULE NAME: pschef #>

# ....../ SECTION: CONFIGURATION
# ___________________________________________________________
# NOTE: change config path to global so recepies, ingredients can be shared across projects
$global:ChefHome = Join-Path $HOME ".phellams" 'pschef'
$global:ChefConfigFile = Join-Path $global:ChefHome "kitchen.state.json"
# Test Config file path and create config file if doesnt exist
if (-not (Test-Path $global:ChefHome)) { New-Item -Type Directory $global:ChefHome -Force | Out-Null }
if (-not (Test-Path $global:ChefConfigFile)) { New-Item -Type file $global:ChefConfigFile -Force | Out-Null }

# ....../ SECTION: THE ARTISAN PALETTE (256-Color TUI Engine) 
# ___________________________________________________________

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

# ....../ SECTION: TUI COMPONENTS (Headers, Logs, Progress) ---
# _____________________________________________________________

function Write-KitchenHeader {
    param([string]$Title, [string]$Subtitle)
    $P = Get-ChefPalette; $W = Get-ChefSize
    
    # Fix: Corrected dash length to prevent overhanging right border
    $DashLen = $W - $Title.Length - 5
    Write-Host "`n$($P.Rail)┌─$($P.Flame) $Title $($P.Rail)$('─' * $DashLen)┐$($P.Reset)"
    
    if ($Subtitle) { 
        # Fix: Adjusted padding to account for the border character
        $SubPad = $W - $Subtitle.Length - 3
        Write-Host "$($P.Rail)│ $($P.Steel)$Subtitle$(' ' * $SubPad)$($P.Rail)│$($P.Reset)" 
    }
    Write-Host "$($P.Rail)├$('─' * ($W - 2))┤$($P.Reset)"
}

function Write-KitchenFooter {
    param([string]$Message, [string]$Status="OK")
    $P = Get-ChefPalette; $W = Get-ChefSize
    $Color = if ($Status -eq "OK") { $P.Herb } else { $P.Berry }
    
    Write-Host "$($P.Rail)├$('─' * ($W - 2))┤$($P.Reset)"
    
    $Time = (Get-Date).ToString("HH:mm:ss")
    # Fix: Offset -1 to fix the right-side alignment of the footer border
    $RightPad = $W - $Message.Length - $Time.Length - 9
    
    Write-Host "$($P.Rail)│ $($Color)$Status $($P.Salt)$Message$(' ' * $RightPad)$($P.Skillet)$Time $($P.Rail)│$($P.Reset)"
    Write-Host "$($P.Rail)└$('─' * ($W - 2))┘$($P.Reset)`n"
}

function Get-ChefMetadata {
    param([string]$Path)
    $Meta = @{ Desc = "No description provided."; Author = "Chef" }
    if (-not (Test-Path $Path)) { return $Meta }

    $Content = Get-Content $Path -TotalCount 30
    # Search for .SYNOPSIS or .DESC or .DESCRIPTION
    foreach ($Line in $Content) {
        if ($Line -match "\.(SYNOPSIS|DESC|DESCRIPTION)\s+(.*)") {
            $Meta.Desc = $Matches[2].Trim()
            break
        }
        if ($Line -match "\.AUTHOR\s+(.*)") {
            $Meta.Author = $Matches[1].Trim()
        }
    }
    return $Meta
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

# --- KITCHEN API (Helpers & Dependencies) ---

function Assert-ChefTool {
    param([Parameter(Mandatory)][string]$Tool)
    
    if (Get-Command $Tool -ErrorAction SilentlyContinue) {
        return $true
    }

    Write-KitchenLog Warning "Stove is cold: Missing '$Tool'."
    
    # Self-Healing Search
    $Fix = Get-ChildItem (Join-Path $PSScriptRoot "Ingredients") -Recurse -Filter "$Tool.ps1" | Select-Object -First 1
    if ($Fix) {
        Write-KitchenLog Task "Found installer in Pantry: [$($Fix.Directory.Name)/$($Fix.BaseName)]"
        $Prompt = Read-Host "  Prep this now? [Y/n]"
        if ($Prompt -match "^[Yy]") {
            Invoke-PsChef -Mode "prep" -Pantry $Fix.Directory.Name -Ingredient $Fix.BaseName
            if (Get-Command $Tool -ErrorAction SilentlyContinue) { return $true }
        }
    }
    
    Write-KitchenLog Error "Critical tool '$Tool' is not installed."
    return $false
}

function Get-ChefRegistry {
    param(
        [Parameter(Mandatory)]
        [ValidateSet("Ingredients", "Recipes", "Mise", "Config")]
        [string]$Category
    )

    $P = Get-ChefPalette
    $Results = @()

    switch ($Category) {
        "Ingredients" {
            Get-ChildItem (Join-Path $PSScriptRoot "Ingredients") -Recurse -Filter "*.ps1" | ForEach-Object {
                $Meta = Get-ChefMetadata -Path $_.FullName
                $Results += [PSCustomObject]@{
                    Pantry = $_.Directory.Name
                    Name   = $_.BaseName
                    Author = $Meta.Author
                    Desc   = $Meta.Desc
                    Tag    = if ($Meta.Author -match "PsChef|Community") { "OFFICIAL" } else { "LOCAL" }
                }
            }
        }
        "Recipes" {
            Get-ChildItem (Join-Path $PSScriptRoot "Recipes") -Filter "*.ps1" | ForEach-Object {
                $Content = & $_.FullName
                $Results += [PSCustomObject]@{
                    Name  = $_.BaseName
                    Desc  = $Content.Description
                    Steps = $Content.Sequence.Count
                }
            }
        }
        "Mise" {
            Get-ChildItem (Join-Path $PSScriptRoot "Mise") | ForEach-Object {
                $Results += [PSCustomObject]@{ Name = $_.Name; Size = "$([Math]::Round($_.Length / 1KB, 2)) KB" }
            }
        }
        "Config" {
            if (Test-Path $GlobalConfigPath) {
                $Cfg = Get-Content $global:ChefConfigFile | ConvertFrom-Json
                $Cfg.psobject.Properties | ForEach-Object {
                    $Results += [PSCustomObject]@{ Setting = $_.Name; Value = $_.Value }
                }
            }
        }
    }
    return $Results
}

function Measure-Ingredient { 
    param($Value, $Name="Param") 
    if([string]::IsNullOrWhiteSpace($Value)){ 
        Write-KitchenLog Error "Missing: $Name"; throw "Stop" } }

function Require-Ingredient {
    param([string]$Pantry, [string]$Ingredient, [switch]$Force)
    
    $S = Get-KitchenState
    $IsInstalled = $null -ne $S.Installed."$Pantry/$Ingredient"
    
    if (-not $IsInstalled -or $Force) {
        if ($Force) { Write-KitchenLog Info "Force-prepping $Pantry/$Ingredient..." }
        Invoke-PsChef -Mode "prep" -Pantry $Pantry -Ingredient $Ingredient
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

# --- STATE ENGINE ---

function Get-KitchenState {
    param([switch]$AsList)
    
    if (-not (Test-Path $global:ChefHome -ErrorAction SilentlyContinue)) { New-Item -Type Directory $global:ChefHome -Force | Out-Null }

    $StateFile = Join-Path $global:ChefHome "kitchen.state.json"
    if (-not (Test-Path $StateFile -ErrorAction SilentlyContinue)) { 
        if ($AsList) { 
            return @() 
        } else { 
            @{ Installed = @{} } 
        } 
    }

    $RawState = Get-Content $StateFile -Raw | ConvertFrom-Json 

    if ($AsList) {
        $List = @()
        # Use psobject to iterate safely
        foreach ($Prop in $RawState.Installed.psobject.Properties) {
            $Key = $Prop.Name
            $Entry = $Prop.Value
            
            # SAFE SPLIT: Ensure we have both halves
            $Parts = $Key -split "/"
            if ($Parts.Count -lt 2) { continue } # Skip malformed keys

            $List += [PSCustomObject]@{
                Pantry     = $Parts[0]
                Ingredient = $Parts[1] # This was likely null/empty
                Installed  = $Entry.At
                Params     = if ($Entry.Meta.Params) { $Entry.Meta.Params -join " " } else { "" }
                Tag        = "HISTORY"
            }
            # Auto Fix binarie
            # NOTE: add in below logic for auto-fix health restore
            # if (-not (Get-Command $Binary -ErrorAction SilentlyContinue)) {
            #     Write-KitchenLog Error "Missing: $Binary"
            #     if ($AutoFix) {
            #         Write-KitchenLog Task "Auto-fixing: $Binary..."
            #         Invoke-PsChef -Mode "prep" -Pantry $Item.Pantry -Ingredient $Item.Ingredient -Force
            #     }
            # }
        }
        return $List
    }
    return $RawState
}

function Set-KitchenState {
    param(
        [Parameter(Mandatory)] [string]$Pantry,
        [Parameter(Mandatory)] [string]$Ingredient,
        [Parameter(Mandatory)] [hashtable]$Meta
    )
    
    # Load existing state
    $S = Get-KitchenState
    
    # Add or Update the entry
    # check - if key doesnt exist, create it
    if (-not $S.Installed.psobject.Properties.Name.Contains($Key)) {
        $S.Installed.psobject.Properties.Add($Key, @{ At = (Get-Date).ToString("yyyy-MM-dd HH:mm"); Meta = $Meta })
    }

    $Key = "$Pantry/$Ingredient"
    $S.Installed.$Key = @{ 
        At   = (Get-Date).ToString("yyyy-MM-dd HH:mm")
        Meta = $Meta 
    }
    
    # ROTATION LOGIC: Maintain only the 100 most recent entries
    $MaxEntries = 100
    $Properties = $S.Installed.psobject.Properties
    
    if ($Properties.Count -gt $MaxEntries) {
        # Sort by the 'At' date string and pick the oldest one to remove
        $OldestKey = ($Properties | Sort-Object { $_.Value.At } | Select-Object -First 1).Name
        $S.Installed.psobject.Properties.Remove($OldestKey)
    }
    
    # Save back to disk
    $S | ConvertTo-Json -Depth 5 | Set-Content -Path $global:ChefConfigFile
}

# --- INTERACTIVE ENGINE (Viewport Menu) ---

function Show-ChefInteractiveMenu {
    param(
        [array]$Data,
        [string]$Title = "KITCHEN MENU",
        [string]$Subtitle = "Select an Item"
    )
    $P = Get-ChefPalette; $W = Get-ChefSize; $Sel = 0; $Max = $Data.Count - 1
    $E = [char]27
    $MenuStartLine = 5 

    try {
        $Host.UI.RawUI.CursorSize = 0
        Clear-Host
        # The Header is static, draw it once.
        Write-KitchenHeader $Title $Subtitle
        
        while ($true) {
            # Move cursor to start of menu area
            Write-Host "$E[$($MenuStartLine);1H" -NoNewline
            
            # 1. INITIALIZE STRING BUNDLE
            $Buffer = New-Object System.Text.StringBuilder
            
            $H = $Host.UI.RawUI.WindowSize.Height - 12
            $Start = 0
            if ($Sel -ge ($Start + $H)) { $Start = $Sel - $H + 1 }; if ($Sel -lt $Start) { $Start = $Sel }; $End = [Math]::Min(($Start + $H - 1), $Max)

            for ($i = $Start; $i -le $End; $i++) {
                $Itm = $Data[$i]
    
                # Standardize Label resolving
                $RawLabel = if ($Itm.Type -eq "Pantry") { $Itm.Name } else { $Itm.Ingredient }
                $Label = "$RawLabel".PadRight(25)

                $DisplayDesc = if ($null -ne $Itm.Desc) { $Itm.Desc } else { "---" }
                if ($DisplayDesc.Length -gt ($W - 35)) { $DisplayDesc = $DisplayDesc.Substring(0, ($W - 38)) + "..." }
    
                if ($i -eq $Sel) { 
                    [void]$Buffer.AppendLine("$($P.Rail)│  $($P.Flame)>> $($P.Salt)$Label $($P.Skillet)$DisplayDesc$($P.Reset)$E[K") 
                }
                else { 
                    [void]$Buffer.AppendLine("$($P.Rail)│     $($P.Steel)$Label $($P.Skillet)$DisplayDesc$($P.Reset)$E[K") 
                }
            }
            
            # Fill empty space in viewport
            for ($j = ($End - $Start); $j -lt $H; $j++) { [void]$Buffer.AppendLine("$($P.Rail)│$E[K") }
            
            # 3. BLAST THE BUFFER TO CONSOLE
            # This is significantly faster than multiple Write-Host calls
            Write-Host $Buffer.ToString() -NoNewline

            Write-KitchenFooter "Item $($Sel+1) of $($Max+1) | [Esc] Back" "WAIT"

            $K = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            switch ($K.VirtualKeyCode) {
                38 { if($Sel -gt 0){$Sel--}else{$Sel=$Max} } 
                40 { if($Sel -lt $Max){$Sel++}else{$Sel=0} } 
                13 { return $Data[$Sel] } 
                27 { return $null } 
            }
        }
    } finally { $Host.UI.RawUI.CursorSize = 25 }
}

# --- VISUALIZER (Workflow Tree) ---

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

# --- REPO MANAGEMENT (Sync) ---

function Update-ChefStock {
    [cmdletbinding()]
    param()
    $ConfPath = Join-Path $global:ChefHome "config.json"; if(!(Test-Path $ConfPath)){return}
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

# --- THE ROUTER (Central Command) ---

function Invoke-PsChef {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Position = 0)] 
        [ValidateSet("prep", "cook", "flow", "status", "stock", "menu-live")]
        [string]$Mode,

        [Parameter(Position = 1)] [string]$Pantry,
        [Parameter(Position = 2)] [string]$Ingredient,

        [Parameter(ValueFromRemainingArguments)] [string[]]$Params,

        # New Params for v2.4
        [ValidateSet("Ingredients", "Recipes", "Mise", "Config")]
        [string]$List,
        [switch]$Raw
    )

    $Root = Join-Path $PSScriptRoot "Ingredients"
    # Handle List Requests
    if ($List) {
        $Data = Get-ChefRegistry -Category $List
        
        if ($Raw) { return $Data }

        # ANSI Rendered List
        Write-KitchenHeader "REGISTRY: $List" "System Audit"
        $P = Get-ChefPalette
        foreach ($Item in $Data) {
            $TagColor = if ($Item.Tag -eq "OFFICIAL") { $P.Herb } else { $P.Water }
            $Label = if ($List -eq "Ingredients") { "$($Item.Pantry)/$($Item.Name)" } else { $Item.Name }
            
            Write-Host "$($P.Rail)│  $($TagColor)● $($P.Steel)$($Label.PadRight(25)) $($P.Skillet)$($Item.Desc)$($P.Reset)"
        }
        Write-KitchenFooter "$($Data.Count) items found"
        return
    }
    # Route: Interactive / Menu
    if ($Mode -eq "menu-live" -or (-not $Mode)) {
        
        # Level 1: Pantries
        $Pantries = Get-ChildItem $Root -Directory | ForEach-Object { 
            [PSCustomObject]@{ 
                Name = $_.Name; 
                Desc = "View all ingredients in $($_.Name)"; 
                Type = "Pantry" 
            } 
        }
        
        $PantryChoice = Show-ChefInteractiveMenu -Data $Pantries -Title "PANTRY SELECT" -Subtitle "Drill down into a category"
        
        if ($null -ne $PantryChoice) {
            # Level 2: Ingredients
            $PantryPath = Join-Path $Root $PantryChoice.Name
            $Items = Get-ChildItem $PantryPath -Filter "*.ps1" | ForEach-Object {
                $Meta = Get-ChefMetadata -Path $_.FullName
                [PSCustomObject]@{ 
                    Pantry = $PantryChoice.Name; 
                    Ingredient = $_.BaseName; 
                    Desc = $Meta.Desc; 
                    Type = "Ingredient" 
                }
            }
            
            $IngTitle = "INGREDIENTS: $($PantryChoice.Name.ToUpper())"
            $IngChoice = Show-ChefInteractiveMenu -Data $Items -Title $IngTitle -Subtitle "Select a dish to prep"
            
            if ($null -ne $IngChoice) {
                # Recursively call prep
                Invoke-PsChef -Mode "prep" -Pantry $IngChoice.Pantry -Ingredient $IngChoice.Ingredient
            } else {
                # Go back to main menu on ESC
                Invoke-PsChef -Mode "menu-live"
            }
        }
        return
    }

    # Route: Utilities
    switch ($Mode) {
        "flow"   { Show-ChefWorkflow $Pantry; return; }
        "status" {
            $History = Get-KitchenState -AsList
            
            if ($Raw) { return $History }

            if ($History.Count -eq 0) {
                Write-KitchenLog Warning "Kitchen is pristine. No history found."
                return
            }

            Write-KitchenHeader "KITCHEN STATUS" "Installation History"
            $P = Get-ChefPalette
            
            foreach ($Item in $History) {
                # Visual: History uses a Gold dot to distinguish from Official/Local
                $Dot = "$([char]27)[38;5;221m●" 
                $Label = "$($Item.Pantry)/$($Item.Ingredient)"
                
                Write-KitchenLog Info "$Dot  $([char]27)[38;5;255m$($Label.PadRight(25)) $([char]27)[38;5;239mInstalled: $($Item.Installed)"
            }
            
            Write-KitchenFooter "$($History.Count) Dishes Served"
            return
        }
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
        $Target = if ($Ingredient) { $Ingredient } else { $Pantry }
        $Script = Join-Path $Root "$Pantry\$Target.ps1"
    
        if (Test-Path $Script) {
            Write-KitchenHeader "PREP STATION" "$Pantry / $Target"
            try {
                if ($PSCmdlet.ShouldProcess("$Pantry/$Target", "Prep")) {
                
                    # FIX: Explicitly handle dependency parsing to avoid 'if' cmd errors
                    $Metadata = Get-Content $Script -TotalCount 30
                    foreach ($Line in $Metadata) {
                        if ($Line -match "\.DEPENDENCIES\s+(.*)") {
                            $DepList = ($Matches[1] -split ",").Trim()
                            foreach ($Dep in $DepList) {
                                # Use the new v2.4 Assertion
                                $Valid = Assert-ChefTool -Tool $Dep
                                if (-not $Valid) { throw "Missing Required Tool: $Dep" }
                            }
                        }
                    }

                    # Execute Ingredient
                    & $Script @Params
                    Set-KitchenState -Pantry $Pantry -Ingredient $Target -Meta @{Params = $Params }
                    break;
                    Write-KitchenFooter "Dish Plated" "OK"
                }
            }
            catch {
                Write-KitchenLog Error $_.Exception.Message
                Write-KitchenFooter "Chef Error" "FAIL"
            }
        }
        else {
            Write-KitchenLog Error "Ingredient '$Pantry/$Target' not found."
        }
    }
}

# --- COMPLETION & EXPORT ---
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