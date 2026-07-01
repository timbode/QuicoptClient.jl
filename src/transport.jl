# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: (c) 2026 Tim Bode, PGI-12, Forschungszentrum Jülich
# ── transport: ship the wire bytes to the Quicopt service ────────────────────
#
# `solve(model)` imports + encodes the model and has the service solve it. Two
# paths, same parsed-JSON result:
#   • sync  (default)      — POST /v1/solve; the server waits for the worker (≤60s).
#   • async (`async=true`) — POST /v1/jobs, poll GET /v1/jobs/{id} to completion,
#     then GET …/result. Use it for the first call against a freshly-booted server:
#     the worker JIT-warms (~30–60s) before claiming, which can 504 a cold sync call.
#
# Keyless on first use: the server mints a key (`X-Quicopt-Api-Key` header), cached
# at `~/.cache/quicopt/free_key` and replayed as a Bearer token (the standard
# free-key cache pattern). The HTTP calls sit behind a `transport` seam — `(method, url, headers,
# body) -> (; status, api_key, body)` — so the mint/cache/poll/parse logic is tested
# with no network.

import HTTP
import JSON3

"""
    DEFAULT_BASE_URL

The public Quicopt service endpoint `solve` targets unless a `base_url` is given.
"""
const DEFAULT_BASE_URL = "https://try.quicoptapi.pgi.fz-juelich.de"

"""
    _default_key_path() -> String

The default location of the cached free-key file,
`\$XDG_CACHE_HOME/quicopt/free_key` (falling back to `~/.cache` when the variable is
unset).
"""
_default_key_path() =
    joinpath(get(ENV, "XDG_CACHE_HOME", joinpath(homedir(), ".cache")), "quicopt", "free_key")

"""
    QuicoptError(status, reason, message, display)

A non-2xx response from the service. `reason` is the stable machine code (e.g.
`"unsupported_model"`, `"quota_exhausted"`); `display` is the server's
ready-to-print framed message, shown by `showerror` when present.
"""
struct QuicoptError <: Exception
    status::Int
    reason::String
    message::String
    display::String
end
Base.showerror(io::IO, e::QuicoptError) =
    print(io, isempty(e.display) ? "QuicoptError($(e.status), $(e.reason)): $(e.message)" : e.display)

"""
    _http(method, url, headers, body) -> NamedTuple

The default `transport`: a thin wrapper over `HTTP.request` normalised to what
`solve` reads. Returns `(; status, api_key, body)`, where `api_key` is the
`X-Quicopt-Api-Key` response header (empty if absent). HTTP status errors are not
raised (`status_exception = false`); `solve` inspects `status` itself.
"""
function _http(method::Symbol, url::AbstractString, headers, body)
    r = HTTP.request(method, url, headers, body; status_exception = false)
    return (; status = Int(r.status), api_key = HTTP.header(r, "X-Quicopt-Api-Key", ""), body = r.body)
end

"""
    _error(resp) -> QuicoptError

Build a [`QuicoptError`](@ref) from a non-2xx response `resp` by reading its JSON
body's `reason`/`error`/`display` fields (each defaulting to `""` if the body is
missing or unparseable).
"""
function _error(resp)
    body = try JSON3.read(resp.body) catch; nothing end
    field(k) = body === nothing ? "" : String(get(body, k, ""))
    QuicoptError(resp.status, field(:reason), field(:error), field(:display))
end

"""
    _finish(result, silent) -> result

Return the parsed `result`, first printing its `display` banner unless `silent` is
set (or no banner is present).
"""
_finish(result, silent) = (silent || (haskey(result, :display) && println(result.display)); result)

"""
    solve(model::JuMP.Model; kwargs...) -> JSON3.Object

Import `model`, encode it to wire bytes, and solve it via the Quicopt service.
See the byte method below for the keyword arguments.
"""
solve(model::JuMP.Model; kwargs...) = solve(encode(import_model(model)); kwargs...)

"""
    solve(bytes; base_url, key_path, async, poll, timeout, silent, transport) -> JSON3.Object

POST already-encoded wire `bytes` and return the parsed JSON result (`status`,
`objective`, `feasible`, `solution`, `display`, …). `async=true` submits to
`/v1/jobs` and polls to completion (use it for the first call against a cold
server — the worker warmup can 504 a sync call); otherwise it is one `/v1/solve`.
On the first keyless call the server mints an API key, cached at `key_path` and
replayed as a Bearer token. A non-2xx response throws [`QuicoptError`](@ref).
`silent=true` suppresses printing the result banner.
"""
function solve(bytes::AbstractVector{UInt8};
               base_url::AbstractString = DEFAULT_BASE_URL,
               key_path::AbstractString = _default_key_path(),
               async::Bool = false, poll::Real = 0.5, timeout::Real = 180.0,
               silent::Bool = false, transport = _http)
    key = isfile(key_path) ? strip(read(key_path, String)) : ""
    headers = ["Content-Type" => "application/octet-stream"]
    isempty(key) || push!(headers, "Authorization" => "Bearer " * key)

    resp = transport(:POST, string(base_url, async ? "/v1/jobs" : "/v1/solve"), headers, bytes)
    resp.status >= 400 && throw(_error(resp))

    if isempty(key) && !isempty(resp.api_key)            # cache the minted key, then use it below
        mkpath(dirname(key_path))
        write(key_path, resp.api_key)
        key = String(resp.api_key)
        silent || @info "minted a free Quicopt key (cached at $key_path)"
    end

    async || return _finish(JSON3.read(resp.body), silent)

    # async: poll the job to completion, then fetch its result
    auth = isempty(key) ? Pair{String,String}[] : ["Authorization" => "Bearer " * key]
    job_id = String(JSON3.read(resp.body).job_id)
    deadline = time() + timeout
    while true
        st = transport(:GET, string(base_url, "/v1/jobs/", job_id), auth, UInt8[])
        st.status >= 400 && throw(_error(st))
        String(JSON3.read(st.body).status) in ("done", "failed") && break
        time() > deadline && error("QuicoptClient: job $job_id did not finish within $(timeout)s")
        sleep(poll)
    end
    res = transport(:GET, string(base_url, "/v1/jobs/", job_id, "/result"), auth, UInt8[])
    res.status >= 400 && throw(_error(res))
    return _finish(JSON3.read(res.body), silent)
end
