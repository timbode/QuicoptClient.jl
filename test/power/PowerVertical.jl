# ───────────────────────────────────────────────────────────────────────────
# The slice-0 vertical, JuMP-authored — QuicoptClient's mirror of QuicoptModeler's
# PowerVertical fixture. Same physics (grid + AC-OPF + unit commitment), but
# entered through JuMP rather than the raw IR, so it exercises *this* package's
# job: the MOI → Program import. There is no oracle and no solver here — the
# client neither solves nor depends on a backend; faithfulness is checked by
# evaluating the imported IR against the JuMP source (see runtests.jl).
# ───────────────────────────────────────────────────────────────────────────
module PowerVertical

using JuMP

include("grid.jl")
include("instances.jl")
include("acopf_jump.jl")

export Grid, Branch, Generator, ybus, three_bus, acopf_jump, acopf_uc_jump

end
