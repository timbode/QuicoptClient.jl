# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: (c) 2026 Tim Bode, PGI-12, Forschungszentrum Jülich
# Regenerate the Julia wire codec from the vendored `program.proto`.
#
#   julia --project=. gen/gen.jl
#
# `proto/quicopt/modeler/v1/program.proto` is the published wire contract.
#
# The generated code under `src/proto/` is committed — this script is only re-run
# when the schema changes.
using ProtoBuf

const ROOT = normpath(joinpath(@__DIR__, ".."))
const OUT  = joinpath(ROOT, "src", "proto")
mkpath(OUT)

protojl(
    "quicopt/modeler/v1/program.proto",   # path relative to the search dir
    joinpath(ROOT, "proto"),              # search dir (proto root)
    OUT;                                  # output dir
    always_use_modules     = true,
    add_kwarg_constructors = true,
)

# stamp the SPDX header onto every generated file (rewritten on each run)
_spdx = "# SPDX-License-Identifier: Apache-2.0\n# SPDX-FileCopyrightText: (c) 2026 Tim Bode, PGI-12, Forschungszentrum Jülich\n"
for (root, _, files) in walkdir(OUT), f in files
    endswith(f, ".jl") || continue
    p = joinpath(root, f)
    s = read(p, String)
    startswith(s, "# SPDX") || write(p, _spdx * s)
end

@info "generated wire codec into src/proto/"
