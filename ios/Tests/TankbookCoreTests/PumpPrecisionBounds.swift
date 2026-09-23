import Foundation

/// Interval estimates and a risk bound for the pump reader's measured
/// precision, as `agents/research/PU.68.md` derives them from the literature:
/// the Wilson score interval to ESTIMATE (Brown, Cai & DasGupta 2001, eq. 4),
/// the exact binomial bounds to CERTIFY (Clopper-Pearson; the exact binomial
/// upper confidence bound of Bates et al. 2021, arXiv:2101.02703, App. B), and
/// the Hoeffding-Bentkus p-value for a bounded loss (Angelopoulos et al. 2021,
/// arXiv:2110.01052, eq. 2). A point estimate over 45-52 commits cannot show a
/// 0.99 floor; these say how far the corpus is from showing it.
enum PumpPrecisionBounds {
    static let z95TwoSided = 1.959963984540054
    static let z95OneSided = 1.6448536269514722

    /// The Wilson score interval for `x` successes of `n` (BCD eq. 4).
    static func wilson(_ x: Int, _ n: Int, z: Double) -> (lower: Double, upper: Double) {
        guard n > 0 else { return (0, 1) }
        let nd = Double(n), p = Double(x) / nd, z2 = z * z
        let centre = (Double(x) + z2 / 2) / (nd + z2)
        let half = z * nd.squareRoot() / (nd + z2) * (p * (1 - p) + z2 / (4 * nd)).squareRoot()
        return (max(0, centre - half), min(1, centre + half))
    }

    /// ln Γ(x); the explicit Double types pick the C library's overload.
    private static func logGamma(_ x: Double) -> Double {
        let value: Double = Foundation.lgamma(x)
        return value
    }

    /// P(Bin(n, p) <= k).
    static func binomialCDF(_ k: Int, _ n: Int, _ p: Double) -> Double {
        if k < 0 { return 0 }
        if k >= n { return 1 }
        if p <= 0 { return 1 }
        if p >= 1 { return 0 }
        let logN = logGamma(Double(n) + 1), lp = log(p), lq = log1p(-p)
        var sum = 0.0
        for i in 0...k {
            let di = Double(i)
            sum += exp(logN - logGamma(di + 1) - logGamma(Double(n) - di + 1) + di * lp + (Double(n) - di) * lq)
        }
        return min(1, sum)
    }

    /// The p at which a decreasing-in-p function crosses `target`, by bisection.
    private static func solve(_ f: (Double) -> Double, target: Double) -> Double {
        var lo = 0.0, hi = 1.0
        for _ in 0..<100 {
            let mid = (lo + hi) / 2
            if f(mid) > target { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }

    /// The one-sided Clopper-Pearson lower bound on a proportion at level
    /// `alpha`: the p at which P(Bin(n, p) >= x) = alpha (BCD §4.2.1).
    static func clopperPearsonLower(_ x: Int, _ n: Int, alpha: Double) -> Double {
        guard x > 0 else { return 0 }
        // P(X >= x) = 1 - CDF(x - 1) rises with p, so solve on its complement.
        return solve({ binomialCDF(x - 1, n, $0) }, target: 1 - alpha)
    }

    /// The exact binomial upper confidence bound on a {0,1} loss rate with `k`
    /// losses in `n` exchangeable units at level `delta` (RCPS App. B, eq. 42).
    static func binomialUCB(_ k: Int, _ n: Int, delta: Double) -> Double {
        guard n > 0 else { return 1 }
        return solve({ binomialCDF(k, n, $0) }, target: delta)
    }

    /// The Hoeffding-Bentkus p-value for H0: risk > alpha, from the mean
    /// `risk` of a loss in [0, 1] over `n` units (LTT eq. 2).
    static func hoeffdingBentkusPValue(risk: Double, n: Int, alpha: Double) -> Double {
        guard n > 0 else { return 1 }
        let a = min(risk, alpha)
        func h1(_ a: Double, _ b: Double) -> Double {
            let first = a > 0 ? a * log(a / b) : 0
            let second = a < 1 ? (1 - a) * log((1 - a) / (1 - b)) : 0
            return first + second
        }
        let hoeffding = exp(-Double(n) * h1(a, alpha))
        let bentkus = M_E * binomialCDF(Int((Double(n) * risk).rounded(.up)), n, alpha)
        return min(1, min(hoeffding, bentkus))
    }

    /// One line for a report: the point estimate, the two-sided Wilson 95 %
    /// interval, and the one-sided 95 % lower bounds (Wilson, Clopper-Pearson).
    static func precisionLine(correct: Int, committed: Int) -> String {
        guard committed > 0 else { return "precision n/a (nothing committed)" }
        let two = wilson(correct, committed, z: z95TwoSided)
        let wilsonLower = wilson(correct, committed, z: z95OneSided).lower
        let cpLower = clopperPearsonLower(correct, committed, alpha: 0.05)
        return String(format: "precision %.3f, Wilson 95%% [%.4f, %.4f], one-sided 95%% lower: Wilson %.4f, "
                      + "Clopper-Pearson %.4f (n = %d cells)",
                      Double(correct) / Double(committed), two.lower, two.upper, wilsonLower, cpLower, committed)
    }
}
