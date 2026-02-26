@{
    Description = "Full Local Dev Environment (WSL + Docker + Postgres)"
    Sequence    = @(
        @{ Group = "sys"; Action = "wsl"; Params = @{ Distro = "Debian" } },
        @{ Group = "sys"; Action = "docker"; Params = @{} },
        @{ Group = "db"; Action = "postgres"; Params = @{ Name = "DevDB"; Storage = "./data" } }
    )
}