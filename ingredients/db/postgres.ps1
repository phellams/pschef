<#
.synopsis
    Generates a PostgreSQL Docker Compose stack with volume persistence.
.author
    @GarveyKSnow
.dependencies
    docker
#>
param(
    [string]$Name = "postgres-lab",
    [string]$User = "admin",
    [string]$Pass = "secret",
    [string]$Storage = "volume" # "volume" or a filepath string
)

# Enforce Docker Presence (Self-Healing)
Require-Ingredient -Pantry "sys" -Ingredient "docker"

Show-SousChef -Message "Generating Postgres Mise..." -Current 50 -Total 100

# Handle Volume Strategy
$VDef = if ($Storage -eq "volume") { "volumes:`n  db_data:" } else { "" }
$VMap = if ($Storage -eq "volume") { "db_data:/var/lib/postgresql/data" } else { "$Storage`:/var/lib/postgresql/data" }

$Yml = Fetch-Mise "postgres.tmplt" @{
    Name = $Name; User = $User; Pass = $Pass;
    VolDef = $VDef; VolMap = $VMap
}

Plate-Dish @{ 
    "." = @{ "docker-compose.yml" = $Yml } 
}

Show-SousChef -Message "Postgres Stack Plated." -Complete