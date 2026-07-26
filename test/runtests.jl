# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: (c) 2026 Tim Bode, PGI-12, Forschungszentrum Jülich
using QuicoptClient
using JuMP
using Test
import ProtoBuf as PB

include("fixtures.jl")
using .Fixtures

# Public, dependency-free regression. Import each fixture, encode, and lock the
# bytes against a committed golden — a guard against *self*-drift in the importer
# or the generated codec. It deliberately does NOT prove correctness against the
# service's reference codec: that is decode-equivalence (the client's bytes decode
# to the intended `Program`) plus an evaluation differential, which couple to the
# closed reference and so live in a separate, private verification harness. This
# repo depends on JuMP + ProtoBuf only.
#
# Regenerate goldens after an intended schema/importer change:
#     julia --project=. gen/goldens.jl
const GOLDENS = joinpath(@__DIR__, "goldens")

@testset "QuicoptClient" begin
    @testset "wire bytes match golden — $name" for (name, m) in
            vcat(Fixtures.models(), Fixtures.stochastic_models())
        golden = joinpath(GOLDENS, name * ".hex")
        @test isfile(golden)
        @test bytes2hex(QuicoptClient.encode(QuicoptClient.import_model(m))) == read(golden, String)
    end

    # The stochastic importer rewrite, checked structurally on its own structs:
    # a source never becomes a decision variable, its uses become source
    # references, declarations carry the distribution, and the scenario fields
    # ride along. (Whether the SERVICE accepts these bytes is decode-equivalence,
    # which lives in the private verification harness like all of it.)
    @testset "stochastic authoring — sources are declarations, not variables" begin
        _pb = QuicoptClient._pb

        m = Fixtures.stochastic_models()[1].second          # the newsvendor
        prog = QuicoptClient.import_model(m)
        @test [v.name for v in prog.vars] == ["x1"]         # demand is gone from the decision set
        @test [d.name for d in prog.sources] == ["demand"]
        @test prog.sources[1].kind.name === :parametric
        @test prog.sources[1].kind[].head == "normal"
        @test prog.scenarios == 512 && prog.scenario_seed == 42

        # the bytes round-trip through the generated codec with everything intact
        p2 = PB.decode(PB.ProtoDecoder(IOBuffer(QuicoptClient.encode(prog))), _pb.Program)
        @test [d.name for d in p2.sources] == ["demand"] && p2.scenarios == 512

        # empirical column survives, packed
        pe = QuicoptClient.import_model(Fixtures.stochastic_models()[2].second)
        @test pe.sources[1].kind.name === :empirical
        @test pe.sources[1].kind[].data == [0.9, 1.0, 1.1, 1.3]

        # a deterministic model emits NO stochastic fields (additive-only)
        md = Model(); @variable(md, 0 <= y <= 1); @objective(md, Min, y)
        pd = QuicoptClient.import_model(md)
        @test isempty(pd.sources) && pd.scenarios == 0 && pd.scenario_seed == 0

        # authoring guardrails
        mb = Model(); @variable(mb, 0 <= w <= 1)
        set_source(mb, w, :normal, 0.0, 1.0)
        @test_throws ErrorException QuicoptClient.import_model(mb)      # bounds on a source

        ma = Model(); v = @variable(ma)
        @test_throws ErrorException set_source(ma, v, :normal, 0.0, 1.0)  # anonymous, no name

        mc = Model(); @variable(mc, a); @variable(mc, b)
        set_source(mc, a, :normal, 0.0, 1.0)
        @test_throws ErrorException set_source(mc, b, :normal, 0.0, 1.0; name = :a)  # name collision

        @test_throws ErrorException set_scenarios(mc, 0)                # R ≥ 1
        @test_throws ErrorException set_scenarios(mc, 4; seed = 0)      # 0 reserved
    end

    include("transport.jl")
end
