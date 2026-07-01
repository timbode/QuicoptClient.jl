# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: (c) 2026 Tim Bode, PGI-12, Forschungszentrum Jülich
using Documenter, QuicoptClient

makedocs(
    sitename = "QuicoptClient.jl",
    modules  = [QuicoptClient],
    authors  = "Tim Bode",
    # Render the public surface; `checkdocs = :exports` keeps the build quiet about
    # the deliberately-documented-but-unrendered private helpers.
    checkdocs = :exports,
    format = Documenter.HTML(
        prettyurls = get(ENV, "CI", "false") == "true",
        canonical  = "https://timbode.github.io/QuicoptClient.jl",
        assets     = ["assets/custom.css"],
        sidebar_sitename = false,   # the logo already carries the brand
    ),
    pages = [
        "Home" => "index.md",
        "API reference" => [
            "Modeling"  => "api/modeling.md",
            "Transport" => "api/transport.md",
        ],
    ],
)

deploydocs(
    repo      = "github.com/timbode/QuicoptClient.jl",
    devbranch = "main",
)
