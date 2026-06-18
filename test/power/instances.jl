"""
    three_bus() -> Grid

A small 3-bus triangle for tests: generators at buses 1 (cheap, no fixed cost)
and 3 (dear, high fixed cost), load at buses 2 and 3. Same instance as
QuicoptModeler's fixture, so the imported model matches the IR-authored one.
"""
function three_bus()
    y = 1 / (0.01 + 0.10im)                      # common series admittance
    branches = [Branch(1, 2, y, 0.02, 3.0),
                Branch(2, 3, y, 0.02, 3.0),
                Branch(1, 3, y, 0.02, 3.0)]
    gens = [Generator(1, 0.0, 5.0, -3.0, 3.0, 10.0,   0.0),    # cheap, no fixed cost
            Generator(3, 0.0, 3.0, -2.0, 2.0, 30.0, 200.0)]    # dear + high fixed cost ⇒ shut if possible
    Grid(3, zeros(ComplexF64, 3),
         fill(0.9, 3), fill(1.1, 3),
         [0.0, 1.0, 0.5],                         # Pd
         [0.0, 0.4, 0.2],                         # Qd
         branches, gens)
end
