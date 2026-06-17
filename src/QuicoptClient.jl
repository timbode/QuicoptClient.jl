"""
QuicoptClient — the Julia client for the Quicopt API.

Authors a model in a familiar Julia front-end (JuMP) and converts it to
QuicoptModeler's IR (`import_model`), the conversion layer of the client. The
durable IR/wire/solver layers live in QuicoptModeler; this package stays a thin
front-end. See `CLAUDE.md`. Transport (serialize → HTTP → key cache) comes later.
"""
module QuicoptClient

import JuMP
const MOI = JuMP.MOI
using QuicoptModeler
const Expression = QuicoptModeler.Expression   # the IR's abstract expr type (not exported)

export import_model

# ── MOI scalar function → IR Expression ─────────────────────────────────────
# `var` maps an `MOI.VariableIndex` to its IR `Var` leaf (closed over the naming).

_expr(v::MOI.VariableIndex, var) = var(v)
_expr(c::Real, var) = Const(float(c))

# affine:  b + Σ aᵢ xᵢ
_expr(f::MOI.ScalarAffineFunction, var) =
    _sum(vcat(Const(f.constant),
              Expression[Apply(:*, Expression[Const(t.coefficient), var(t.variable)]) for t in f.terms]))

# quadratic: MOI stores ½ xᵀQx + aᵀx + b, so a diagonal term (c,x,x) is ½c·x² and
# an off-diagonal (c,x,y) — held once — is c·x·y.
function _expr(f::MOI.ScalarQuadraticFunction, var)
    terms = Expression[Const(f.constant)]
    for t in f.affine_terms
        push!(terms, Apply(:*, Expression[Const(t.coefficient), var(t.variable)]))
    end
    for t in f.quadratic_terms
        if t.variable_1 == t.variable_2
            push!(terms, Apply(:*, Expression[Const(t.coefficient / 2),
                                              Apply(:^, Expression[var(t.variable_1), Const(2.0)])]))
        else
            push!(terms, Apply(:*, Expression[Const(t.coefficient),
                                              Apply(:*, Expression[var(t.variable_1), var(t.variable_2)])]))
        end
    end
    _sum(terms)
end

# nonlinear: a symbol-keyed operator tree mapping ~1:1 onto QuicoptModeler's catalog
_expr(f::MOI.ScalarNonlinearFunction, var) =
    _apply(f.head, Expression[_expr(a, var) for a in f.args])

# sum of terms, dropping additive-zero constants (cosmetic; value-preserving)
function _sum(terms)
    nz = Expression[t for t in terms if !(t isa Const && t.value == 0.0)]
    isempty(nz)     ? Const(0.0) :
    length(nz) == 1 ? nz[1] :
                      Apply(:+, nz)
end

# MOI operator head → IR Apply, normalised to the catalog's arities
function _apply(head::Symbol, args::Vector{Expression})
    head === :- && length(args) == 1 && return Apply(:-, Expression[Const(0.0), args[1]])   # unary minus
    head === :* && length(args) > 2  && return foldl((a, b) -> Apply(:*, Expression[a, b]), args)  # n-ary ⇒ binary
    haskey(QuicoptModeler.OPERATORS, head) ||
        error("operator :$head is not in QuicoptModeler's catalog — register it there (ir.jl) before importing")
    Apply(head, args)
end

# ── variable bounds / integrality from VariableIndex-in-set constraints ──────

_bound!(lo, hi, dom, vi, s::MOI.GreaterThan) = (lo[vi] = max(lo[vi], s.lower))
_bound!(lo, hi, dom, vi, s::MOI.LessThan)    = (hi[vi] = min(hi[vi], s.upper))
_bound!(lo, hi, dom, vi, s::MOI.EqualTo)     = (lo[vi] = hi[vi] = s.value)
_bound!(lo, hi, dom, vi, s::MOI.Interval)    = (lo[vi] = s.lower; hi[vi] = s.upper)
_bound!(lo, hi, dom, vi, ::MOI.ZeroOne)      = (dom[vi] = BINARY; lo[vi] = max(lo[vi], 0.0); hi[vi] = min(hi[vi], 1.0))
_bound!(lo, hi, dom, vi, ::MOI.Integer)      = (dom[vi] = INTEGER)

# ── function-in-set constraint → IR Constraint (Zero / Nonneg) ───────────────
# `f ∈ {≥ l}` ⇒ f − l ≥ 0 ; `f ∈ {≤ u}` ⇒ u − f ≥ 0 ; `f = v` ⇒ f − v = 0.

_minus(f, c::Real) = c == 0.0 ? f : Apply(:-, Expression[f, Const(float(c))])
_geq(u, f) = Apply(:-, Expression[Const(float(u)), f])

_con!(cons, f, s::MOI.EqualTo)     = push!(cons, Constraint(_minus(f, s.value), Zero(),   Pair{Symbol,SetRef}[]))
_con!(cons, f, s::MOI.GreaterThan) = push!(cons, Constraint(_minus(f, s.lower), Nonneg(), Pair{Symbol,SetRef}[]))
_con!(cons, f, s::MOI.LessThan)    = push!(cons, Constraint(_geq(s.upper, f),   Nonneg(), Pair{Symbol,SetRef}[]))
function _con!(cons, f, s::MOI.Interval)
    push!(cons, Constraint(_minus(f, s.lower), Nonneg(), Pair{Symbol,SetRef}[]))
    push!(cons, Constraint(_geq(s.upper, f),   Nonneg(), Pair{Symbol,SetRef}[]))
end

"""
    import_model(m::JuMP.Model) -> QuicoptModeler.Program

Convert a JuMP/MOI model into QuicoptModeler's `Program` IR. Imports at the MOI
level: each variable becomes a scalar `VarDecl` (`:x{col}`) with its bounds and
domain; the objective and every function-in-set constraint become IR expressions
(`ScalarNonlinearFunction`/affine/quadratic → the expression graph; `EqualTo` →
`Zero`, `LessThan`/`GreaterThan`/`Interval` → `Nonneg`). The result is a flat
`Program` (no index sets); `flatten` is effectively identity on it.
"""
function import_model(m::JuMP.Model)
    b = JuMP.backend(m)
    vis = MOI.get(b, MOI.ListOfVariableIndices())
    varname(vi) = Symbol("x", vi.value)
    var(vi) = Var(varname(vi), ())

    lo  = Dict(vi => -Inf for vi in vis)
    hi  = Dict(vi =>  Inf for vi in vis)
    dom = Dict(vi => CONTINUOUS for vi in vis)
    for (F, S) in MOI.get(b, MOI.ListOfConstraintTypesPresent())
        F === MOI.VariableIndex || continue
        for ci in MOI.get(b, MOI.ListOfConstraintIndices{F,S}())
            _bound!(lo, hi, dom, MOI.get(b, MOI.ConstraintFunction(), ci), MOI.get(b, MOI.ConstraintSet(), ci))
        end
    end

    vars = VarDecl[]
    for vi in vis
        l, u = lo[vi], hi[vi]
        (isfinite(l) && isfinite(u)) ||
            error("variable $(varname(vi)) has a non-finite bound [$l, $u]; unbounded import is not supported yet")
        push!(vars, VarDecl(varname(vi), Symbol[], dom[vi], l, u, clamp(0.0, l, u)))
    end

    sense = MOI.get(b, MOI.ObjectiveSense()) == MOI.MAX_SENSE ? :max : :min
    Fobj = MOI.get(b, MOI.ObjectiveFunctionType())
    objective = _expr(MOI.get(b, MOI.ObjectiveFunction{Fobj}()), var)

    cons = Constraint[]
    for (F, S) in MOI.get(b, MOI.ListOfConstraintTypesPresent())
        F === MOI.VariableIndex && continue
        for ci in MOI.get(b, MOI.ListOfConstraintIndices{F,S}())
            _con!(cons, _expr(MOI.get(b, MOI.ConstraintFunction(), ci), var), MOI.get(b, MOI.ConstraintSet(), ci))
        end
    end

    Program(IndexSet[], Dict{Symbol,Dict{Tuple,Vector}}(), Dict{Symbol,Dict{Tuple,Float64}}(),
            vars, objective, sense, cons, Dict{Tuple{Symbol,Tuple},Float64}())
end

end
