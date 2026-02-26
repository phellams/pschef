<#
.DESCRIPTION
    Installs WSL2 and applies optimized memory/processor constraints.
.AUTHOR
    @sgkens
.DEPENDENCIES
    wsl
#>
param([string]$Distro = "Ubuntu")

Check-Stove "wsl"
Measure-Ingredient $Distro "Linux Distribution"

Show-SousChef -Message "Provisioning $Distro..." -Current 20 -Total 100

# Install logic
wsl --install -d $Distro --web-download

# Apply global .wslconfig from Mise
$Conf = Fetch-Mise "wslconfig.tmplt" @{ Mem = "4GB"; Cpu = "2" }
$Path = Join-Path $env:USERPROFILE ".wslconfig"
$Conf | Set-Content $Path

Show-SousChef -Message "WSL Environment Ready. Reboot required." -Complete