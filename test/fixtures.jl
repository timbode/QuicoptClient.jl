# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: (c) 2026 Tim Bode, PGI-12, Forschungszentrum Jülich
# Shared JuMP fixtures, imported by BOTH the public golden test (here) and the
# private verification harness. Keeping them in one
# place means the two test layers exercise exactly the same models.
module Fixtures

using JuMP
include(joinpath(@__DIR__, "power", "PowerVertical.jl"))
using .PowerVertical

export models, three_bus, acopf_jump, acopf_uc_jump

"""
    models() -> Vector{Pair{String,JuMP.Model}}

Each `name => model` is one import facet; `name` is also the golden file stem.
"""
function models()
    out = Pair{String,Model}[]

    # nonlinear objective (^, /), box bounds, no constraints
    m = Model(); @variable(m, 0.1 <= x <= 10); @objective(m, Min, x^2 + 1 / x)
    push!(out, "scalar_nlp" => m)

    # quadratic objective + nonlinear (exp) ≤ constraint
    m = Model(); @variable(m, -5 <= x <= 5); @variable(m, -5 <= y <= 5)
    @objective(m, Min, (x - 3)^2 + (y - 3)^2); @constraint(m, exp(x) + exp(y) <= 4)
    push!(out, "quad_exp_le" => m)

    # quadratic with an off-diagonal (x·y) term
    m = Model(); @variable(m, -5 <= x <= 5); @variable(m, -5 <= y <= 5)
    @objective(m, Min, x^2 + x * y + y^2 - 3 * x)
    push!(out, "quad_offdiag" => m)

    # Max sense
    m = Model(); @variable(m, 0 <= x <= 4); @variable(m, 0 <= y <= 4)
    @objective(m, Max, 3x + 2y - x^2 - y^2); @constraint(m, x + y <= 5)
    push!(out, "maximize" => m)

    # unbounded: x free (−∞,∞), y half-bounded [−2,∞)
    m = Model(); @variable(m, x); @variable(m, y >= -2)
    @objective(m, Min, (x - 1)^2 + (y + 1)^2 + x * y); @constraint(m, x + y == 3)
    push!(out, "unbounded" => m)

    # linear program — the free tier's `:lp` class (a real solve, not a 422)
    m = Model(); @variable(m, 0 <= x <= 4); @variable(m, 0 <= y <= 4)
    @objective(m, Max, 3x + 2y); @constraint(m, x + y <= 5); @constraint(m, x + 3y <= 9)
    push!(out, "lp" => m)

    # mixed-integer linear program — a general integer + a binary, the `:milp` class
    m = Model(); @variable(m, 0 <= x <= 10, Int); @variable(m, y, Bin)
    @objective(m, Max, 4x + 7y); @constraint(m, 2x + 3y <= 12)
    push!(out, "milp" => m)

    # the PowerVertical mirror — AC-OPF and unit commitment
    g = three_bus()
    push!(out, "acopf" => acopf_jump(g))
    push!(out, "unit_commitment" => acopf_uc_jump(g))

    out
end

end
