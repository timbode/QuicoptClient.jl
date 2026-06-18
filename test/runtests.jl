using QuicoptClient
import QuicoptModeler as QM
using JuMP, Test, Random
const MOI = JuMP.MOI
const W = QM.Wire

include("power/PowerVertical.jl")
using .PowerVertical

# Backend-free fidelity check. The client's job is import + wire, never solving,
# so it depends on no backend — and neither does this test. Faithfulness is
# verified by *evaluation*: round-trip the imported Program through the wire,
# flatten it, and check the IR's own `closures` (a lowering, not a solver)
# reproduce the JuMP model's objective and every constraint residual at random
# points. No optimizer is ever attached.
function assert_faithful_import(m::Model, prog; samples = 25, seed = 1)
    c   = QM.closures(QM.flatten(W.decode(W.encode(prog))))   # the round-trip re-proves the codec on real importer output
    pos = Dict(name => i for (i, (name, _)) in enumerate(c.order))
    at(ν) = jv -> ν[pos[Symbol("x", JuMP.index(jv).value)]]   # a JuMP variable → its sampled value

    # the importer's set→residual transform: f = v ⇒ f−v ; f ≥ l ⇒ f−l ; f ≤ u ⇒ u−f
    resid(val, s::MOI.EqualTo)     = val - s.value
    resid(val, s::MOI.GreaterThan) = val - s.lower
    resid(val, s::MOI.LessThan)    = s.upper - val
    cons = all_constraints(m; include_variable_in_set_constraints = false)

    Random.seed!(seed)
    for _ in 1:samples
        ν  = vcat(rand(c.N_d), c.lvar .+ rand(c.N_c) .* (c.uvar .- c.lvar))   # binaries in [0,1], rest in-box
        f  = at(ν)
        @test c.f(ν) ≈ value(f, objective_function(m)) atol = 1e-8
        ir   = sort(c.g(ν))
        jump = sort(Float64[resid(value(f, constraint_object(con).func), constraint_object(con).set) for con in cons])
        @test length(ir) == length(jump)
        @test ir ≈ jump atol = 1e-8
    end
end

@testset "QuicoptClient" begin
    @testset "MOI import → IR evaluates identically (backend-free)" begin
        # fixture 1 — nonlinear objective (^, /), box bounds, no constraints.
        m1 = Model()
        @variable(m1, 0.1 <= x <= 10)
        @objective(m1, Min, x^2 + 1 / x)
        assert_faithful_import(m1, import_model(m1))

        # fixture 2 — quadratic objective + nonlinear (exp) ≤ constraint.
        m2 = Model()
        @variable(m2, -5 <= x2 <= 5)
        @variable(m2, -5 <= y2 <= 5)
        @objective(m2, Min, (x2 - 3)^2 + (y2 - 3)^2)
        @constraint(m2, exp(x2) + exp(y2) <= 4)
        assert_faithful_import(m2, import_model(m2))

        # fixture 3 — quadratic with an off-diagonal (x·y) term.
        m3 = Model()
        @variable(m3, -5 <= x3 <= 5)
        @variable(m3, -5 <= y3 <= 5)
        @objective(m3, Min, x3^2 + x3 * y3 + y3^2 - 3 * x3)
        assert_faithful_import(m3, import_model(m3))
    end

    # The PowerVertical mirror: the same physics QuicoptModeler authors in the raw
    # IR, here authored in JuMP and brought in through `import_model`.
    @testset "AC-OPF import → IR evaluates identically" begin
        g = three_bus()
        m = acopf_jump(g)
        assert_faithful_import(m, import_model(m))
    end

    @testset "unit commitment (MINLP) import → IR evaluates identically" begin
        g    = three_bus()
        m    = acopf_uc_jump(g)
        prog = import_model(m)
        assert_faithful_import(m, prog)
        bins = [vd for vd in prog.vars if vd.domain == QM.BINARY]
        @test length(bins) == length(g.gens)                     # the commitment vars import as BINARY
    end
end
