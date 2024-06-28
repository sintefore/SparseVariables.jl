using Documenter, JuMP, SparseVariables, HiGHS, CSV, DataFrames, PrettyTables

pages = [
    "Introduction" => "index.md",
    "Manual" => [
        "Get started" => "manual/get_started.md",
        "Benchmarks" => "manual/benchmarks.md",
    ],
    "API reference" => "reference/api.md",
]

Documenter.makedocs(
    sitename = "SparseVariables",
    format = Documenter.HTML(;
        prettyurls = get(ENV, "CI", "false") == "true",
        edit_link = "main",
        assets = String[],
    ),
    doctest = true,
    #modules = [SparseVariables],
    pages = pages,
)

Documenter.deploydocs(; repo = "github.com/sintefore/SparseVariables.jl.git", push_preview = true)
