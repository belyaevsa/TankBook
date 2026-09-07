import Foundation

/// What a string literal does when a helper call binds it to a parameter that
/// the helper forwards into a text-rendering initialiser (RV.102).
enum RoutedLiteralKind: Equatable {
    /// The destination parameter is `String`, so the literal renders verbatim
    /// through the `Text(_: String)`-family overload - English-in-RU whatever
    /// the catalogue holds. This is the defect class `HomeEmptyStates.quickAction`
    /// shipped: "Select car" and "Type it" were catalogue keys that reached the
    /// screen through a `String` parameter and so never looked anything up.
    case flagsEnglish
    /// The destination parameter is `LocalizedStringKey`, so the literal is an
    /// ordinary key and needs catalogue membership like any `Text("…")` call.
    case checkMembership
}

/// One literal at a helper call site that flows into a text renderer through
/// the helper's parameter list (RV.102), or one bound to a `String` local that
/// a text renderer then draws. Both render English in Russian.
struct RoutedLiteral: Equatable {
    let keyTemplate: String
    let file: String
    let line: Int
    let kind: RoutedLiteralKind
}

private enum ForwardParamKind: Equatable {
    case string
    case localizedStringKey
    case other
}

/// One parameter of a same-file helper, enough to bind a call site's argument.
private struct ForwardParam {
    /// The external label; `_` when the parameter is unlabeled (positional).
    let label: String
    let localName: String
    let kind: ForwardParamKind
}

/// A same-file helper whose parameter list the callsite pass needs.
private struct FunctionScan {
    let name: String
    let openParen: Int
    let params: [ForwardParam]
    /// Parallel to `params`: true when the parameter is forwarded as the whole
    /// content of a `Text`/`Label`/`Button` call inside the function body.
    let forwarded: [Bool]
}

/// A `let name = "literal"` local that a text renderer later draws. Bound to a
/// string literal it is `String`-typed by construction, so it renders verbatim.
private struct LiteralBoundLocal {
    let name: String
    let container: Int
    let declIndex: Int
    let line: Int
    let keyTemplate: String
}

/// A string literal found as a bound argument, plus whether it interpolates.
private struct BoundLiteralValue {
    let template: String
    let line: Int
    let isInterpolated: Bool
}

extension SourceScanner {

    // MARK: - Entry point

    /// The RV.102 pass: a string literal that reaches a text renderer only by
    /// being routed through a `String` type. Two shapes:
    ///   1. a same-file helper whose `String` parameter is forwarded into
    ///      `Label`/`Text`/`Button`, called with a literal for that parameter
    ///      (the `quickAction` defect);
    ///   2. a `let name = "literal"` local that `Label`/`Text`/`Button` draws.
    /// Both render the literal verbatim, so a catalogue entry - even a correct,
    /// translated one - never applies. The `LocalizedStringKey` twin of shape 1
    /// is a key by construction and is emitted as .checkMembership so the gate
    /// treats a learned helper exactly like a `Text("…")` call site.
    static func routedLiterals(inFile file: String, text: String) -> [RoutedLiteral] {
        let context = scanContext(for: file, text: text)
        var result = literalBoundLocalRenders(context: context)
        for function in functionScans(context: context) {
            result += helperCallsiteLiterals(function: function, context: context)
        }
        return deduplicated(result)
    }

    /// Deduplicates by (file, line, keyTemplate, kind) so two emission paths
    /// can never report the same literal twice when they overlap.
    private static func deduplicated(_ literals: [RoutedLiteral]) -> [RoutedLiteral] {
        var seen = Set<String>()
        var result: [RoutedLiteral] = []
        for literal in literals {
            let identity = "\(literal.file)|\(literal.line)|\(literal.keyTemplate)|\(literal.kind)"
            guard seen.insert(identity).inserted else { continue }
            result.append(literal)
        }
        return result
    }

    // MARK: - Shape 1: same-file helpers whose parameters forward into a renderer

    /// Every concrete function declaration in the file, with its forwarded
    /// parameters resolved from the body.
    private static func functionScans(context: ScanContext) -> [FunctionScan] {
        let code = context.code
        var result: [FunctionScan] = []
        var scan = 0
        while scan < code.count {
            if let slice = slice(at: scan, in: context.slices) {
                scan = slice.end
                continue
            }
            guard matches(code, "func", at: scan),
                  !isIdentifierChar(code, at: scan - 1),
                  !isIdentifierChar(code, at: scan + 4) else {
                scan += 1
                continue
            }
            guard let parsed = parseFunctionDeclaration(context: context, funcIndex: scan) else {
                scan += 1
                continue
            }
            result.append(parsed.function)
            scan = parsed.bodyEnd + 1
        }
        return result
    }

    /// Parses the declaration starting at `func`, returning the function and
    /// the end of its body so the enclosing scan skips nested declarations.
    private static func parseFunctionDeclaration(
        context: ScanContext,
        funcIndex: Int
    ) -> (function: FunctionScan, bodyEnd: Int)? {
        let code = context.code
        var cursor = funcIndex + 4
        while cursor < code.count && isSpace(code[cursor]) { cursor += 1 }
        guard cursor < code.count, isIdentifierChar(code, at: cursor) else { return nil }
        let (name, afterName) = readIdentifier(code, from: cursor)
        cursor = skipAngleBrackets(from: afterName, context: context)
        guard cursor < code.count, code[cursor] == "(",
              let closeParen = parenClose(open: cursor, context: context) else { return nil }
        let params = parseParams(from: cursor + 1, to: closeParen, context: context)
        guard let bodyOpen = firstBraceAfter(closeParen, context: context),
              let bodyEnd = braceEnd(open: bodyOpen, context: context) else { return nil }
        let forwarded = params.map { parameter in
            parameter.kind != .other
                && forwardsToTextRenderer(parameter.localName,
                                          bodyStart: bodyOpen + 1,
                                          bodyEnd: bodyEnd,
                                          context: context)
        }
        return (FunctionScan(name: name, openParen: cursor, params: params, forwarded: forwarded),
                bodyEnd)
    }

    /// `func name<T>(…)`: skips a balanced generic clause between the name and
    /// the parameter list, when one is present.
    private static func skipAngleBrackets(from start: Int, context: ScanContext) -> Int {
        var cursor = start
        while cursor < context.code.count && isSpace(context.code[cursor]) { cursor += 1 }
        guard cursor < context.code.count, context.code[cursor] == "<" else { return start }
        var depth = 0
        while cursor < context.code.count {
            let char = context.code[cursor]
            if char == "<" { depth += 1 }
            if char == ">" { depth -= 1 }
            cursor += 1
            if depth == 0 { return cursor }
        }
        return start
    }

    /// The index of the first `{` after `start` - the body of a concrete
    /// function. A declaration without a body (a protocol requirement) returns
    /// nil because no brace follows.
    private static func firstBraceAfter(_ start: Int, context: ScanContext) -> Int? {
        var cursor = start
        while cursor < context.code.count {
            if let slice = slice(at: cursor, in: context.slices) {
                cursor = slice.end
                continue
            }
            if context.code[cursor] == "{" { return cursor }
            cursor += 1
        }
        return nil
    }

    private static func parseParams(from start: Int, to end: Int,
                                    context: ScanContext) -> [ForwardParam] {
        var params: [ForwardParam] = []
        for segment in topLevelRanges(start: start, end: end, context: context) {
            guard let parameter = parseParam(segment, context: context) else { continue }
            params.append(parameter)
        }
        return params
    }

    /// One parameter segment `label local: Type` -> `ForwardParam`. The type is
    /// taken up to the first top-level `=` so defaults never confuse it.
    private static func parseParam(_ range: Range<Int>, context: ScanContext) -> ForwardParam? {
        guard range.lowerBound < range.upperBound,
              let colon = firstTopLevel(range: range, needle: ":", context: context) else {
            return nil
        }
        let before = String(context.code[range.lowerBound..<colon])
            .trimmingCharacters(in: .whitespaces)
        guard before != "_", !before.isEmpty else { return nil }
        let tokens = before.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard let lastName = tokens.last else { return nil }
        let label: String
        if tokens.count == 1 {
            label = String(tokens[0])
        } else if tokens.count == 2 {
            label = tokens[0] == "_" ? "_" : String(tokens[0])
        } else {
            return nil
        }
        let type = typeText(from: colon + 1, upperBound: range.upperBound, context: context)
        let kind: ForwardParamKind
        switch type {
        case "String": kind = .string
        case "LocalizedStringKey": kind = .localizedStringKey
        default: kind = .other
        }
        return ForwardParam(label: label, localName: String(lastName), kind: kind)
    }

    /// The declared type of a parameter, cut at the first top-level `=` (a
    /// default value) and trimmed.
    private static func typeText(from start: Int, upperBound: Int,
                                 context: ScanContext) -> String {
        let text: String
        if let equals = firstTopLevel(range: start..<upperBound, needle: "=",
                                      context: context) {
            text = String(context.code[start..<equals])
        } else {
            text = String(context.code[start..<upperBound])
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    /// The index of the first `needle` at parenthesis/bracket/brace depth zero
    /// inside `range`, or nil. Single-character needles only.
    private static func firstTopLevel(range: Range<Int>, needle: Character,
                                      context: ScanContext) -> Int? {
        var paren = 0
        var brace = 0
        var bracket = 0
        var cursor = range.lowerBound
        while cursor < range.upperBound {
            if let slice = slice(at: cursor, in: context.slices) {
                cursor = slice.end
                continue
            }
            let char = context.code[cursor]
            if char == needle, paren == 0, brace == 0, bracket == 0 { return cursor }
            switch char {
            case "(": paren += 1
            case ")": paren -= 1
            case "{": brace += 1
            case "}": brace -= 1
            case "[": bracket += 1
            case "]": bracket -= 1
            default: break
            }
            cursor += 1
        }
        return nil
    }

    /// Splits `start..<end` on commas that are not nested inside any
    /// parenthesis, bracket, brace or string span.
    private static func topLevelRanges(start: Int, end: Int,
                                       context: ScanContext) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var segmentStart = start
        var paren = 0
        var brace = 0
        var bracket = 0
        var cursor = start
        while cursor < end {
            if let slice = slice(at: cursor, in: context.slices) {
                cursor = slice.end
                continue
            }
            let char = context.code[cursor]
            switch char {
            case "(": paren += 1
            case ")": paren -= 1
            case "{": brace += 1
            case "}": brace -= 1
            case "[": bracket += 1
            case "]": bracket -= 1
            default:
                if char == ",", paren == 0, brace == 0, bracket == 0 {
                    ranges.append(trimmedRange(segmentStart, cursor, context: context))
                    segmentStart = cursor + 1
                }
            }
            cursor += 1
        }
        if segmentStart < end { ranges.append(trimmedRange(segmentStart, end, context: context)) }
        return ranges
    }

    private static func trimmedRange(_ start: Int, _ end: Int,
                                     context: ScanContext) -> Range<Int> {
        var lower = start
        var upper = end
        while lower < upper && isSpace(context.code[lower]) { lower += 1 }
        while upper > lower && isSpace(context.code[upper - 1]) { upper -= 1 }
        return lower..<upper
    }

    /// True when the parameter appears as the whole content argument of a
    /// `Text`/`Label`/`Button` call in the function body - the forwarding that
    /// makes a caller's literal reach a text renderer through this parameter.
    private static func forwardsToTextRenderer(_ name: String, bodyStart: Int,
                                               bodyEnd: Int,
                                               context: ScanContext) -> Bool {
        let code = context.code
        var cursor = bodyStart
        while cursor < bodyEnd {
            if let slice = slice(at: cursor, in: context.slices) {
                cursor = slice.end
                continue
            }
            guard !isIdentifierChar(code, at: cursor - 1),
                  let prefixLength = textRenderPrefixLength(code, at: cursor) else {
                cursor += 1
                continue
            }
            guard let contentStart = firstNonSpace(after: cursor + prefixLength,
                                                   context: context),
                  contentStart < bodyEnd, isIdentifierChar(code, at: contentStart) else {
                cursor += 1
                continue
            }
            let (token, afterToken) = readIdentifier(code, from: contentStart)
            if token == name, afterToken < bodyEnd,
               code[afterToken] == ")" || code[afterToken] == "," {
                return true
            }
            cursor += 1
        }
        return false
    }

    /// The length of a `Text(`/`Label(`/`Button(` prefix at `index`, or nil
    /// when the position does not open a text-rendering content argument.
    private static func textRenderPrefixLength(_ code: [Character], at index: Int) -> Int? {
        for prefix in ["Text(", "Label(", "Button("] where matches(code, prefix, at: index) {
            return prefix.count
        }
        return nil
    }

    /// Every call to `function` in the file whose argument for a forwarded
    /// parameter is a string literal. A literal bound to a `String` forward
    /// renders English-in-RU; one bound to a `LocalizedStringKey` forward is a
    /// key by construction and is checked like any other.
    private static func helperCallsiteLiterals(function: FunctionScan,
                                               context: ScanContext) -> [RoutedLiteral] {
        let code = context.code
        guard function.forwarded.contains(true) else { return [] }
        var result: [RoutedLiteral] = []
        var scan = 0
        while scan < code.count {
            if let slice = slice(at: scan, in: context.slices) {
                scan = slice.end
                continue
            }
            let afterName = scan + function.name.count
            guard matches(code, function.name, at: scan),
                  !isIdentifierChar(code, at: scan - 1),
                  code[max(scan - 1, 0)] != ".",
                  scan != function.openParen,
                  afterName < code.count, code[afterName] == "(",
                  let close = parenClose(open: afterName, context: context) else {
                scan += 1
                continue
            }
            result += bindLiteralArguments(function: function,
                                           callStart: afterName + 1,
                                           callEnd: close,
                                           context: context)
            scan = close + 1
        }
        return result
    }

    /// Walks the call's argument segments in parallel with the parameter list
    /// and reports each forwarded parameter that received a string literal.
    private static func bindLiteralArguments(function: FunctionScan,
                                             callStart: Int,
                                             callEnd: Int,
                                             context: ScanContext) -> [RoutedLiteral] {
        var result: [RoutedLiteral] = []
        var used = Set<Int>()
        var positional = 0
        for segment in topLevelRanges(start: callStart, end: callEnd, context: context) {
            guard let binding = bindSegment(segment,
                                            function: function,
                                            context: context,
                                            used: &used,
                                            positional: &positional) else { continue }
            let parameter = function.params[binding.paramIndex]
            guard function.forwarded[binding.paramIndex],
                  parameter.kind == .string || parameter.kind == .localizedStringKey,
                  let literal = literalValue(from: binding.valueStart,
                                             to: segment.upperBound,
                                             context: context),
                  // An interpolated literal is a composed value, not copy: a
                  // `value:` argument of `"\(count)"` renders dynamic data and
                  // must not be flagged (the false-positive guard). Only pure
                  // copy can render English-in-RU.
                  !literal.isInterpolated else { continue }
            let kind: RoutedLiteralKind = parameter.kind == .string
                ? .flagsEnglish : .checkMembership
            result.append(RoutedLiteral(keyTemplate: literal.template,
                                        file: context.file,
                                        line: literal.line,
                                        kind: kind))
        }
        return result
    }

    /// Assigns one argument segment to a parameter: by external label when the
    /// segment begins `label:`, otherwise to the next unlabeled (`_`) parameter.
    /// Returns the parameter index and where its value begins.
    private static func bindSegment(_ segment: Range<Int>,
                                    function: FunctionScan,
                                    context: ScanContext,
                                    used: inout Set<Int>,
                                    positional: inout Int) -> (paramIndex: Int, valueStart: Int)? {
        if let colon = leadingLabelColon(segment, context: context) {
            let label = String(context.code[segment.lowerBound..<colon])
                .trimmingCharacters(in: .whitespaces)
            guard let index = function.params.indices.first(where: {
                function.params[$0].label == label && !used.contains($0)
            }) else { return nil }
            used.insert(index)
            var cursor = colon + 1
            while cursor < segment.upperBound && isSpace(context.code[cursor]) { cursor += 1 }
            return (index, cursor)
        }
        while positional < function.params.count && used.contains(positional) { positional += 1 }
        guard positional < function.params.count,
              function.params[positional].label == "_" else { return nil }
        let index = positional
        used.insert(index)
        positional += 1
        var cursor = segment.lowerBound
        while cursor < segment.upperBound && isSpace(context.code[cursor]) { cursor += 1 }
        return (index, cursor)
    }

    /// The index of the `:` in a leading `label:` at the start of a segment, or
    /// nil when the segment does not begin with one (a positional argument, an
    /// expression, a literal).
    private static func leadingLabelColon(_ segment: Range<Int>,
                                          context: ScanContext) -> Int? {
        var cursor = segment.lowerBound
        while cursor < segment.upperBound && isIdentifierChar(context.code, at: cursor) {
            cursor += 1
        }
        guard cursor > segment.lowerBound else { return nil }
        var after = cursor
        while after < segment.upperBound && isSpace(context.code[after]) { after += 1 }
        guard after < segment.upperBound, context.code[after] == ":" else { return nil }
        return after
    }

    /// A string literal at `start` (the value of a bound argument), or nil.
    private static func literalValue(from start: Int, to end: Int,
                                     context: ScanContext) -> BoundLiteralValue? {
        guard start < end, context.code[start] == "\"",
              let inner = context.innerByStart[start], !inner.isEmpty else { return nil }
        return BoundLiteralValue(template: SourceTokenizer.keyTemplate(from: inner),
                                 line: lineNumber(in: context.text, at: start),
                                 isInterpolated: inner.contains("\\("))
    }

    // MARK: - Shape 2: a `let name = "literal"` local that a renderer draws

    /// Single forward pass over the file tracking brace containers. When a
    /// `Text`/`Label`/`Button` content argument is a bare identifier bound by an
    /// enclosing `let` to a pure string literal, the literal renders verbatim.
    private static func literalBoundLocalRenders(context: ScanContext) -> [RoutedLiteral] {
        let code = context.code
        var braceStack: [Int] = []
        var candidates: [LiteralBoundLocal] = []
        var result: [RoutedLiteral] = []
        var cursor = 0
        while cursor < code.count {
            if let slice = slice(at: cursor, in: context.slices) {
                cursor = slice.end
                continue
            }
            let char = code[cursor]
            if char == "{" {
                braceStack.append(cursor)
                cursor += 1
                continue
            }
            if char == "}" {
                if !braceStack.isEmpty { braceStack.removeLast() }
                cursor += 1
                continue
            }
            if let parsed = parseCopyLocal(at: cursor,
                                           container: braceStack.last ?? -1,
                                           context: context) {
                candidates.append(parsed.local)
                cursor = parsed.next
                continue
            }
            guard !isIdentifierChar(code, at: cursor - 1),
                  let prefixLength = textRenderPrefixLength(code, at: cursor),
                  let contentStart = firstNonSpace(after: cursor + prefixLength,
                                                   context: context),
                  contentStart < code.count, isIdentifierChar(code, at: contentStart) else {
                cursor += 1
                continue
            }
            let (name, afterToken) = readIdentifier(code, from: contentStart)
            if afterToken < code.count, code[afterToken] == ")" || code[afterToken] == ",",
               let match = nearestCopyCandidate(named: name,
                                                usageIndex: cursor,
                                                braceStack: braceStack,
                                                candidates: candidates) {
                result.append(RoutedLiteral(keyTemplate: match.keyTemplate,
                                            file: context.file,
                                            line: match.line,
                                            kind: .flagsEnglish))
            }
            cursor += 1
        }
        return result
    }

    /// Parses a `let name = "literal"` (or `let name: String = "literal"`)
    /// starting at `let`. `String`-typed by construction when the annotation is
    /// `String` or absent; a `LocalizedStringKey` annotation is a key by
    /// construction and left to the existing membership pass. Only pure,
    /// non-interpolated literals count: an interpolated `String` local is
    /// usually a composed value, not copy.
    private static func parseCopyLocal(at letIndex: Int, container: Int,
                                       context: ScanContext) -> (local: LiteralBoundLocal, next: Int)? {
        let code = context.code
        guard matches(code, "let", at: letIndex),
              !isIdentifierChar(code, at: letIndex - 1),
              !isIdentifierChar(code, at: letIndex + 3) else { return nil }
        var cursor = letIndex + 3
        while cursor < code.count && isSpace(code[cursor]) { cursor += 1 }
        guard cursor < code.count, isIdentifierChar(code, at: cursor) else { return nil }
        let (name, afterName) = readIdentifier(code, from: cursor)
        cursor = afterName
        while cursor < code.count && isSpace(code[cursor]) { cursor += 1 }
        var annotation = ""
        if cursor < code.count, code[cursor] == ":" {
            cursor += 1
            let annotationStart = cursor
            while cursor < code.count && code[cursor] != "=" {
                if let slice = slice(at: cursor, in: context.slices) { cursor = slice.end; continue }
                cursor += 1
            }
            annotation = String(code[annotationStart..<cursor]).trimmingCharacters(in: .whitespaces)
        }
        if !annotation.isEmpty && annotation != "String" { return nil }
        while cursor < code.count && isSpace(code[cursor]) { cursor += 1 }
        guard cursor < code.count, code[cursor] == "=" else { return nil }
        cursor += 1
        while cursor < code.count && isSpace(code[cursor]) { cursor += 1 }
        guard cursor < code.count, code[cursor] == "\"",
              let inner = context.innerByStart[cursor],
              !inner.isEmpty,
              !inner.contains("\\("),
              inner.rangeOfCharacter(from: .letters) != nil else { return nil }
        let end = slice(at: cursor, in: context.slices)?.end ?? cursor + 1
        let local = LiteralBoundLocal(name: name,
                                      container: container,
                                      declIndex: letIndex,
                                      line: lineNumber(in: context.text, at: cursor),
                                      keyTemplate: SourceTokenizer.keyTemplate(from: inner))
        return (local, end)
    }

    /// The closest candidate with the matching name declared before `usageIndex`
    /// in a container on the current brace stack (an ancestor of the use).
    private static func nearestCopyCandidate(named name: String,
                                             usageIndex: Int,
                                             braceStack: [Int],
                                             candidates: [LiteralBoundLocal]) -> LiteralBoundLocal? {
        var best: LiteralBoundLocal?
        for candidate in candidates where candidate.name == name
            && candidate.declIndex < usageIndex
            && braceStack.contains(candidate.container) {
            if best == nil || candidate.declIndex > best!.declIndex { best = candidate }
        }
        return best
    }

    // MARK: - Shared helpers

    private static func readIdentifier(_ code: [Character], from index: Int) -> (String, Int) {
        var cursor = index
        var name: [Character] = []
        while cursor < code.count && isIdentifierChar(code, at: cursor) {
            name.append(code[cursor])
            cursor += 1
        }
        return (String(name), cursor)
    }

    /// The index of the parenthesis that closes the one opened at `open`.
    private static func parenClose(open: Int, context: ScanContext) -> Int? {
        var depth = 0
        var cursor = open
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
                if depth == 0 { return cursor }
            }
            cursor += 1
        }
        return nil
    }

    /// The index of the brace that closes the one opened at `open`.
    private static func braceEnd(open: Int, context: ScanContext) -> Int? {
        var depth = 0
        var cursor = open
        while cursor < context.code.count {
            if let slice = slice(at: cursor, in: context.slices) {
                cursor = slice.end
                continue
            }
            let char = context.code[cursor]
            if char == "{" {
                depth += 1
            } else if char == "}" {
                depth -= 1
                if depth == 0 { return cursor }
            }
            cursor += 1
        }
        return nil
    }

    private static func firstNonSpace(after index: Int, context: ScanContext) -> Int? {
        var cursor = index
        while cursor < context.code.count && isSpace(context.code[cursor]) { cursor += 1 }
        return cursor < context.code.count ? cursor : nil
    }

    private static func isSpace(_ char: Character) -> Bool {
        char == " " || char == "\t" || char == "\n" || char == "\r"
    }
}
