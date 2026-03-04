<# 
    MODULE NAME: pschef 
    AUTHOR:      @PsChef
    DESCRIPTION: A high-performance developer tool designed to eliminate setup friction.
    LICENSE:     MIT
    REPO:        https://gitlab.com/phellams/pschef
#>

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# ----------------------------------------------------------------------------- 
# SECTION: GLOBAL CONFIGURATION & MULTI-PANTRY SETUP
# =============================================================================

$global:ChefHome = Join-Path $HOME '.phellams' 'pschef'
$global:ChefStateFile = Join-Path $global:ChefHome 'kitchen.state.json'
$global:ChefConfigFile = Join-Path $global:ChefHome 'config.json'

if (-not (Test-Path $global:ChefHome)) { New-Item -Type Directory $global:ChefHome -Force | Out-Null }
if (-not (Test-Path $global:ChefStateFile)) { 
    $InitSchema = @{ Recipes = @{}; Ingredients = @{}; Mise = @{}; Installed = @{}; Uninstalled = @{} }
    $InitSchema | ConvertTo-Json -Depth 5 | Set-Content $global:ChefStateFile -Force 
}

# Initialize default multi-repo config if it doesn't exist
if (-not (Test-Path $global:ChefConfigFile)) {
    $DefaultConfig = @{
        # The array of active folders to search (order matters for overrides)
        ActivePantries = @(
            "pschef-pantry" 
            # "community"
            )
        # The Git remotes to sync during Update-ChefStock
        Repositories = @{
            "pschef-pantry" = "https://gitlab.com/phellams/pschef-pantry.git"
            # "community" = "https://github.com/your-org/community-pantry.git"
        }
    }
    $DefaultConfig | ConvertTo-Json -Depth 5 | Set-Content $global:ChefConfigFile -Force
}

# Load the active pantries array into memory
$global:ChefConfig = Get-Content $global:ChefConfigFile -Raw | ConvertFrom-Json
$global:ChefPantries = $global:ChefConfig.ActivePantries

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# -----------------------------------------------------------------------------
# SECTION: THE ARTISAN PALETTE (256-Color TUI Engine) 
# =============================================================================

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

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# -----------------------------------------------------------------------------
# SECTION: TUI COMPONENTS (Headers, Logs, Progress) ---
# =============================================================================

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
    
    $Meta = @{ 
        name = ""; description = ""; summary = ""; status = "wip"; 
        platform = @(); authors = @(); dependencies = @();
        params = @(); examples = @()
    }
    if (-not (Test-Path $Path)) { return $Meta }

    $Lines = Get-Content $Path
    $InBlock = $false
    $CurrentProp = $null

    foreach ($Line in $Lines) {
        if ($Line -match "^<#") { $InBlock = $true; continue }
        if ($Line -match "^#>") { break }
        
        if ($InBlock) {
            if ($Line -match "^\.([a-zA-Z]+)") {
                $CurrentProp = $Matches[1].ToLower()
            } 
            elseif ($CurrentProp -and -not [string]::IsNullOrWhiteSpace($Line)) {
                # We use a lighter trim here to preserve intentional indentation in examples
                $Val = $Line.TrimEnd().TrimStart() 
                switch ($CurrentProp) {
                    "name" { $Meta.name = $Val }
                    "description" { $Meta.description += if ($Meta.description) { " $Val" } else { $Val } }
                    "status" { $Meta.status = $Val }
                    "platform" { $Meta.platform += ($Val -split ",").Trim() }
                    "authors" { $Meta.authors += ($Val -split ",").Trim() }
                    "dependencies" { $Meta.dependencies += ($Val -split ",").Trim() }
                    "params" { $Meta.params += $Val }
                    "examples" { $Meta.examples += $Val }
                }
            }
        }
    }

    if ($Meta.description) {
        $Meta.summary = if ($Meta.description.Length -gt 80) { $Meta.description.Substring(0, 77) + "..." } else { $Meta.description }
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

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# -----------------------------------------------------------------------------
# SECTION: KITCHEN API (Helpers & Dependencies) ---
# =============================================================================

function Assert-ChefTool {
    <#
    #>
    param([Parameter(Mandatory)][string]$Tool)
    
    if (Get-Command $Tool -ErrorAction SilentlyContinue) { return $true }

    Write-KitchenLog Warning "Stove is cold: Missing '$Tool'."
    
    $FixPath = $null
    foreach ($PantrySource in $global:ChefPantries) {
        $SearchPath = Join-Path $global:ChefHome "$PantrySource\Ingredients"
        if (Test-Path $SearchPath) {
            $Found = Get-ChildItem $SearchPath -Recurse -Filter "$Tool.ps1" | Select-Object -First 1
            if ($null -ne $Found) { 
                $FixPath = $Found
                break 
            }
        }
    }

    if ($null -ne $FixPath) {
        $PantryGroup = $FixPath.Directory.Name
        $IngredientName = $FixPath.BaseName
        Write-KitchenLog Task "Found installer in Pantry: [$PantryGroup/$IngredientName]"
        $Prompt = Read-Host "  Prep this now? [Y/n]"
        if ($Prompt -match "^[Yy]") {
            Invoke-PsChef -Mode "prep" -Pantry $PantryGroup -Ingredient $IngredientName
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
    
    $IndexPath = Join-Path $global:ChefHome "pantry.index.json"
    
    # Auto-Heal: If the cache doesn't exist, build it silently
    if (-not (Test-Path $IndexPath)) {
        Update-ChefIndex
    }
    
    $Cache = Get-Content $IndexPath -Raw | ConvertFrom-Json

    switch ($Category) {
        "Ingredients" {
            if ($null -ne $Cache.Ingredients) {
                $Cache.Ingredients.psobject.Properties | ForEach-Object { $Results += $_.Value }
            }
        }
        "Recipes" {
            if ($null -ne $Cache.Recipes) {
                $Cache.Recipes.psobject.Properties | ForEach-Object { $Results += $_.Value }
            }
        }
        "Mise" {
            if ($null -ne $Cache.Mise) {
                $Cache.Mise.psobject.Properties | ForEach-Object { $Results += $_.Value }
            }
        }
        "Config" {
            if (Test-Path $global:ChefConfigFile) {
                $Cfg = Get-Content $global:ChefConfigFile -Raw | ConvertFrom-Json
                $Cfg.psobject.Properties | ForEach-Object {
                    $Results += [PSCustomObject]@{ Setting = $_.Name; Value = ($_.Value | ConvertTo-Json -Compress) }
                }
            }
        }
    }
    
    # Sort alphabetically by Name for clean TUI rendering
    return $Results | Sort-Object Name
}

function Measure-Ingredient {
    [cmdletbinding()]
    param($Value, $Name="Param") 
    if([string]::IsNullOrWhiteSpace($Value)){ 
        Write-KitchenLog Error "Missing: $Name"; throw "Stop" 
    } 
}

function Resolve-Ingredient {
    param(
        [string]$Pantry, 
        [string]$Ingredient, 
        [switch]$Force
    )
    
    $Catalog = Get-KitchenState -Section "Installed" -Raw
    $Key = "$Pantry/$Ingredient"
    $IsInstalled = $false
    
    if ($null -ne $Catalog) {
        if ($Catalog.psobject.Properties.Match($Key).Count -gt 0) {
            $IsInstalled = $true
        }
    }
    
    if (-not $IsInstalled -or $Force) {
        if ($Force) { Write-KitchenLog Info "Force-prepping $Key..." }
        Invoke-PsChef -Mode "prep" -Pantry $Pantry -Ingredient $Ingredient
    }
}

function Get-Template { 
    param($Name, [hashtable]$Vars = @{}) 
    
    # 1. Check local project override first
    $LocalPath = Join-Path $PWD ".pschef\Mise\$Name"
    
    # 2. Use global resolver if no local override
    $P = if (Test-Path $LocalPath) { $LocalPath } else { Find-ChefResource -Type "Mise" -Name $Name }
    
    if (-not $P -or -not (Test-Path $P)) { throw "Mise Not Found: $Name" }
    
    $C = Get-Content $P -Raw
    foreach ($k in $Vars.Keys) { $C = $C.Replace("{{$k}}", "$($Vars[$k])") }
    return $C 
}

function Set-Table { 
    param($Structure) 
    if(!(Get-Command New-Skeleton -EA SilentlyContinue)){ 
        Write-KitchenLog Error "fissing New-Skeleton"; 
        throw "Stop" 
    }
    Write-KitchenLog Task "Initialize dish parts..."; 
    New-Skeleton -Structure $Structure; 
    Write-KitchenLog Success "Dish parts plated."
}

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# -----------------------------------------------------------------------------
# SECTION: AST CACHING ENGINE
# =============================================================================

function Update-ChefIndex {
    Write-KitchenLog Task "Compiling high-speed AST cache..."
    
    $Index = @{
        Ingredients = @{}
        Recipes     = @{}
        Mise        = @{}
    }

    # Loop backwards so highest priority (index 0) overwrites lower priority during assignment
    for ($i = $global:ChefPantries.Count - 1; $i -ge 0; $i--) {
        $Src = $global:ChefPantries[$i]
        $BasePath = Join-Path $global:ChefHome $Src

        # 1. Index Ingredients
        $IngRoot = Join-Path $BasePath "Ingredients"
        if (Test-Path $IngRoot) {
            Get-ChildItem $IngRoot -Recurse -Filter "*.ps1" | ForEach-Object {
                $PantryGroup = $_.Directory.Name
                $Name = $_.BaseName
                $Key = "$PantryGroup/$Name"
                $Meta = Get-ChefMetadata -Path $_.FullName
                
                # Hashtable assignment automatically deduplicates O(1)
                $Index.Ingredients[$Key] = [PSCustomObject]@{
                    Source = $Src
                    Pantry = $PantryGroup
                    Name   = $Name
                    Author = if ($Meta.authors) { $Meta.authors -join ", " } else { "Unknown" }
                    Desc   = $Meta.summary
                    Tag    = if ($Meta.authors -match "PsChef|Community") { "OFFICIAL" } else { "LOCAL" }
                }
            }
        }

        # 2. Index Recipes
        $RecRoot = Join-Path $BasePath "Recipes"
        if (Test-Path $RecRoot) {
            Get-ChildItem $RecRoot -Filter "*.ps1" | ForEach-Object {
                $Name = $_.BaseName
                $Index.Recipes[$Name] = [PSCustomObject]@{
                    Source = $Src
                    Name   = $Name
                    Desc   = "Executable Recipe Block"
                    Steps  = 0
                }
            }
        }

        # 3. Index Mise
        $MiseRoot = Join-Path $BasePath "Mise"
        if (Test-Path $MiseRoot) {
            Get-ChildItem $MiseRoot -File | ForEach-Object {
                $Name = $_.Name
                $Index.Mise[$Name] = [PSCustomObject]@{
                    Source = $Src
                    Name   = $Name
                    Size   = "$([Math]::Round($_.Length / 1KB, 2)) KB"
                }
            }
        }
    }

    $IndexPath = Join-Path $global:ChefHome "pantry.index.json"
    $Index | ConvertTo-Json -Depth 10 | Set-Content $IndexPath -Force
    
    Write-KitchenLog Success "AST Cache compiled. I/O bottleneck eliminated."
}

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# -----------------------------------------------------------------------------
# SECTION: STATE ENGINE & CATALOG ---
# =============================================================================

function Get-KitchenState {
    param(
        [ValidateSet("Recipes", "Ingredients", "Mise", "Installed", "Uninstalled")] [string]$Section,
        [string]$Item,
        [switch]$Raw
    )
    
    $StateFile = Join-Path $global:ChefHome "kitchen.state.json"
    if (Test-Path $StateFile) { 
        $State = Get-Content $StateFile -Raw | ConvertFrom-Json 
    } else { 
        $State = $null 
    }
    
    # 1. Schema Validation & Repair
    if (-not $State) {
        $State = [PSCustomObject]@{ Recipes = @{}; Ingredients = @{}; Mise = @{}; Installed = @{}; Uninstalled = @{} }
    }
    else {
        foreach ($S in @("Recipes", "Ingrefdients", "Mise", "Installed", "Uninstalled")) {
            if (-not $State.psobject.Properties.Match($S).Count) {
                Add-Member -InputObject $State -MemberType NoteProperty -Name $S -Value @{}
            }
        }
    }

    # 2. Return All Logic
    if (-not $Section) { 
        if ($Raw) { 
        return $State 
        } else { 
            return $State | ConvertTo-Json -Depth 5 
        } 
    }
    
    # 3. Targeted Return Logic
    $Target = $State.$Section
    if ($Item) {
        if ($Target.psobject.Properties.Match($Item).Count) { 
            $Target = $Target.$Item 
        } else { 
            $Target = $null 
        }
    }

    if ($Raw) { return $Target }

    # 4. PsChef Theme Output (when -Raw is not used)
    $P = Get-ChefPalette
    Write-KitchenHeader "STATE QUERY" "Section: $Section $(if($Item){"| Item: $Item"})"
    
    if (-not $Target) {
        Write-KitchenLog Warning "No data found."
    }
    else {
        if ($Item) {
            $Target.psobject.Properties | ForEach-Object { 
                Write-Host "$($P.Rail)│  $($P.Water)● $($P.Steel)$($_.Name.PadRight(15)) $($P.Skillet)$($_.Value)$($P.Reset)" 
            }
        }
        else {
            $Target.psobject.Properties | ForEach-Object { 
                Write-Host "$($P.Rail)│  $($P.Herb)● $($P.Steel)$($_.Name)$($P.Reset)" 
            }
        }
    }
    Write-KitchenFooter "Query Complete"
}

function Set-KitchenState {
    param(
        [Parameter(Mandatory)] [ValidateSet("Recipes", "Ingredients", "Mise", "Installed", "Uninstalled")] [string]$Section,
        [Parameter(Mandatory)] [string]$Item,
        [Parameter(Mandatory)] $Meta,
        [switch]$Raw
    )
    
    $State = Get-KitchenState -Raw
    
    # Attach data safely
    if (-not $State.$Section.psobject.Properties.Match($Item).Count) {
        Add-Member -InputObject $State.$Section -MemberType NoteProperty -Name $Item -Value $Meta
    }
    else {
        $State.$Section.$Item = $Meta
    }

    # Rotation Logic for history sections only
    if ($Section -match "^(Installed|Uninstalled)$") {
        $Max = 100
        $Props = $State.$Section.psobject.Properties
        if ($Props.Count -gt $Max) {
            $Oldest = ($Props | Sort-Object { $_.Value.updatedDate } | Select-Object -First 1).Name
            $State.$Section.psobject.Properties.Remove($Oldest)
        }
    }

    $State | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $global:ChefHome "kitchen.state.json")
    if ($Raw) { return $State.$Section.$Item }
}

function Register-KitchenState {
    param(
        [Parameter(Mandatory)] [ValidateSet("Recipes", "Ingredients", "Mise")] [string]$Section,
        [Parameter(Mandatory)] [string]$Item,
        [Parameter(Mandatory)] [hashtable]$Meta
    )
    
    $Record = [PSCustomObject]@{
        name             = if ($Meta.name) { $Meta.name } else { $Item }
        description      = if ($Meta.description) { $Meta.description } else { "" }
        summary          = if ($Meta.summary) { $Meta.summary } else { "" }
        state            = "available"
        updatedDate      = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        status           = if ($Meta.status) { $Meta.status } else { "wip" }
        platform         = if ($Meta.platform) { @($Meta.platform) } else { @() }
        dependencies     = if ($Meta.dependencies) { @($Meta.dependencies) } else { @() }
        params           = if ($Meta.params) { @($Meta.params) } else { @() }
        examples         = if ($Meta.examples) { @($Meta.examples) } else { @() }
        dependentRecipes = @()
        authors          = if ($Meta.authors) { @($Meta.authors) } else { @() }
    }
    
    Set-KitchenState -Section $Section -Item $Item -Meta $Record | Out-Null
}
# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# -----------------------------------------------------------------------------
# SECTION: INTERACTIVE ENGINE (Viewport Menu) ---
# =============================================================================

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

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# -----------------------------------------------------------------------------
# SECTION: VISUALIZER (Workflow Tree) ---
# =============================================================================

function Show-ChefWorkflow {
    param([string]$RecipeName)
    
    $Path = Find-ChefResource -Type "Recipes" -Name $RecipeName
    if (-not $Path) { 
        Write-KitchenLog Error "Recipe not found across active pantries: $RecipeName"
        return 
    }
    
    $Steps = (& $Path).Sequence
    $P = Get-ChefPalette
    Write-Host "`n$($P.Rail)┌─$($P.Flame) SERVICE FLOW: $($RecipeName.ToUpper()) $($P.Rail)┐$($P.Reset)"
    for ($i = 0; $i -lt $Steps.Count; $i++) {
        $S = $Steps[$i]
        $Last = ($i -eq $Steps.Count - 1)
        $Tree = if ($Last) { "└──" } else { "├──" }
        $Pipe = if ($Last) { "   " } else { "│  " }
        
        $Pms = ""
        if ($S.Params) { $S.Params.Keys | ForEach-Object { $Pms += "$_=$($S.Params[$_]) " } }
        
        Write-Host "$($P.Rail)│  $($P.Skillet)$Tree$($P.Reset) $($P.Brand)[$($i+1)]$($P.Reset) $($P.Success)$($S.Group)/$($S.Action)$($P.Reset) $($P.Steel)($Pms)$($P.Reset)"
        if (-not $Last) { Write-Host "$($P.Rail)│  $($P.Skillet)$Pipe$($P.Reset)" }
    }
    Write-Host "$($P.Rail)└──────────────────────────────┘$($P.Reset)`n"
}

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# -----------------------------------------------------------------------------
# SECTION: MULTI-PANTRY PATH RESOLUTION & REPO MANAGEMENT (Sync)
# =============================================================================

function Find-ChefResource {
    param(
        [ValidateSet("Ingredients", "Recipes", "Mise")] [string]$Type,
        [string]$PantryGroup, # e.g., "sys", "db"
        [string]$Name,        # e.g., "docker", "postgres"
        [switch]$ReturnAll    # Returns all instances for aggregation (like menus)
    )

    $Results = @()
    foreach ($PantrySource in $global:ChefPantries) {
        $BasePath = Join-Path $global:ChefHome $PantrySource
        
        if ($Type -eq "Mise") {
            $Target = Join-Path $BasePath "Mise\$Name"
        }
        elseif ($Type -eq "Recipes") {
            $Target = Join-Path $BasePath "Recipes\$Name.ps1"
        }
        else {
            # Ingredients
            $Target = if ($Name) { Join-Path $BasePath "Ingredients\$PantryGroup\$Name.ps1" } 
            else { Join-Path $BasePath "Ingredients\$PantryGroup" }
        }

        if (Test-Path $Target) {
            if (-not $ReturnAll) { return $Target } # Return first match (Overrides)
            $Results += $Target
        }
    }
    
    if ($ReturnAll) { return $Results }
    return $null
}

function Update-ChefStock {
    <#
    .name Update-ChefStock
    .description
        Syncs all Git repositories defined in config.json into the global ChefHome and compiles the AST cache.
    #>
    Write-KitchenHeader "STOCKING PANTRY" "Syncing remote repositories"

    # POLISH: Prevent raw exceptions if Git is missing
    if (-not (Get-Command "git" -ErrorAction SilentlyContinue)) {
        Write-KitchenLog Error "Git is not installed or not in PATH."
        Write-KitchenLog Task "PsChef requires Git to synchronize remote pantries."
        Write-KitchenFooter "Stocking Failed" "FAIL"
        return
    }
    
    Write-KitchenHeader "STOCKING PANTRY" "Syncing remote repositories"
    $P = Get-ChefPalette
    $Repos = $global:ChefConfig.Repositories.psobject.Properties

    foreach ($Repo in $Repos) {
        $LocalDir = Join-Path $global:ChefHome $Repo.Name
        $RemoteUrl = $Repo.Value

        if (Test-Path $LocalDir) {
            Write-KitchenLog Task "Pulling updates for [$($Repo.Name)]..."
            $Output = Invoke-Expression "git -C `"$LocalDir`" pull origin main 2>&1"
            if ($LASTEXITCODE -eq 0) {
                Write-KitchenLog Success "Synced [$($Repo.Name)]"
            }
            else {
                Write-KitchenLog Error "Failed to sync [$($Repo.Name)]"
            }
        }
        else {
            Write-KitchenLog Task "Cloning new pantry [$($Repo.Name)]..."
            $Output = Invoke-Expression "git clone `"$RemoteUrl`" `"$LocalDir`" 2>&1"
            if ($LASTEXITCODE -eq 0) {
                Write-KitchenLog Success "Cloned [$($Repo.Name)]"
            }
            else {
                Write-KitchenLog Error "Failed to clone [$($Repo.Name)]"
            }
        }
    }
    
    # Trigger the Index Compiler
    Update-ChefIndex
    
    Write-KitchenFooter "Pantry Stocked"
}

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# -----------------------------------------------------------------------------
# SECTION: STOVE API (Helpers, Dashboards) ---
# =============================================================================
function Get-StoveHeader {
    param([string]$App, [string]$Controller)
    $P = Get-ChefPalette
    Write-Host "`n$($P.Rail)┌─$($P.Flame) STOVE CONTROL: $($App.ToUpper()) / $($Controller.ToUpper()) $($P.Rail)─┐$($P.Reset)"
}

function Get-StoveFooter {
    param([string]$Status = "OK")
    $P = Get-ChefPalette
    Write-Host "$($P.Rail)└────────────────────────────────┘ $($P.Brand)[$Status]$($P.Reset)`n"
}

function Get-StoveLogs {
    param([string]$Level, [string]$Message)
    # Similar to Write-KitchenLog, but uses distinct Stove badging
    $P = Get-ChefPalette
    $Badge = switch ($Level) {
        "Info" { "$($P.Water)■$($P.Reset)" }
        "Warn" { "$($P.Wip)▲$($P.Reset)" }
        "Error" { "$($P.Flame)X$($P.Reset)" }
        "Fix" { "$($P.Herb)◆$($P.Reset)" } # Used for auto-fix recommendations
    }
    Write-Host "$($P.Rail)│  $Badge $Message"
}
    
function Get-KitchenDashboard {
    param(
        [Parameter(Mandatory)]
        [scriptblock]$TelemetrySource,
        
        [switch]$Live
    )

    $ESC = [char]27
    $AltBufferEnter = "$ESC[?1049h"
    $AltBufferExit = "$ESC[?1049l"
    $HideCursor = "$ESC[?25l"
    $ShowCursor = "$ESC[?25h"
    $ClearEOL = "$ESC[K" 
    $ClearEOS = "$ESC[J" 
    $Inverse = "$ESC[7m" 
    $Reset = "$ESC[0m"

    try {
        [Console]::Write($AltBufferEnter + $HideCursor)
        [Console]::CursorVisible = $false 

        $IsRunning = $true
        $SelectedIndex = 0
        $ActiveFilterID = $null
        $ViewMode = "Main" # Can be 'Main' or 'Logs'

        while ($IsRunning) {
            # 1. Fetch data. We now pass ViewMode so the controller knows if it needs to fetch heavy logs
            $Data = Invoke-Command -ScriptBlock $TelemetrySource -ArgumentList $ActiveFilterID, $ViewMode

            if ($Data.Containers.Count -gt 0 -and $SelectedIndex -ge $Data.Containers.Count) { 
                $SelectedIndex = [Math]::Max(0, $Data.Containers.Count - 1) 
            }

            [Console]::SetCursorPosition(0, 0)
            $P = Get-ChefPalette
            $TargetID = if ($Data.Containers.Count -gt 0) { $Data.Containers[$SelectedIndex].ID } else { $null }

            # --- RENDER: LOGS MODAL ---
            if ($ViewMode -eq "Logs") {
                [Console]::WriteLine("  $($P.Brand)$($Data.App.ToUpper()) DASHBOARD  >  LOGS: $($Data.ActiveView)$($P.Reset)$ClearEOL")
                [Console]::WriteLine("──────────────────────────────────────────────────────────────$ClearEOL")
                
                # Print the last 20 lines of logs
                if ($Data.Logs) {
                    foreach ($LogLine in $Data.Logs) {
                        # Truncate log lines to prevent terminal wrapping from breaking the UI
                        $SafeLine = if ($LogLine.Length -gt 60) { $LogLine.Substring(0, 57) + "..." } else { $LogLine.PadRight(60) }
                        [Console]::WriteLine("  $($P.Steel)$SafeLine$($P.Reset)$ClearEOL")
                    }
                }
                else {
                    [Console]::WriteLine("  $($P.Wip)No logs available or container is empty.$($P.Reset)$ClearEOL")
                }

                [Console]::WriteLine("──────────────────────────────────────────────────────────────$ClearEOL")
                [Console]::WriteLine("  [Esc] Back to Dashboard  [Q]uit$ClearEOL")
                [Console]::Write($ClearEOS)
            } 
            # --- RENDER: MAIN DASHBOARD ---
            else {
                $ViewTitle = if ($ActiveFilterID) { "$($Data.App.ToUpper()) DASHBOARD  >  $($Data.ActiveView)" } else { "$($Data.App.ToUpper()) DASHBOARD  >  GLOBAL" }
                
                [Console]::WriteLine("  $($P.Brand)$ViewTitle$($P.Reset)  |  Uptime: $($Data.Uptime)$ClearEOL")
                [Console]::WriteLine("──────────────────────────────────────────────────────────────$ClearEOL")
                [Console]::WriteLine("  CPU  $($Data.Charts.CPU)  $($Data.Stats.CPUPct)%$ClearEOL")
                [Console]::WriteLine("  MEM  $($Data.Charts.MEM)  $($Data.Stats.MEMPct)%$ClearEOL")
                [Console]::WriteLine("──────────────────────────────────────────────────────────────$ClearEOL")
                [Console]::WriteLine("  CPU Trend:  $($Data.Charts.CPUSpark)$ClearEOL")
                [Console]::WriteLine("  MEM Trend:  $($Data.Charts.MEMSpark)$ClearEOL")
                [Console]::WriteLine("──────────────────────────────────────────────────────────────$ClearEOL")
                [Console]::WriteLine("  $($P.Steel)CONTAINERS ($($Data.Containers.Count))$($P.Reset)$ClearEOL")
                
                for ($i = 0; $i -lt $Data.Containers.Count; $i++) {
                    $C = $Data.Containers[$i]
                    $RowStyle = if ($i -eq $SelectedIndex) { $Inverse } else { "" }
                    $Pointer = if ($i -eq $SelectedIndex) { "▶" } else { " " }
                    $StatusColor = if ($C.CPU -eq 0 -and $C.MEM -eq 0) { $P.Wip } else { $P.Water } 
                    
                    $NameCol = $C.Name.PadRight(20)
                    $CpuCol = "$($C.CPU)%".PadRight(8)
                    $MemCol = "$($C.MEM)%".PadRight(8)
                    
                    [Console]::WriteLine("$RowStyle  $StatusColor$Pointer$Reset$RowStyle $NameCol CPU: $CpuCol MEM: $MemCol$Reset$ClearEOL")
                }

                [Console]::WriteLine("──────────────────────────────────────────────────────────────$ClearEOL")
                [Console]::WriteLine("  [Q]uit  [Up/Down] Navigate  [Enter] Filter  [L]ogs  [E]xec$ClearEOL")
                [Console]::WriteLine("  [R]estart  [S]top  [P]ause  [D]elete$ClearEOL")
                [Console]::Write($ClearEOS)
            }

            if (-not $Live) { break }

            # --- KEYBOARD ROUTING ---
            if ([Console]::KeyAvailable) {
                $KeyInfo = [Console]::ReadKey($true)

                if ($ViewMode -eq "Logs") {
                    switch ($KeyInfo.Key) {
                        'Escape' { $ViewMode = "Main" }
                        'Q' { $IsRunning = $false }
                    }
                }
                else {
                    switch ($KeyInfo.Key) {
                        'Q' { $IsRunning = $false }
                        'UpArrow' { if ($SelectedIndex -gt 0) { $SelectedIndex-- } }
                        'DownArrow' { if ($SelectedIndex -lt ($Data.Containers.Count - 1)) { $SelectedIndex++ } }
                        'Enter' {
                            if ($ActiveFilterID) { $ActiveFilterID = $null }
                            else { $ActiveFilterID = $TargetID }
                        }
                        'L' { 
                            if ($TargetID) { $ViewMode = "Logs" } 
                        }
                        'E' {
                            if ($TargetID) {
                                # Suspend Dashboard & Drop to Shell
                                [Console]::CursorVisible = $true
                                [Console]::Write($AltBufferExit + $ShowCursor)
                                
                                # Try bash first, fallback to sh if bash is missing
                                Write-Host "`n◆ Entering container shell. Type 'exit' to return to dashboard...`n" -ForegroundColor Cyan
                                docker exec -it $TargetID /bin/sh -c "if command -v bash >/dev/null 2>&1; then bash; else sh; fi"
                                
                                # Resume Dashboard
                                [Console]::Write($AltBufferEnter + $HideCursor)
                                [Console]::CursorVisible = $false
                            }
                        }
                        # Actions dispatched to controller via fire-and-forget
                        'S' { if ($TargetID) { docker stop $TargetID 2>&1 | Out-Null } }
                        'R' { if ($TargetID) { docker restart $TargetID 2>&1 | Out-Null } }
                        'P' { 
                            if ($TargetID) { 
                                # Toggle pause state implicitly
                                $State = docker inspect -f '{{.State.Paused}}' $TargetID
                                if ($State -match "true") { docker unpause $TargetID 2>&1 | Out-Null }
                                else { docker pause $TargetID 2>&1 | Out-Null }
                            } 
                        }
                        'D' { 
                            if ($TargetID) { 
                                docker rm -f $TargetID 2>&1 | Out-Null
                                if ($ActiveFilterID -eq $TargetID) { $ActiveFilterID = $null }
                            } 
                        }
                    }
                }
            }

            Start-Sleep -Milliseconds 500
        }
    }
    finally {
        [Console]::CursorVisible = $true
        [Console]::Write($AltBufferExit + $ShowCursor)
    }
}

function Invoke-StoveDiagnostic {
    param([string]$App, [string]$ErrorOutput)
    
    if ($ErrorOutput -match "permission denied.*docker daemon") {
        Get-StoveLogs "Warn" "Detected socket permission error."
        Get-StoveLogs "Fix" "Suggested Auto-Fix: Add user to docker group."
        
        $Prompt = Read-Host "  Apply fix now? [Y/n]"
        if ($Prompt -match "^[Yy]") {
            # Execute standard PsChef prep for the fix
            chef prep sys docker -Action fix-permissions
            return $true
        }
    }
    return $false
}

function New-StoveGauge {
    param(
        [Parameter(Mandatory)]
        [double]$Percentage,
        
        [int]$Width = 20
    )
    
    # 1. Enforce strict 0-100 bounds
    if ($Percentage -lt 0) { $Percentage = 0 }
    if ($Percentage -gt 100) { $Percentage = 100 }
    
    # 2. Define the exact block characters
    $FillChar = "▓"
    $EmptyChar = "░"
    
    # 3. Calculate blocks based on requested terminal width
    $FilledCount = [Math]::Round(($Percentage / 100) * $Width)
    $EmptyCount = $Width - $FilledCount
    
    # 4. Handle edge cases where math rounding pushes out of bounds
    if ($FilledCount -lt 0) { $FilledCount = 0; $EmptyCount = $Width }
    if ($FilledCount -gt $Width) { $FilledCount = $Width; $EmptyCount = 0 }
    
    $Bar = ($FillChar * $FilledCount) + ($EmptyChar * $EmptyCount)
    
    return "[$Bar]"
}

function New-StoveSparkline {
    param(
        [Parameter(Mandatory)]
        [double[]]$Data,
        
        [int]$MaxWidth = 15
    )
    
    if ($null -eq $Data -or $Data.Count -eq 0) { return "" }
    
    # 1. Truncate array to fit terminal constraints (keep newest data at the end)
    if ($Data.Count -gt $MaxWidth) {
        $Data = $Data[ - $MaxWidth..-1]
    }
    
    # 2. Define the 8-tier Unicode block scale (Lower 1/8 to Full Block)
    $Ticks = @(' ', '▂', '▃', '▄', '▅', '▆', '▇', '█')
    
    # 3. Find boundaries for normalization
    $Min = ($Data | Measure-Object -Minimum).Minimum
    $Max = ($Data | Measure-Object -Maximum).Maximum
    
    # 4. Handle flatlines (no variance in data)
    if ($Min -eq $Max) {
        $Flat = $Ticks[3] * $Data.Count # Default to a mid-line representation
        return $Flat
    }
    
    $Range = $Max - $Min
    $Sparkline = ""
    
    # 5. Normalize and Map
    foreach ($Value in $Data) {
        $Normalized = [Math]::Round((($Value - $Min) / $Range) * ($Ticks.Count - 1))
        $Sparkline += $Ticks[$Normalized]
    }
    
    return $Sparkline
}

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# -----------------------------------------------------------------------------
# SECTION: THE ROUTER (Central Command) ---
# =============================================================================
function Invoke-PsChef {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Position = 0)] 
        [ValidateSet("prep", "cook", "stove", "flow", "status", "stock", "menu-live", "info")]
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
        $W = Get-ChefSize
        
        foreach ($Item in $Data) {
            # Default to Blue if no Tag exists (like Mise/Recipes)
            $TagColor = if ($null -ne $Item.Tag -and $Item.Tag -eq "OFFICIAL") { $P.Herb } else { $P.Water }
            
            $Label = ""
            $Detail = ""
            
            # Dynamically format based on the category's object schema
            switch ($List) {
                "Ingredients" {
                    $Label = "$($Item.Pantry)/$($Item.Name)"
                    $Detail = "[$($Item.Source)] $($Item.Desc)"
                }
                "Recipes" {
                    $Label = $Item.Name
                    $Detail = "[$($Item.Source)] $($Item.Steps) Steps | $($Item.Desc)"
                }
                "Mise" {
                    $Label = $Item.Name
                    $Detail = "[$($Item.Source)] Size: $($Item.Size)"
                }
                "Config" {
                    $Label = $Item.Setting
                    $Detail = $Item.Value
                    $TagColor = $P.Flame # Give config a distinct orange dot
                }
            }
            
            # Truncate detail text to prevent wrapping and breaking the Rail border
            $LabelPad = 25
            $MaxDetailLen = $W - $LabelPad - 10
            if ($Detail.Length -gt $MaxDetailLen -and $MaxDetailLen -gt 0) {
                $Detail = $Detail.Substring(0, $MaxDetailLen - 3) + "..."
            }
            
            Write-Host "$($P.Rail)│  $($TagColor)● $($P.Steel)$($Label.PadRight($LabelPad)) $($P.Skillet)$Detail$($P.Reset)"
        }
        
        $ItemCount = if ($null -ne $Data) { $Data.Count } else { 0 }
        Write-KitchenFooter "$ItemCount items found"
        return
    }
    # Route: Interactive / Menu
    if ($Mode -eq "menu-live" -or (-not $Mode)) {
        
        # Level 1: Aggregate Pantries from ALL sources
        $PantryGroups = @()
        foreach ($Source in $global:ChefPantries) {
            $Root = Join-Path $global:ChefHome "$Source\Ingredients"
            if (Test-Path $Root) {
                $PantryGroups += Get-ChildItem $Root -Directory
            }
        }
        
        # Deduplicate pantry group names (e.g., if 'sys' is in both 'pschef' and 'community')
        $UniqueGroups = $PantryGroups | Select-Object -ExpandProperty Name -Unique
        
        $PantriesData = $UniqueGroups | ForEach-Object { 
            [PSCustomObject]@{ Name = $_; Desc = "View ingredients in $_"; Type = "Pantry" } 
        }
        
        $PantryChoice = Show-ChefInteractiveMenu -Data $PantriesData -Title "PANTRY SELECT" -Subtitle "Aggregated from $global:ChefPantries"
        
        if ($null -ne $PantryChoice) {
            # Level 2: Aggregate Ingredients for the chosen group
            $Items = @()
            foreach ($Source in $global:ChefPantries) {
                $IngRoot = Join-Path $global:ChefHome "$Source\Ingredients\$($PantryChoice.Name)"
                if (Test-Path $IngRoot) {
                    Get-ChildItem $IngRoot -Filter "*.ps1" | ForEach-Object {
                        $Meta = Get-ChefMetadata -Path $_.FullName
                        $Items += [PSCustomObject]@{ 
                            Pantry     = $PantryChoice.Name; 
                            Ingredient = $_.BaseName; 
                            Desc       = "[$Source] $($Meta.summary)"; # Shows which repo it came from
                            Type       = "Ingredient" 
                        }
                    }
                }
            }
            
            # Deduplicate by ingredient name (priority to earlier arrays in config)
            $UniqueItems = $Items | Group-Object Ingredient | ForEach-Object { $_.Group[0] }

            $IngTitle = "INGREDIENTS: $($PantryChoice.Name.ToUpper())"
            $IngChoice = Show-ChefInteractiveMenu -Data $UniqueItems -Title $IngTitle -Subtitle "Select a dish to prep"
            
            if ($null -ne $IngChoice) {
                Invoke-PsChef -Mode "prep" -Pantry $IngChoice.Pantry -Ingredient $IngChoice.Ingredient
            }
            else {
                Invoke-PsChef -Mode "menu-live"
            }
        }
        return
    }

    # Route: Utilities
    switch ($Mode) {
        "info" {
            $Target = if ($Ingredient) { $Ingredient } else { $Pantry }
            
            # 1. Resolve Resource
            $Script = Find-ChefResource -Type "Ingredients" -PantryGroup $Pantry -Name $Target
            $Type = "Ingredient"
            
            if (-not $Script) {
                $Script = Find-ChefResource -Type "Recipes" -Name $Pantry
                $Type = "Recipe"
            }

            if (-not $Script -or -not (Test-Path $Script)) {
                Write-KitchenLog Error "Resource not found: $Pantry / $Target"
                return
            }

            $MetaObj = Get-ChefMetadata -Path $Script

            # --- 1. ANSI Style Definitions ---
            $ESC = [char]27
            $Bold = "$ESC[1m"
            $Italic = "$ESC[3m"
            $Reset = "$ESC[0m"
            
            # Palette
            $cPsChef   = "$ESC[38;5;175m" # Soft Magenta
            $cWip      = "$ESC[38;5;229m" # Pastel Yellow
            $cDone     = "$ESC[38;5;150m" # Pastel Green
            $cVerified = "$ESC[48;5;150m$ESC[38;5;16m$Italic" # Pastel Green BG, Black Text, Italic
            
            $cWin      = "$ESC[38;5;153m" # Pastel Blue
            $cLin      = "$ESC[38;5;255m" # White
            $cOsx      = "$ESC[38;5;183m" # Pastel Purple (OSX Choice)
            
            $cParam    = "$ESC[38;5;159m" # Pastel Cyan
            $cType     = "$ESC[38;5;216m" # Pastel Peach
            $cDesc     = "$ESC[38;5;245m" # Gray
            $cComment  = "$ESC[38;5;240m" # Dark Gray (Code Comments)
            $cCmd      = "$ESC[38;5;111m" # Soft Blue (CLI Commands)

            # --- 2. Data Formatting ---
            $FName = "$Bold$($MetaObj.name)$Reset"
            
            $FAuthors = @()
            foreach ($a in $MetaObj.authors) {
                if ($a -match "@PsChef") { $FAuthors += "$cPsChef$a$Reset" }
                else { $FAuthors += $a }
            }
            
            $Stat = $MetaObj.status.ToLower().Trim()
            $FStatus = switch ($Stat) {
                "wip"      { "$cWip$Stat$Reset" }
                "done"     { "$cDone$Stat$Reset" }
                "verified" { "$cVerified $Stat $Reset" }
                default    { $Stat }
            }

            $FPlats = @()
            foreach ($p in $MetaObj.platform) {
                $pLower = $p.ToLower().Trim()
                if ($pLower -match "win") { $FPlats += "$cWin⦿ $p$Reset" }
                elseif ($pLower -match "linux") { $FPlats += "$cLin⦿ $p$Reset" }
                elseif ($pLower -match "osx|mac") { $FPlats += "$cOsx⦿ $p$Reset" }
                else { $FPlats += $p }
            }

            # --- 3. Render Artisan Info Sheet ---
            Write-KitchenHeader "RESOURCE INFO" "$Type`: $(if ($Type -eq 'Ingredient') {"$Pantry/$Target"} else {$Pantry})"
            $P = Get-ChefPalette

            Write-Host "$($P.Rail)│  $($P.Brand)Name:$($P.Reset)         $FName"
            Write-Host "$($P.Rail)│  $($P.Brand)Authors:$($P.Reset)      $($FAuthors -join ', ')"
            Write-Host "$($P.Rail)│  $($P.Brand)Status:$($P.Reset)       $FStatus"
            Write-Host "$($P.Rail)│  $($P.Brand)Platforms:$($P.Reset)    $($FPlats -join '  ')"
            
            if ($MetaObj.dependencies.Count -gt 0) {
                Write-Host "$($P.Rail)│  $($P.Brand)Dependencies:$($P.Reset) $($MetaObj.dependencies -join ', ')"
            }
            Write-Host "$($P.Rail)│"
            Write-Host "$($P.Rail)│  $($P.Brand)Description:$($P.Reset)"
            Write-Host "$($P.Rail)│  $($P.Steel)$($MetaObj.description)$($P.Reset)"

            if ($MetaObj.params.Count -gt 0) {
                Write-Host "$($P.Rail)│"
                Write-Host "$($P.Rail)│  $($P.Brand)Parameters:$($P.Reset)"
                foreach ($prm in $MetaObj.params) {
                    # Regex match to dynamically split the parameter string
                    if ($prm -match "^\s*(\-[a-zA-Z0-9_]+)\s+<([^>]+)>\s+\-\s+(.*)$") {
                        Write-Host "$($P.Rail)│    $cParam$($Matches[1])$Reset $cType<$($Matches[2])>$Reset $cDesc- $($Matches[3])$Reset"
                    } else {
                        Write-Host "$($P.Rail)│    $cDesc$prm$Reset"
                    }
                }
            }

            if ($MetaObj.examples.Count -gt 0) {
                Write-Host "$($P.Rail)│"
                Write-Host "$($P.Rail)│  $($P.Brand)Examples:$($P.Reset)"
                
                for ($i = 0; $i -lt $MetaObj.examples.Count; $i++) {
                    $ex = $MetaObj.examples[$i]
                    
                    if ($ex -match "^\s*#") {
                        # Format code comments
                        Write-Host "$($P.Rail)│    $cComment$ex$Reset"
                    } else {
                        # Syntax highlight the core CLI command, leave arguments base gray
                        $cmdStr = $ex -replace "(chef\s+prep\s+[a-zA-Z0-9_-]+\s+[a-zA-Z0-9_-]+|chef\s+[a-zA-Z0-9_-]+)", "$cCmd`$1$Reset$cDesc"
                        Write-Host "$($P.Rail)│    $cDesc$cmdStr$Reset"
                        
                        # Inject a blank rail line after an execution line to separate examples
                        if ($i -lt ($MetaObj.examples.Count - 1)) {
                            Write-Host "$($P.Rail)│"
                        }
                    }
                }
            }

            Write-KitchenFooter "EOF"
            return
        }
        "stove" {
            # Syntax: chef stove docker networks -List <networkname>
            $App = $Pantry       # e.g., 'docker'
            $Controller = $Ingredient # e.g., 'networks'
    
            $StoveDir = Join-Path $global:ChefHome "pschef-pantry" "stoves" $App
            $ControllerPath = Join-Path $StoveDir "$Controller.ps1"

            if (-not (Test-Path $ControllerPath)) {
                Write-KitchenLog Error "Stove controller not found: $App / $Controller"
                return
            }

            # Pass the remaining parameters straight through to the controller
            # We use $Params hashtable populated by the dynamic args
            & $ControllerPath @Params
            return
        }
        "flow"   { Show-ChefWorkflow $Pantry; return; }
        "status" {
            # 1. Fetch the targeted catalog section
            $InstalledCatalog = Get-KitchenState -Section "Installed" -Raw
            
            # 2. Handle Pipeline Export
            if ($Raw) { return $InstalledCatalog }

            # 3. Validate Properties
            $Props = if ($null -ne $InstalledCatalog) { $InstalledCatalog.psobject.Properties } else { $null }

            if ($null -eq $Props -or $Props.Count -eq 0) {
                Write-KitchenLog Warning "Kitchen is pristine. No history found."
                return
            }

            # 4. Render the Artisan TUI
            Write-KitchenHeader "KITCHEN STATUS" "Installation History"
            $P = Get-ChefPalette
            
            foreach ($Prop in $Props) {
                $Key = $Prop.Name
                $Details = $Prop.Value
                
                # Visual: Gold dot indicates historical state
                $Dot = "$([char]27)[38;5;221m●" 
                
                # Safely extract the new schema's date format
                $InstallDate = if ($null -ne $Details.updatedDate) { $Details.updatedDate } else { "Unknown" }
                
                Write-KitchenLog Info "$Dot  $($P.Salt)$($Key.PadRight(25)) $($P.Skillet)Installed: $InstallDate"
            }
            
            Write-KitchenFooter "$($Props.Count) Dishes Served"
            return
        }
        "stock"  { Update-ChefStock; return }
        "cook" { 
            $RecipePath = Find-ChefResource -Type "Recipes" -Name $Pantry
            if (-not $RecipePath) {
                Write-KitchenLog Error "Recipe not found across active pantries: $Pantry"
                return
            }

            $Recipe = & $RecipePath
            Write-KitchenHeader "COOKING" $Pantry
            foreach ($S in $Recipe.Sequence) { 
                Invoke-PsChef -Mode "prep" -Pantry $S.Group -Ingredient $S.Action -Params $S.Params 
            }
            Write-KitchenFooter "Recipe Complete" "OK"
            return
        }
    }

    # Route: Prep (The Executioner)
    if ($Mode -eq "prep") {
        $Target = if ($Ingredient) { $Ingredient } else { $Pantry }
        $Script = Find-ChefResource -Type "Ingredients" -PantryGroup $Pantry -Name $Target
        
        if ($null -ne $Script -and (Test-Path $Script)) {
            Write-KitchenHeader "PREP STATION" "$Pantry / $Target"
            try {
                if ($PSCmdlet.ShouldProcess("$Pantry/$Target", "Prep")) {
                    
                    # 1. Parse dependencies using the new Metadata Engine
                    $MetaObj = Get-ChefMetadata -Path $Script
                    
                    if ($null -ne $MetaObj.dependencies -and $MetaObj.dependencies.Count -gt 0) {
                        foreach ($Dep in $MetaObj.dependencies) {
                            if ([string]::IsNullOrWhiteSpace($Dep)) { continue }
                            $Valid = Assert-ChefTool -Tool $Dep
                            if (-not $Valid) { throw "Missing Required Tool: $Dep" }
                        }
                    }

                    # 2. Execute Ingredient
                    & $Script @Params
                    
                    # 3. Inject rich object into the Installed catalog
                    $InstallRecord = [PSCustomObject]@{
                        name        = $Target
                        state       = "installed"
                        updatedDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                        status      = "verified"
                        authors     = $MetaObj.authors
                        params      = $Params -join " "
                    }
                    
                    Set-KitchenState -Section "Installed" -Item "$Pantry/$Target" -Meta $InstallRecord | Out-Null
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

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# -----------------------------------------------------------------------------
# SECTION: COMPLETION & EXPORT ---
# =============================================================================
$ChefCompleter = {
    param($cmd, $param, $word, $ast, $bound)
    
    # We must construct the path manually here because global vars may not be scoped in the completer context
    $IndexPath = Join-Path $HOME ".phellams" "pschef" "pantry.index.json"
    if (-not (Test-Path $IndexPath)) { return }
    
    $Cache = Get-Content $IndexPath -Raw | ConvertFrom-Json
    if ($null -eq $Cache -or $null -eq $Cache.Ingredients) { return }

    if ($param -eq "Pantry") { 
        $Groups = @()
        $Cache.Ingredients.psobject.Properties | ForEach-Object { $Groups += $_.Value.Pantry }
        
        return $Groups | Select-Object -Unique | Sort-Object | Where-Object { $_ -like "$word*" } | ForEach-Object { 
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) 
        }
    }
    
    if ($param -eq "Ingredient" -and $bound.ContainsKey("Pantry")) {
        $Ings = @()
        $TargetPantry = $bound["Pantry"]
        
        $Cache.Ingredients.psobject.Properties | ForEach-Object { 
            if ($_.Value.Pantry -eq $TargetPantry) { $Ings += $_.Value.Name }
        }
        
        return $Ings | Select-Object -Unique | Sort-Object | Where-Object { $_ -like "$word*" } | ForEach-Object { 
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) 
        }
    }
}

Register-ArgumentCompleter -CommandName "invoke-pschef" -ParameterName "Pantry" -ScriptBlock $ChefCompleter
Register-ArgumentCompleter -CommandName "invoke-pschef" -ParameterName "Ingredient" -ScriptBlock $ChefCompleter
Register-ArgumentCompleter -CommandName "pschef" -ParameterName "Pantry" -ScriptBlock $ChefCompleter
Register-ArgumentCompleter -CommandName "pschef" -ParameterName "Ingredient" -ScriptBlock $ChefCompleter
Register-ArgumentCompleter -CommandName "chef" -ParameterName "Pantry" -ScriptBlock $ChefCompleter
Register-ArgumentCompleter -CommandName "chef" -ParameterName "Ingredient" -ScriptBlock $ChefCompleter

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# =============================================================================
# SECTION: EXPORT ---
# =============================================================================
Export-ModuleMember -Function *