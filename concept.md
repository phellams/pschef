# Module Concept Notes


## **Layout Definitions**

|Concept|Part|definition|
|---|---|---|
|**Alias**|`Invoke-PsChef`,`chef`,`pschef`|The CLI command.|
|**Scripts**|*Ingredients*|The raw scripts (e.g., `dotnet/aot.ps1`).|
|**Groups**|*Pantry*|Folders inside Ingredients (e.g., `Ingredients/dotnet`).|
|**Bundles**|*Recipes*|Instructions combining multiple ingredients.|
|**Templates**|*Mise*|Mise-en-place. The static boilerplates used by ingredients.|
|**Execution**|*Prep*|Running a single ingredient (e.g., `chef prep dotnet`).|
|**Orchestration**|*Cook*|Running a full recipe (e.g., `chef cook Lab`).|
|**Sync**|*Stock*|Pulling ingredients from external repos.|
|**List**|*Menu*|Showing what is available.|


## **The Syntax Flow**

  * Scaffold a specific item:
    `chef prep <Pantry> <Ingredient> -Name "App"`
    (Example: `chef prep dotnet aot`)
  * Execute a full stack:
    `chef cook <RecipeName>`
    (Example: `chef cook StandardLab`)
  * Update external sources:
    `chef stock`
  * See available tools:
    `chef menu`


```pre
PsChef/
├── Ingredients/
│   ├── dotnet/
│   │   ├── aot.ps1       # Logic
│   │   └── aot.md        # Docs
│   └── zig/
│       ├── bin.ps1
│       └── bin.md
├── Recipes/              # Multi-step instructions
└── Mise/                 # Raw templates ({{Name}})
```