<#
.SYNOPSIS
    Installs Docker Engine on Linux guests via official curl script.
.AUTHOR
    @Community
.DEPENDENCIES
    curl, sudo
#>
Assert-ChefTool "curl"

Show-SousChef -Message "Downloading Docker..." -Current 30 -Total 100

# Run official script
$Script = "curl -fsSL https://get.docker.com -o get-docker.sh && sudo sh get-docker.sh"

pwsh -c "$Script"

Show-SousChef -Message "Setting user permissions..." -Current 80 -Total 100
pwsh -c "sudo usermod -aG docker $USER"

Show-SousChef -Message "Docker Engine Active." -Complete