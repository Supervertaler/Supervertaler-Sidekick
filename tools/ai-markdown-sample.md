# The Symbol δ (Lowercase Delta)

δ is the lowercase form of the fourth letter of the Greek alphabet (uppercase: Δ). It has many specialized meanings across different fields:

## Mathematics
- **Small change/increment**: Represents an infinitesimally small quantity, often paired with ε (epsilon) in calculus proofs (e.g., *epsilon-delta* definition of a limit)
- **Kronecker delta (δ<sub>ij</sub>)**: Equals 1 if i = j, and 0 otherwise
  - Used in `sum(δ_ij * a_j)` and in tensor notation
  - Written ~~δ(i,j)~~ δ<sub>ij</sub> in most textbooks
- **Dirac delta function (δ(x))**: A function that is zero everywhere except at x = 0, where it is infinite, used in physics and engineering

## Physics
- **Partial derivative notation**: Sometimes used alongside ∂ for small variations
- **Skin depth**: In electromagnetism, the penetration depth, in m<sup>-1</sup> terms

## Chemistry
1. **Partial charge**: δ+ and δ– denote partial charges in polar molecules (e.g., δ+ on H, δ– on O in H<sub>2</sub>O)
2. **Chemical shift**: In NMR spectroscopy, δ is the chemical shift (in ppm)
   - Measured against TMS, which is set to δ = 0

---

### At a glance

| Field | Meaning | Unit |
|:------|:-------:|-----:|
| Mathematics | Small change | – |
| Chemistry | **Chemical shift** | ppm |
| Physics | Skin depth | m |

> In Dutch and German it is *delta*; in Chinese 德尔塔. Translators: keep δ as it is 😀.

```python
def kronecker(i, j):
    return 1 if i == j else 0
```

See [Delta (letter)](https://en.wikipedia.org/wiki/Delta_(letter)) for more.
