# QuicoptClient.jl

The **Julia client for the Quicopt API**. A user authors a model in a familiar
Julia front-end (JuMP), and this package converts it to Quicopt's IR, serializes
it to the wire proto, and (later) ships it to the service.

This is a **client/front-end, not a modeler.** The durable layers — the IR, the
on-the-wire model schema, `flatten`, the routing brain, the solver portfolio —
all live in **QuicoptModeler** (`../QuicoptModeler`, `Pkg.develop`'d). QuicoptClient
stays thin and replaceable. It is the clean, **per-language** successor to the
polyglot `QuicoptClients` repo: one package per language — `QuicoptClient.jl`
here, a Ruby gem, a Python/Pyomo client elsewhere — each published and versioned
on its own.

## Two layers

1. **Conversion** — external model → QuicoptModeler `Program` (the IR). This is
   what unlocks anything a MathOpt `ModelProto` can't express (nonlinear).
2. **Transport** — `Program` → `Wire.encode` bytes → HTTP `POST /v1/solve`, with
   the minted free key cached and replayed as a Bearer token (the `quicopt.py`
   pattern). **Deferred** until the conversion layer is proven.

## Current state — the conversion layer (MOI → `Program`), wire elided

Built first and proven with the wire skipped, **and without a solver** (the client
depends on no backend): build a JuMP model, import it to a `Program`, round-trip
through QuicoptModeler's codec (no HTTP), flatten, and check the IR *evaluates
identically* to the JuMP source at random points.

```
build JuMP model
   │  ① import         (this package: MOI → Program)
   ▼
 Program ─② Wire.encode─► bytes ··(wire skipped)·· ─③ Wire.decode─► Program ─④ flatten─► closures
        compare evaluation (objective + each constraint residual) ⇆ the JuMP model  ← ⑤ no solver
```

Only ① is new here; ②–④ are QuicoptModeler's (already green). So any discrepancy
in ⑤ localizes to the importer — the house "one thing under test" property.

**Status (green — 376 tests).** `import_model` covers affine / quadratic (MOI's
½-on-diagonal convention) / nonlinear (`^ / exp sin cos …`, n-ary `+`, unary `-`)
functions, variable bounds + integrality (`ZeroOne`/`Integer` → `Domain`), and
`EqualTo`/`LessThan`/`GreaterThan`/`Interval` → `Zero`/`Nonneg`. Fidelity is checked
**backend-free**: the round-tripped IR's `closures` (a *lowering*, not a solver)
must reproduce the JuMP model's objective + every constraint residual at random
points. Fixtures: three convex toys plus the **`PowerVertical` mirror**
(`test/power/`) — AC-OPF *and* unit commitment authored in JuMP, the parallel of
QuicoptModeler's IR-authored fixture, so the binary `u`'s and the nonlinear
`v·v·cos` balance are proven to import faithfully. Deferred: unbounded variables
(importer rejects ±Inf bounds), `Max` sense, and operators outside the catalog
(error by design → register them in QuicoptModeler).

**Backend-free — a caveat (mostly resolved).** The client's *direct* deps are
`JuMP` + `QuicoptModeler` only; no solver, runtime or test. As of 2026-06-18
QuicoptModeler's backends are *mostly* optional — `Ipopt`, `HiGHS`, and
`QuicoptBinary` are weakdeps / package extensions, so installing QuicoptClient no
longer pulls them. **`QuicoptMixed` is the one remaining hard dep** (still in
QuicoptModeler `[deps]`), so it is still pulled transitively (+ OrdinaryDiffEqTsit5
etc.). Fully honouring "the client depends on a backend nowhere" now needs only
QuicoptMixed made a weakdep too — then the IR + wire + lowerings + route core
installs with zero solvers.

## The conversion (MOI → `Program`)

Import at the **MOI level**, not JuMP's surface: MOI is the stable structured
layer, and modern JuMP lowers nonlinear expressions to
`MOI.ScalarNonlinearFunction` — a symbol-keyed operator tree that maps near-1:1
onto QuicoptModeler's operator catalog (`OPERATORS`: `+ - * / ^ sin cos exp log
sqrt …`).

- `ScalarNonlinearFunction` → `Apply`; affine/quadratic functions → `Apply` over
  `+`/`*`; `VariableIndex` → `Var`.
- Sets: `EqualTo`→`Zero`, `LessThan`/`GreaterThan`→`Nonneg` (shifted),
  `Interval`→ two rows; `ZeroOne`/`Integer`→ `Domain`.
- An operator absent from the catalog is a coverage gap to fill *in
  QuicoptModeler* (register + AD/JuMP rules, FD-tested), never papered over here.

## Conventions

- **Code reads like mathematics**; comment *why*, not *what*. Internal
  functions/types are `_`-prefixed.
- **Verification-first, backend-free**: the spine is a differential test that the
  imported + round-tripped IR *evaluates identically* to the JuMP source (via
  `closures`) — never a solver. The client depends on a backend nowhere.
- The IR and proto are **owned by QuicoptModeler** — depend on its types, never
  fork them here.
- Never `git push`; no `Co-Authored-By` trailer in commits; work on a branch.
- Run tests: `julia --project=. -e 'using Pkg; Pkg.test()'`.

## Layout (planned)

- `src/` — the MOI → `Program` importer (conversion layer).
- `test/` — the differential loop above (deps: QuicoptModeler + JuMP + Ipopt).
- Transport layer + the network client arrive once the conversion seam is proven.
