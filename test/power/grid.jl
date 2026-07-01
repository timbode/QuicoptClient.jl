# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: (c) 2026 Tim Bode, PGI-12, Forschungszentrum Jülich
# A power grid in per-unit. Duplicated from the reference PowerVertical test
# fixture so the two suites stay parallel yet independent (pure physics, no deps).

"""
    Branch(from, to, y, b_c, rate)

A transmission line in per-unit: series admittance `y = 1/(r + jx)`, total
line-charging susceptance `b_c` (half shunted at each end), and apparent-power
limit `rate` (`0` ⇒ unlimited).
"""
struct Branch
    from::Int
    to::Int
    y::ComplexF64        # series admittance  1/(r + jx)
    b_c::Float64         # total line-charging susceptance (½ shunted per end)
    rate::Float64        # apparent-power limit |S_ij| ≤ rate   (0 ⇒ unlimited)
end

"""
    Generator(bus, Pmin, Pmax, Qmin, Qmax, cost, fixed)

A generator at `bus` with active/reactive limits, linear cost `cost·P`, and a
`fixed` cost incurred only when committed.
"""
struct Generator
    bus::Int
    Pmin::Float64
    Pmax::Float64
    Qmin::Float64
    Qmax::Float64
    cost::Float64        # linear cost  c·P
    fixed::Float64       # fixed cost when committed (no-load / start-up)
end

"""
    Grid(n, y_shunt, vmin, vmax, Pd, Qd, branches, gens)

A power network in per-unit: `n` buses with shunt admittances, voltage limits
`[vmin, vmax]`, and fixed loads `(Pd, Qd)`, connected by `branches` and served by
`gens`.
"""
struct Grid
    n::Int
    y_shunt::Vector{ComplexF64}
    vmin::Vector{Float64}
    vmax::Vector{Float64}
    Pd::Vector{Float64}
    Qd::Vector{Float64}
    branches::Vector{Branch}
    gens::Vector{Generator}
end

"""
    ybus(g) -> Matrix{ComplexF64}

The bus admittance matrix

    Y_ii = y^sh_i + Σ_{(i,k)} (y_ik + j b^c_ik/2),    Y_ik = −y_ik   (i ≠ k),

symmetric for a reciprocal network.
"""
function ybus(g::Grid)
    Y = zeros(ComplexF64, g.n, g.n)
    for b in g.branches
        i, k = b.from, b.to
        Y[i, i] += b.y + im * b.b_c / 2
        Y[k, k] += b.y + im * b.b_c / 2
        Y[i, k] -= b.y
        Y[k, i] -= b.y
    end
    for i in 1:g.n
        Y[i, i] += g.y_shunt[i]
    end
    Y
end
