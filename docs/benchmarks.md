# Recorded benchmark observations

Recorded with `python -B scripts/bench.py` on 2026-10-18 (Apple Silicon laptop, moon 0.1.20261012 / moonc v0.10.15, Node 25). Wall times are end-to-end CLI runs including Node startup, best of three; they are recorded observations on one machine, not performance targets or guarantees.

| Case | Median wall time (ms) |
| --- | ---: |
| merge 12 layers x 2000 keys (24k paths) | 133 |
| export flat of the same tree | 126 |
| 1000 interpolation references | 261 |
| merge at nesting depth 100 | 143 |

Correctness at the same scale is asserted every run: the 24k-key merge, the 1000-reference configuration and the depth-100 merge are compared against the independent Python oracle (`scripts/bench.py --check`, also a CI step).
