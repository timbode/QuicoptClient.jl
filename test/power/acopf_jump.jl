# AC optimal power flow (and its unit-commitment MINLP) authored directly in JuMP
# — the front door a real user would use. The client imports these with
# `import_model`; the test then checks the imported IR evaluates identically.
#
# The physics mirrors QuicoptModeler's IR-authored `acopf.jl` (the same polar
# power balance and linking), so the two test suites stay parallel — one authoring
# in the raw IR, this one through JuMP. Nothing here solves; the models are built
# with no optimizer attached and only ever read for import.

# polar power injections P_i(v,θ), Q_i(v,θ) as JuMP nonlinear expressions
_injP(v, θ, G, B, i, n) = v[i] * sum(v[j] * (G[i, j] * cos(θ[i] - θ[j]) + B[i, j] * sin(θ[i] - θ[j])) for j in 1:n)
_injQ(v, θ, G, B, i, n) = v[i] * sum(v[j] * (G[i, j] * sin(θ[i] - θ[j]) - B[i, j] * cos(θ[i] - θ[j])) for j in 1:n)

_at(g::Grid, i) = [k for k in 1:length(g.gens) if g.gens[k].bus == i]   # generators on bus i

"""
    acopf_jump(g) -> JuMP.Model

The continuous AC optimal power flow for grid `g`, authored in JuMP (no optimizer):
families `v`/`θ` over buses, `Pg`/`Qg` over generators, nodal power balance per
bus, cost objective, bus-1 angle fixed as the reference.
"""
function acopf_jump(g::Grid)
    Y = ybus(g); G = real(Y); B = imag(Y)
    n, ng = g.n, length(g.gens)
    m = Model()
    @variable(m, g.vmin[i] <= v[i = 1:n] <= g.vmax[i], start = 1.0)
    @variable(m, -π <= θ[i = 1:n] <= π, start = 0.0)
    @variable(m, g.gens[k].Pmin <= Pg[k = 1:ng] <= g.gens[k].Pmax, start = 0.0)
    @variable(m, g.gens[k].Qmin <= Qg[k = 1:ng] <= g.gens[k].Qmax, start = 0.0)
    fix(θ[1], 0.0; force = true)                                            # angle reference
    @constraint(m, [i = 1:n], sum(Pg[k] for k in _at(g, i); init = 0.0) - g.Pd[i] - _injP(v, θ, G, B, i, n) == 0)
    @constraint(m, [i = 1:n], sum(Qg[k] for k in _at(g, i); init = 0.0) - g.Qd[i] - _injQ(v, θ, G, B, i, n) == 0)
    @objective(m, Min, sum(g.gens[k].cost * Pg[k] for k in 1:ng))
    m
end

"""
    acopf_uc_jump(g) -> JuMP.Model

AC OPF with unit commitment: adds a binary `u` per generator, the linking
inequalities `u_k P^min_k ≤ P_k ≤ u_k P^max_k` (and the reactive analogue), and
fixed costs in the objective. Generator power lower bounds reach 0 so an off unit
(`u_k = 0`) can be forced silent.
"""
function acopf_uc_jump(g::Grid)
    Y = ybus(g); G = real(Y); B = imag(Y)
    n, ng = g.n, length(g.gens)
    m = Model()
    @variable(m, g.vmin[i] <= v[i = 1:n] <= g.vmax[i], start = 1.0)
    @variable(m, -π <= θ[i = 1:n] <= π, start = 0.0)
    @variable(m, min(0.0, g.gens[k].Pmin) <= Pg[k = 1:ng] <= g.gens[k].Pmax, start = 0.0)
    @variable(m, min(0.0, g.gens[k].Qmin) <= Qg[k = 1:ng] <= g.gens[k].Qmax, start = 0.0)
    @variable(m, u[k = 1:ng], Bin)
    fix(θ[1], 0.0; force = true)
    @constraint(m, [i = 1:n], sum(Pg[k] for k in _at(g, i); init = 0.0) - g.Pd[i] - _injP(v, θ, G, B, i, n) == 0)
    @constraint(m, [i = 1:n], sum(Qg[k] for k in _at(g, i); init = 0.0) - g.Qd[i] - _injQ(v, θ, G, B, i, n) == 0)
    @constraint(m, [k = 1:ng], u[k] * g.gens[k].Pmax - Pg[k] >= 0)          # P ≤ u·Pmax
    @constraint(m, [k = 1:ng], Pg[k] - u[k] * g.gens[k].Pmin >= 0)          # P ≥ u·Pmin
    @constraint(m, [k = 1:ng], u[k] * g.gens[k].Qmax - Qg[k] >= 0)
    @constraint(m, [k = 1:ng], Qg[k] - u[k] * g.gens[k].Qmin >= 0)
    @objective(m, Min, sum(g.gens[k].cost * Pg[k] for k in 1:ng) + sum(g.gens[k].fixed * u[k] for k in 1:ng))
    m
end
