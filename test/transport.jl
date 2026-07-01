# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: (c) 2026 Tim Bode, PGI-12, Forschungszentrum Jülich
# Transport tests — hermetic, no network. A scripted `transport` records each
# request and returns canned responses in order, so the mint/cache/Bearer-replay/
# poll/parse logic (sync and async) is exercised end to end without a live service.
using QuicoptClient, JuMP, Test
import JSON3

mutable struct FakeTransport
    requests::Vector{Any}
    responses::Vector{Any}
    i::Int
end
FakeTransport(responses) = FakeTransport(Any[], responses, 0)
function (t::FakeTransport)(method, url, headers, body)
    t.i += 1
    push!(t.requests, (; method, url, headers = Dict(headers), body))
    return t.responses[t.i]
end

_okbody(; kw...) = Vector{UInt8}(JSON3.write((;
    status = "optimal", objective = 1.5, feasible = true,
    solution = Dict("x1" => 1.0), display = "‹frame›", kw...)))
_json(nt) = Vector{UInt8}(JSON3.write(nt))

@testset "transport" begin
    keyfile = joinpath(mktempdir(), "free_key")

    # ── sync ────────────────────────────────────────────────────────────────
    # 1) keyless first call mints + caches the key, parses the result
    t = FakeTransport([(; status = 200, api_key = "ab"^32, body = _okbody())])
    r = solve(b"WIRE"; key_path = keyfile, silent = true, transport = t)
    @test r.status == "optimal" && r.objective == 1.5
    @test read(keyfile, String) == "ab"^32
    @test t.requests[1].method == :POST && endswith(t.requests[1].url, "/v1/solve")
    @test t.requests[1].headers["Content-Type"] == "application/octet-stream"
    @test !haskey(t.requests[1].headers, "Authorization")        # no bearer on the minting call

    # 2) second call replays the cached key as a Bearer token
    t2 = FakeTransport([(; status = 200, api_key = "", body = _okbody(objective = 2.0))])
    r2 = solve(b"WIRE"; key_path = keyfile, silent = true, transport = t2)
    @test r2.objective == 2.0
    @test t2.requests[1].headers["Authorization"] == "Bearer " * "ab"^32

    # 3) a non-2xx response throws QuicoptError carrying the reason + display
    t3 = FakeTransport([(; status = 422, api_key = "",
        body = _json((; error = "nonlinear program", reason = "unsupported_model", display = "‹unsupported›")))])
    e = try
        solve(b"WIRE"; key_path = keyfile, silent = true, transport = t3)
    catch err
        err
    end
    @test e isa QuicoptError && e.status == 422 && e.reason == "unsupported_model"
    @test sprint(showerror, e) == "‹unsupported›"

    # 4) solve(::JuMP.Model) runs the full import → encode → POST path
    m = Model(); @variable(m, 0 <= x <= 1); @objective(m, Min, x)
    t4 = FakeTransport([(; status = 200, api_key = "", body = _okbody())])
    r4 = solve(m; key_path = keyfile, silent = true, transport = t4)
    @test r4.status == "optimal" && !isempty(t4.requests[1].body)

    # ── async ───────────────────────────────────────────────────────────────
    # 5) submit → poll (running → done) → result; minted key replayed on the polls
    keyfile2 = joinpath(mktempdir(), "free_key")
    t5 = FakeTransport([
        (; status = 202, api_key = "cd"^32, body = _json((; job_id = "JOB1", status = "queued"))),
        (; status = 200, api_key = "",      body = _json((; status = "running"))),
        (; status = 200, api_key = "",      body = _json((; status = "done"))),
        (; status = 200, api_key = "",      body = _okbody(objective = 4.0))])
    r5 = solve(b"WIRE"; key_path = keyfile2, silent = true, async = true, poll = 0.001, transport = t5)
    @test r5.status == "optimal" && r5.objective == 4.0
    @test t5.requests[1].method == :POST && endswith(t5.requests[1].url, "/v1/jobs")
    @test t5.requests[2].method == :GET  && occursin("/v1/jobs/JOB1", t5.requests[2].url)
    @test endswith(t5.requests[end].url, "/result")
    @test read(keyfile2, String) == "cd"^32
    @test t5.requests[2].headers["Authorization"] == "Bearer " * "cd"^32   # poll uses the minted key
end
