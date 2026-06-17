using QuicoptClient
import QuicoptModeler as QM
using JuMP, Ipopt, Test
const W = QM.Wire

# Solve a Program through the full client→server path with the wire elided:
# encode → decode → flatten → QuicoptModeler's reference solve (IR → JuMP → Ipopt).
# Going through encode/decode also re-proves the codec on real importer output.
function solve_via_ir(prog)
    flat = QM.flatten(W.decode(W.encode(prog)))
    m, _ = QM._solve(flat)
    objective_value(m)
end

@testset "QuicoptClient" begin
    @testset "MOI import → IR ≡ JuMP+Ipopt (differential)" begin
        # fixture 1 — nonlinear objective (^, /), box bounds, no constraints.
        # min x² + 1/x ⇒ x⋆ = 2^(−1/3), f⋆ = 2^(−2/3) + 2^(1/3).
        m1 = Model(Ipopt.Optimizer); set_silent(m1)
        @variable(m1, 0.1 <= x <= 10)
        @objective(m1, Min, x^2 + 1/x)
        prog1 = import_model(m1)                       # import the structure before solving
        optimize!(m1)
        o1 = solve_via_ir(prog1)
        @test o1 ≈ objective_value(m1) atol = 1e-6
        @test o1 ≈ 2.0^(-2 / 3) + 2.0^(1 / 3) atol = 1e-5

        # fixture 2 — quadratic objective + nonlinear (exp) ≤ constraint; convex,
        # unique optimum, so both solves agree regardless of start.
        m2 = Model(Ipopt.Optimizer); set_silent(m2)
        @variable(m2, -5 <= x2 <= 5)
        @variable(m2, -5 <= y2 <= 5)
        @objective(m2, Min, (x2 - 3)^2 + (y2 - 3)^2)
        @constraint(m2, exp(x2) + exp(y2) <= 4)
        prog2 = import_model(m2)
        optimize!(m2)
        @test solve_via_ir(prog2) ≈ objective_value(m2) atol = 1e-5

        # fixture 3 — quadratic with an off-diagonal (x·y) term, unconstrained box.
        # min x² + xy + y² − 3x ⇒ optimum (2, −1), f⋆ = −3.
        m3 = Model(Ipopt.Optimizer); set_silent(m3)
        @variable(m3, -5 <= x3 <= 5)
        @variable(m3, -5 <= y3 <= 5)
        @objective(m3, Min, x3^2 + x3 * y3 + y3^2 - 3 * x3)
        prog3 = import_model(m3)
        optimize!(m3)
        o3 = solve_via_ir(prog3)
        @test o3 ≈ objective_value(m3) atol = 1e-6
        @test o3 ≈ -3.0 atol = 1e-5
    end
end
