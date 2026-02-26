param([string]$Name)

# 1. Fail Fast if cargo isn't found
Assert-ChefTool -Command "cargo" -Message "Rust toolchain missing."

Show-SousChef -Message "Scaffolding Rust..." -Current 20 -Total 100