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

Built first and proven with the wire skipped: build a JuMP model, import it to a
`Program`, round-trip through QuicoptModeler's codec (no HTTP), flatten, solve —
and check it matches solving the original JuMP model directly.

```
build JuMP model
   │  ① import         (this package: MOI → Program)
   ▼
 Program ─② Wire.encode─► bytes ··(wire skipped)·· ─③ Wire.decode─► Program ─④ flatten─► solve
        compare  ⇆  JuMP → Ipopt/HiGHS directly on the same model     ← ⑤ differential acceptance
```

Only ① is new here; ②–④ are QuicoptModeler's (already green). So any discrepancy
in ⑤ localizes to the importer — the house "one thing under test" property.

**Status (first slice, green — 5 tests).** `import_model` covers affine /
quadratic (MOI's ½-on-diagonal convention) / nonlinear (`^ / exp …`, n-ary `+`,
unary `-`) functions, variable bounds + integrality (`ZeroOne`/`Integer` →
`Domain`), and `EqualTo`/`LessThan`/`GreaterThan`/`Interval` → `Zero`/`Nonneg`.
Three convex fixtures (nonlinear `^`/`/`; quadratic + `exp ≤`; off-diagonal
quadratic) round-trip and solve to the JuMP+Ipopt optimum. Deferred: unbounded
variables (the reference `_solve` rejects ±Inf bounds), integer/binary *solving*
(needs a discrete reference, not Ipopt — domains are imported, not yet exercised),
`Max` sense, and operators outside the catalog (error by design → register them in
QuicoptModeler). A `:+` over heterogeneous JuMP scalars surfaced one fix in
QuicoptModeler's reference lowering (`sum` → `reduce(+, …)`).

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
- **Verification-first**: the differential test against JuMP+Ipopt is the spine;
  the importer is never the thing trusted during bring-up.
- The IR and proto are **owned by QuicoptModeler** — depend on its types, never
  fork them here.
- Never `git push`; no `Co-Authored-By` trailer in commits; work on a branch.
- Run tests: `julia --project=. -e 'using Pkg; Pkg.test()'`.

## Layout (planned)

- `src/` — the MOI → `Program` importer (conversion layer).
- `test/` — the differential loop above (deps: QuicoptModeler + JuMP + Ipopt).
- Transport layer + the network client arrive once the conversion seam is proven.
