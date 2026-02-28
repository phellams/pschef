### 2. Documentation: `README.md`

# PsChef `v2.0 Gold`

**Atomic Scaffolding & Orchestration CLI for PowerShell.**

PsChef is a high-performance developer tool designed to eliminate setup friction. It replaces monolithic scripts with **Ingredients** (atomic scripts) and **Recipes** (orchestration bundles), all rendered in a bespoke, handcrafted **Artisan TUI**.

## 1. Terminology

* **Pantry:** A logical group of ingredients (e.g., `sys`, `db`).
* **Ingredient:** An atomic script located at `Ingredients/<Pantry>/<Name>.ps1`.
* **Recipe:** A sequential bundle of ingredients at `Recipes/<Name>.ps1`.
* **Mise:** Static templates or configurations at `Mise/<Name>.tmplt`.

## 2. Global API (Helper Reference)

Use these built-in functions inside your ingredients for consistency and TUI integration:

| Function | Purpose | Example |
| --- | --- | --- |
| `Check-Stove` | Verifies a binary exists; triggers self-healing. | `Check-Stove "docker"` |
| `Measure-Ingredient` | Validates a required parameter. | `Measure-Ingredient $Name` |
| `Require-Ingredient` | Enforces another ingredient is prepped first. | `Require-Ingredient "sys" "wsl"` |
| `Fetch-Mise` | Loads a template with variable replacement. | `Fetch-Mise "web.tmplt" @{P=80}` |
| `Plate-Dish` | Final file/folder generation (New-Skeleton). | `Plate-Dish @{ "src"=@{} }` |
| `Show-SousChef` | Renders the responsive progress bar. | `Show-SousChef "Grilling" 50 100` |
| `Write-KitchenLog` | Outputs a rail-linked status entry. | `Write-KitchenLog Success "OK"` |

## 3. Usage Guide

### Interactive Menu

Simply type the command to launch the live selector:

```powershell
chef

```

### Visualizing Service Flow

See what a recipe does before cooking it:

```powershell
chef flow FullStack

```

### Direct Prepping

```powershell
chef prep dotnet aot -Name "FastApp"

```

### Kitchen History

```powershell
chef status

```

## 4. Developer Standard

Every ingredient script **must** contain a metadata header for dependency resolution and menu discovery:

```powershell
<#
.SYNOPSIS
    Installs Docker Engine.
.AUTHOR
    @Community
.DEPENDENCIES
    curl, sudo
#>

```