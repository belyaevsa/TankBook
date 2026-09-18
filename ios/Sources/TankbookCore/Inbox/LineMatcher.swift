import Foundation

// MARK: - Pairing the cloud's invoice lines onto the local split
// (docs/EXTRACTION.md -> "Line merge outcomes")

/// One cloud line's partner on the local split, or none. Deterministic: the
/// same two lists always pair the same way, and no local line is ever paired
/// twice.
public struct LineMatch: Equatable, Sendable {
    public enum Basis: Equatable, Sendable {
        /// The local line with the same amount (CHECK 3 tolerance) - the
        /// strongest signal an invoice has, immune to how a title was OCR'd.
        case sameAmount
        /// No amount match; the local title closest to the cloud title above
        /// `LineMatcher.titleThreshold`.
        case title
        /// No partner: the cloud read a line the local split did not - offered
        /// as a new line the user can append.
        case new
    }

    public let cloudIndex: Int
    public let localIndex: Int?
    public let basis: Basis

    public init(cloudIndex: Int, localIndex: Int?, basis: Basis) {
        self.cloudIndex = cloudIndex
        self.localIndex = localIndex
        self.basis = basis
    }
}

/// Pairs cloud lines with local lines by amount first, then by title, else as
/// new - never by position, because the provider's printed order and the
/// splitter's order need not agree and a by-position pairing turns one shifted
/// line into a column of wrong offers. A local line with no partner is left
/// alone: the cloud never proposes deleting what the user's split has.
public enum LineMatcher {
    /// The token-overlap ratio a title pairing needs.
    public static let titleThreshold = 0.5

    public static func match(cloud: [ServiceRecognition.LineItem],
                             local: [ServiceItem]) -> [LineMatch] {
        var taken = Set<Int>()
        var matches: [LineMatch] = []
        var unresolved: [Int] = []

        // Pass 1: amounts. Each cloud line takes the first free local line
        // with the same amount.
        for (cloudIndex, line) in cloud.enumerated() {
            guard let amount = line.cost?.amount,
                  let localIndex = local.indices.first(where: { index in
                      !taken.contains(index) && sameAmount(local[index].cost?.amount, amount)
                  }) else {
                unresolved.append(cloudIndex)
                continue
            }
            taken.insert(localIndex)
            matches.append(LineMatch(cloudIndex: cloudIndex, localIndex: localIndex, basis: .sameAmount))
        }

        // Pass 2: titles, over what is left on both sides.
        for cloudIndex in unresolved {
            let tokens = Self.tokens(cloud[cloudIndex].title)
            var best: (index: Int, score: Double)?
            for index in local.indices where !taken.contains(index) {
                let score = overlap(tokens, Self.tokens(local[index].title))
                if score >= titleThreshold, score > (best?.score ?? 0) {
                    best = (index, score)
                }
            }
            if let best {
                taken.insert(best.index)
                matches.append(LineMatch(cloudIndex: cloudIndex, localIndex: best.index, basis: .title))
            } else {
                matches.append(LineMatch(cloudIndex: cloudIndex, localIndex: nil, basis: .new))
            }
        }

        return matches.sorted { $0.cloudIndex < $1.cloudIndex }
    }

    private static func sameAmount(_ local: Decimal?, _ cloud: Decimal) -> Bool {
        guard let local else { return false }
        return abs(local - cloud) <= ConfirmConfidenceGate.crossCheckTolerance(amount: cloud)
    }

    /// Lowercased word tokens, digits kept (a part number is a strong token),
    /// one-character noise dropped.
    static func tokens(_ title: String) -> Set<String> {
        Set(title.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count > 1 })
    }

    /// Jaccard overlap of the two token sets; 0 when either is empty.
    static func overlap(_ a: Set<String>, _ b: Set<String>) -> Double {
        let union = a.union(b)
        guard !union.isEmpty else { return 0 }
        return Double(a.intersection(b).count) / Double(union.count)
    }
}
