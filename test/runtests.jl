# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: (c) 2026 Tim Bode, PGI-12, Forschungszentrum Jülich
using QuicoptClient
using Test

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
    @testset "wire bytes match golden — $name" for (name, m) in Fixtures.models()
        golden = joinpath(GOLDENS, name * ".hex")
        @test isfile(golden)
        @test bytes2hex(QuicoptClient.encode(QuicoptClient.import_model(m))) == read(golden, String)
    end

    include("transport.jl")
end
