$ChefHome = Join-Path $HOME ".phellams" pschef
$GlobalConfigPath = Join-Path $ChefHome "config.json"
if (-not (Test-Path $ChefHome)) { New-Item -Type Directory $ChefHome -Force | Out-Null }

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

function Write-KitchenFooter {
    param([string]$Message, [string]$Status = "OK")
    $P = Get-ChefPalette; $W = Get-ChefSize
    $Color = if ($Status -eq "OK") { $P.Herb } else { $P.Berry }
    
    $Line1 = "$($P.Rail)├$('─' * ($W - 2))┤$($P.Reset)`n"
    
    $Time = (Get-Date).ToString("HH:mm:ss")
    $RightPad = $W - $Message.Length - $Time.Length - 9
    $Line2 = "$($P.Rail)│ $($Color)$Status $($P.Salt)$Message$(' ' * $RightPad)$($P.Skillet)$Time $($P.Rail)│$($P.Reset)`n"
    $Line3 = "$($P.Rail)└$('─' * ($W - 2))┘$($P.Reset)"

    # Blast the whole footer at once
    [Console]::Write($Line1 + $Line2 + $Line3)
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

# --- STATE ENGINE ---

function Get-KitchenState {
    $F = Join-Path $ChefHome "kitchen.state.json"; return if (Test-Path $F) { Get-Content $F -Raw | ConvertFrom-Json } else { @{Installed=@{}} }
}

function Set-KitchenState {
    param($Pantry, $Ingredient, $Meta)
    $S = Get-KitchenState; $S.Installed."$Pantry/$Ingredient" = @{ At=(Get-Date).ToString("yyyy-MM-dd HH:mm"); Meta=$Meta }
    $S | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $ChefHome "kitchen.state.json")
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
                $Label = (if ($Itm.Type -eq "Pantry") { $Itm.Name } else { $Itm.Ingredient }).PadRight(25)
                $Desc = if ($Itm.Desc) { $Itm.Desc } else { "---" }
                if ($Desc.Length -gt ($W - 35)) { $Desc = $Desc.Substring(0, ($W - 38)) + "..." }
                
                # 2. ADD TO BUFFER (Using ANSI for colors)
                if ($i -eq $Sel) { 
                    [void]$Buffer.AppendLine("$($P.Rail)│  $($P.Flame)>> $($P.Salt)$Label $($P.Skillet)$Desc$($P.Reset)$E[K") 
                } else { 
                    [void]$Buffer.AppendLine("$($P.Rail)│     $($P.Steel)$Label $($P.Skillet)$Desc$($P.Reset)$E[K") 
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
        # Level 1: Pantries
        $Pantries = Get-ChildItem $Root -Directory | ForEach-Object { 
            [PSCustomObject]@{ Name = $_.Name; Desc = "View contents of the $($_.Name) pantry."; Type = "Pantry" } 
        }
        
        $PantryChoice = Show-ChefInteractiveMenu -Data $Pantries -Title "PANTRY SELECT" -Subtitle "Drill down into a category"
        
        if ($PantryChoice) {
            # Level 2: Ingredients
            $Items = Get-ChildItem (Join-Path $Root $PantryChoice.Name) -Filter "*.ps1" | ForEach-Object {
                $Meta = Get-ChefMetadata -Path $_.FullName
                [PSCustomObject]@{ Pantry = $PantryChoice.Name; Ingredient = $_.BaseName; Desc = $Meta.Desc; Type = "Ingredient" }
            }
            
            $IngChoice = Show-ChefInteractiveMenu -Data $Items -Title "INGREDIENTS: $($PantryChoice.Name.ToUpper())" -Subtitle "Select a dish to prep"
            
            if ($IngChoice) {
                Invoke-PsChef -Mode "prep" -Pantry $IngChoice.Pantry -Ingredient $IngChoice.Ingredient
            }
            else {
                Invoke-PsChef -Mode "menu-live" # Recurse back to start
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