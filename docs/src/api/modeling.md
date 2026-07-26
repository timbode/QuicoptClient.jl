# Modeling

Convert a JuMP model into the Quicopt wire `Program` and serialize it to bytes.

```@docs
QuicoptClient.import_model
QuicoptClient.encode
```

## Stochastic models

A stochastic model is an ordinary JuMP model with two decorations: variables
marked as random *sources*, and scenario *aggregators* closing every stochastic
subexpression before it reaches the objective or a constraint root.

```julia
using QuicoptClient, JuMP

m = Model()
@variable(m, 0 <= x <= 200)            # decision: how much to stock
@variable(m, demand)                   # random: what will be asked for
set_source(m, demand, :normal, 100.0, 15.0)
set_scenarios(m, 512; seed = 42)

@objective(m, Min, 3x + 10 * smean(max(demand - x, 0)))
result = solve(m)
```

Using `demand` twice refers to the *same* draw — a source is one random
variable, shared by name; declare independent sources as separate variables.
These models solve through the service only: the aggregator heads are symbolic,
so attaching a local optimizer fails with an unsupported-operator error.

```@docs
QuicoptClient.set_source
QuicoptClient.set_scenarios
QuicoptClient.smean
QuicoptClient.scvar
QuicoptClient.sfreq_leq
```
