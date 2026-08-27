import Foundation

/// One string literal inside a call's non-literal first argument (P5.3).
///
/// `localizes` records which `Text` initialiser the compiler routes through:
///   - `true` - a pure-literal ternary branch (`cond ? "A" : "B"`). SwiftUI
///     builds a `LocalizedStringKey` with a runtime key, so the literal IS
///     looked up in the catalogue and needs an entry like any other key.
///   - `false` - a literal inside a `String`-pinned expression (`x ?? "…"`,
///     `cond ? someString : "…"`, `"a" + "b"`). The `String` overload renders
///     it verbatim, so it is English-in-RU whatever the catalogue holds - the
///     defect the key-membership gate cannot see, because the key may exist
///     yet never be looked up.
struct CompoundStringLiteral: Equatable {
    let literal: String
    let file: String
    let line: Int
    let callSite: String
    let localizes: Bool
}

private enum ExpressionSegmentKind: Equatable {
    case condition
    case trueBranch
    case falseBranch
    case coalesceLeft
    case coalesceRight
    case whole
}

private struct ExpressionSegment: Equatable {
    let kind: ExpressionSegmentKind
    let range: Range<Int>
}

extension SourceScanner {

    /// The compound-argument pass (P5.3). `Text("literal")` is a key by
    /// construction and the normal pass already checks it; this pass handles
    /// the first argument that is NOT a literal but CONTAINS one - the shape
    /// behind the P1.4 and P4.7 RU defects ("АВГУСТ РАСХОДЫ", "с вашего
    /// телефон Android"), where runtime data and copy shared one expression.
    /// A literal in a `String`-typed expression renders English; a literal in
    /// a pure-literal ternary branch is still a key and only needs catalogue
    /// membership.
    ///
    /// Deliberate boundaries (so the blind spot stays known, not guessed):
    ///   - Only literals at parenthesis depth 0 are examined - direct operands
    ///     of the top-level expression. A literal inside a nested call
    ///     (`Text("Currency")` under `.accessibilityLabel`, a `String(format:)`
    ///     argument, a `joined(separator: ", ")`) is either a key the normal
    ///     pass already checks or plain data, not copy leaking through an
    ///     expression.
    ///   - A literal in a ternary's *condition* is compared, never rendered -
    ///     skipped.
    ///   - `Text(someVariable)` with no literal at all is invisible to any
    ///     scan: the value may be user data (correct) or an unlocalised key (a
    ///     bug), and only value-flow analysis could tell. Not reported; the
    ///     codebase rule recorded at the top of `L10n.swift` stands.
    static func compoundStringLiterals(file: String,
                                       context: ScanContext) -> [CompoundStringLiteral] {
        let code = context.code
        let slices = context.slices
        var result: [CompoundStringLiteral] = []
        var scan = 0
        while scan < code.count {
            if let slice = slice(at: scan, in: slices) {
                scan = slice.end
                continue
            }
            guard let after = matchCallSitePrefix(code, at: scan) else {
                scan += 1
                continue
            }
            defer { scan = after }
            var cursor = after
            while cursor < code.count && (code[cursor] == " " || code[cursor] == "\t") {
                cursor += 1
            }
            if cursor >= code.count || code[cursor] == "\"" { continue }
            if String(code[cursor..<min(cursor + 9, code.count)]) == "verbatim:" { continue }
            guard let close = argumentCloseParen(from: cursor, context: context) else { continue }
            let callSite = String(code[scan..<after])
            result += literals(in: cursor..<close, callSite: callSite,
                               file: file, context: context)
        }
        return result
    }

    /// String literals at parenthesis depth 0 inside `span` - the ones that
    /// participate directly in the top-level expression rather than sitting
    /// inside a nested call's argument list.
    private static func depthZeroSlices(in span: Range<Int>,
                                        context: ScanContext) -> [GateSlice] {
        var result: [GateSlice] = []
        var depth = 0
        var cursor = span.lowerBound
        while cursor < span.upperBound {
            if let slice = slice(at: cursor, in: context.slices) {
                if depth == 0 { result.append(slice) }
                cursor = slice.end
                continue
            }
            let char = context.code[cursor]
            if char == "(" {
                depth += 1
            } else if char == ")" {
                depth -= 1
            }
            cursor += 1
        }
        return result
    }

    private static func literals(in span: Range<Int>,
                                 callSite: String,
                                 file: String,
                                 context: ScanContext) -> [CompoundStringLiteral] {
        let segments = expressionSegments(in: span, context: context)
        var result: [CompoundStringLiteral] = []
        for slice in depthZeroSlices(in: span, context: context) {
            let inner = context.innerByStart[slice.start] ?? ""
            if inner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            let line = lineNumber(in: context.text, at: slice.start)
            guard let localizes = literalStatus(at: slice.start, segments: segments,
                                                context: context) else { continue }
            result.append(CompoundStringLiteral(literal: inner, file: file,
                                                line: line, callSite: callSite,
                                                localizes: localizes))
        }
        return result
    }

    /// Splits `span` into top-level expression segments: a ternary, a
    /// nil-coalescing, or the whole expression.
    private static func expressionSegments(in span: Range<Int>,
                                           context: ScanContext) -> [ExpressionSegment] {
        let code = context.code
        var cursor = span.lowerBound
        var depth = 0
        var singleQ: Int?
        var colon: Int?
        var doubleQ: Int?
        while cursor < span.upperBound {
            if let slice = slice(at: cursor, in: context.slices) {
                cursor = slice.end
                continue
            }
            let char = code[cursor]
            if char == "(" {
                depth += 1
                cursor += 1
                continue
            }
            if char == ")" {
                depth -= 1
                cursor += 1
                continue
            }
            if depth == 0 {
                if char == "?" && cursor + 1 < span.upperBound && code[cursor + 1] == "?" {
                    doubleQ = cursor
                    break
                }
                if char == "?" { singleQ = cursor }
                if char == ":" && singleQ != nil && colon == nil { colon = cursor }
            }
            cursor += 1
        }
        if let doubleQ {
            return [ExpressionSegment(kind: .coalesceLeft, range: span.lowerBound..<doubleQ),
                    ExpressionSegment(kind: .coalesceRight, range: (doubleQ + 2)..<span.upperBound)]
        }
        if let singleQ, let colon, colon > singleQ {
            return [ExpressionSegment(kind: .condition, range: span.lowerBound..<singleQ),
                    ExpressionSegment(kind: .trueBranch, range: (singleQ + 1)..<colon),
                    ExpressionSegment(kind: .falseBranch, range: (colon + 1)..<span.upperBound)]
        }
        return [ExpressionSegment(kind: .whole, range: span.lowerBound..<span.upperBound)]
    }

    /// Classifies a literal at `position`:
    ///   - nil - not reported (a ternary condition, rendered nowhere);
    ///   - true - a key (both ternary branches literal, or a `nil ?? "A"`);
    ///   - false - English-in-RU (a `String`-pinned expression).
    private static func literalStatus(at position: Int,
                                      segments: [ExpressionSegment],
                                      context: ScanContext) -> Bool? {
        guard let segment = segments.first(where: { position >= $0.range.lowerBound
            && position < $0.range.upperBound }) else {
            return false
        }
        switch segment.kind {
        case .condition:
            return nil
        case .trueBranch, .falseBranch:
            // `cond ? "A" : "B"` stays a literal expression (LocalizedStringKey);
            // `cond ? x : "B"` is pinned to String by the other branch, and the
            // literal branch renders English.
            let otherKind: ExpressionSegmentKind = segment.kind == .trueBranch ? .falseBranch : .trueBranch
            let other = segments.first { $0.kind == otherKind }
            let thisPure = isPureLiteral(segment.range, context: context)
            let otherPure = other.map { isPureLiteral($0.range, context: context) } ?? false
            return thisPure && otherPure
        case .coalesceRight:
            let leftText = segments.first { $0.kind == .coalesceLeft }
                .map { maskedText($0.range, context: context) } ?? ""
            let leftIsBareNil = leftText.trimmingCharacters(in: .whitespacesAndNewlines) == "nil"
            return leftIsBareNil && isPureLiteral(segment.range, context: context)
        case .coalesceLeft, .whole:
            return false
        }
    }

    /// True when a segment holds a single string literal and nothing else.
    private static func isPureLiteral(_ range: Range<Int>, context: ScanContext) -> Bool {
        var cursor = range.lowerBound
        while cursor < range.upperBound {
            if let slice = slice(at: cursor, in: context.slices) {
                cursor = slice.end
                continue
            }
            let char = context.code[cursor]
            if char == " " || char == "\t" || char == "\n" {
                cursor += 1
                continue
            }
            return false
        }
        return true
    }

    /// The segment's code with its string literals removed - used to tell a
    /// bare `nil` left operand from a variable left operand.
    private static func maskedText(_ range: Range<Int>, context: ScanContext) -> String {
        var out: [Character] = []
        var cursor = range.lowerBound
        while cursor < range.upperBound {
            if let slice = slice(at: cursor, in: context.slices) {
                cursor = slice.end
                continue
            }
            out.append(context.code[cursor])
            cursor += 1
        }
        return String(out)
    }

    /// The close parenthesis of the call whose argument starts at `start`,
    /// counting every nested parenthesis so the outer `)` is the one that
    /// takes the running depth below zero.
    private static func argumentCloseParen(from start: Int,
                                           context: ScanContext) -> Int? {
        var depth = 0
        var cursor = start
        while cursor < context.code.count {
            if let slice = slice(at: cursor, in: context.slices) {
                cursor = slice.end
                continue
            }
            let char = context.code[cursor]
            if char == "(" {
                depth += 1
            } else if char == ")" {
                depth -= 1
                if depth < 0 { return cursor }
            }
            cursor += 1
        }
        return nil
    }
}
