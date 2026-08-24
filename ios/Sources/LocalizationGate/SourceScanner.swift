import Foundation

/// One string literal's span in the source text, plus its raw inner content.
/// A struct (not a tuple) so the gate itself does not trip the `large_tuple`
/// lint rule - a gate that fails lint gates nothing.
private struct GateSlice {
    let start: Int
    let end: Int
    let inner: String
}

private enum GateTokenKind {
    case code
    case lineComment
    case blockComment
    case string
}

private struct GateToken {
    let start: Int
    let end: Int
    let kind: GateTokenKind
    let inner: String?
}

/// Everything the scanning passes share, bundled so no pass needs more than a
/// handful of parameters.
private struct ScanContext {
    let file: String
    let text: String
    let code: [Character]
    let slices: [GateSlice]
    let innerByStart: [Int: String]
}

/// The lexer half of the gate: comment stripping, string-literal reading and
/// template building. Split from the scanning passes so each type stays under
/// the lint body-length budget.
private enum SourceTokenizer {

    /// Splits a source file into tokens, tracking comment and string state so
    /// `//` inside a literal and `"` inside a comment are handled correctly.
    static func tokenize(_ chars: [Character]) -> [GateToken] {
        var tokens: [GateToken] = []
        var index = 0
        let count = chars.count
        while index < count {
            if chars[index] == "/" && index + 1 < count && chars[index + 1] == "/" {
                let start = index
                while index < count && chars[index] != "\n" { index += 1 }
                tokens.append(GateToken(start: start, end: index, kind: .lineComment, inner: nil))
            } else if chars[index] == "/" && index + 1 < count && chars[index + 1] == "*" {
                let start = index
                index += 2
                while index + 1 < count && !(chars[index] == "*" && chars[index + 1] == "/") { index += 1 }
                index = min(index + 2, count)
                tokens.append(GateToken(start: start, end: index, kind: .blockComment, inner: nil))
            } else if chars[index] == "\"" {
                let start = index
                let literal = readStringLiteral(chars, from: start, count: count)
                tokens.append(GateToken(start: start, end: literal.end, kind: .string, inner: String(literal.inner)))
                // `readStringLiteral` never returns less than start + 1, so this
                // always advances - the scan cannot stall on a literal.
                index = literal.end
            } else {
                tokens.append(GateToken(start: index, end: index + 1, kind: .code, inner: nil))
                index += 1
            }
        }
        return tokens
    }

    /// Reads a string literal starting at `start` (a `"`), handling escapes
    /// and balanced `\(interpolation)` expressions. Returns the raw inner text
    /// and the index just past the closing quote.
    private static func readStringLiteral(_ chars: [Character],
                                          from start: Int,
                                          count: Int) -> (inner: [Character], end: Int) {
        var index = start + 1
        var inner: [Character] = []
        while index < count {
            let current = chars[index]
            if current == "\\" {
                if index + 1 < count && chars[index + 1] == "(" {
                    // Interpolation: consume the balanced expression.
                    inner.append("\\")
                    inner.append("(")
                    index += 2
                    var depth = 1
                    while index < count && depth > 0 {
                        let nested = chars[index]
                        inner.append(nested)
                        if nested == "(" {
                            depth += 1
                        } else if nested == ")" {
                            depth -= 1
                        }
                        index += 1
                    }
                } else if index + 1 < count {
                    inner.append(current)
                    inner.append(chars[index + 1])
                    index += 2
                } else {
                    inner.append(current)
                    index += 1
                }
            } else if current == "\"" {
                index += 1
                break
            } else {
                inner.append(current)
                index += 1
            }
        }
        return (inner, index)
    }

    /// Turns a literal's inner text into the key template the catalogue is
    /// keyed by: each `\(interpolation)` becomes a `%@` token and common
    /// escapes are decoded so `"L/100\n"` matches a catalogue value holding a
    /// real newline.
    static func keyTemplate(from inner: String) -> String {
        let chars = Array(inner)
        var out: [Character] = []
        var index = 0
        while index < chars.count {
            let current = chars[index]
            if current == "\\" && index + 1 < chars.count && chars[index + 1] == "(" {
                var depth = 1
                var cursor = index + 2
                while cursor < chars.count && depth > 0 {
                    if chars[cursor] == "(" {
                        depth += 1
                    } else if chars[cursor] == ")" {
                        depth -= 1
                    }
                    cursor += 1
                }
                out.append("%")
                out.append("@")
                index = cursor
            } else if current == "\\" && index + 1 < chars.count {
                out += decodeEscape(chars[index + 1])
                index += 2
            } else {
                out.append(current)
                index += 1
            }
        }
        return String(out)
    }

    private static func decodeEscape(_ next: Character) -> [Character] {
        switch next {
        case "n": return ["\n"]
        case "t": return ["\t"]
        case "r": return ["\r"]
        case "0": return ["\0"]
        case "\"": return ["\""]
        case "\\": return ["\\"]
        default: return ["\\", next]
        }
    }
}

/// Extracts the user-facing string key references from one Swift source file.
enum SourceScanner {

    /// User-facing call sites whose first argument is a literal key. Bare
    /// names get an identifier-boundary check so `MyText(` never matches
    /// `Text(`; dotted SwiftUI modifiers are matched on the dot.
    private static let barePrefixes: [String] = [
        "Text(",
        "String(localized:",
        "LocalizedStringKey(",
        "Button(",
        "Label(",
        "TextField(",
        "SecureField(",
        "Picker(",
        "Menu(",
        "Section(",
        // Codebase display wrappers - each forwards its first argument to
        // `Text(_: LocalizedStringKey)` (FieldRow, SectionEyebrow) or stores it
        // as a `LocalizedStringKey` label (figureRow).
        "FieldRow(",
        "SectionEyebrow(",
        "figureRow(label:",
        // The app's own catalogue lookup for composed rows. Its literals are
        // keys by construction - and unlike `Text(_: LocalizedStringKey)` they
        // are the half of the codebase that routes through `Text(_: String)`,
        // which does not localise at all. 58 call sites went unchecked until
        // this entry existed.
        "L10n.localize("
    ]
    private static let dottedPrefixes: [String] = [
        ".navigationTitle(",
        ".navigationBarTitle(",
        ".accessibilityLabel(",
        ".alert(",
        ".confirmationDialog("
    ]
    private static let localizedStringKeyType = "LocalizedStringKey"

    /// Extracts every user-facing key reference from one source file.
    static func references(inFile file: String, text: String) -> [LocalizedKeyReference] {
        let chars = Array(text)
        var code = chars
        var slices: [GateSlice] = []
        var innerByStart: [Int: String] = [:]
        for token in SourceTokenizer.tokenize(chars) {
            switch token.kind {
            case .lineComment, .blockComment:
                for index in token.start..<min(token.end, code.count) where code[index] != "\n" {
                    code[index] = " "
                }
            case .string:
                slices.append(GateSlice(start: token.start,
                                        end: token.end,
                                        inner: token.inner ?? ""))
                innerByStart[token.start] = token.inner ?? ""
            case .code:
                break
            }
        }
        let context = ScanContext(file: file, text: text, code: code,
                                  slices: slices, innerByStart: innerByStart)
        var refs = callSiteReferences(context: context)
        refs += propertyReferences(context: context)
        return refs
    }

    /// The `Text("literal")`-style pass: a prefix followed by a string literal
    /// that is the call's first argument. Positions inside string ranges are
    /// skipped so a user-facing literal containing e.g. `.alert("x")` is not
    /// re-scanned as a call site.
    private static func callSiteReferences(context: ScanContext) -> [LocalizedKeyReference] {
        var refs: [LocalizedKeyReference] = []
        var scan = 0
        while scan < context.code.count {
            if let slice = slice(at: scan, in: context.slices) {
                scan = slice.end
                continue
            }
            guard let after = matchCallSitePrefix(context.code, at: scan) else {
                scan += 1
                continue
            }
            appendReference(prefixAt: scan, after: after, context: context, refs: &refs)
            scan = after
        }
        return refs
    }

    /// The `LocalizedStringKey`-typed property pass: stored defaults
    /// (`var caption: LocalizedStringKey? = "…"`) and computed bodies
    /// (`var title: LocalizedStringKey { … }`), whose literals are keys by
    /// construction.
    private static func propertyReferences(context: ScanContext) -> [LocalizedKeyReference] {
        var refs: [LocalizedKeyReference] = []
        var scan = 0
        while scan < context.code.count {
            if let slice = slice(at: scan, in: context.slices) {
                scan = slice.end
                continue
            }
            guard matches(context.code, localizedStringKeyType, at: scan),
                  isIdentifierChar(context.code, at: scan - 1) == false,
                  isIdentifierChar(context.code, at: scan + localizedStringKeyType.count) == false,
                  isPropertyTypeAnnotation(context.code, at: scan) else {
                scan += 1
                continue
            }
            scan = consumePropertyDeclaration(from: scan + localizedStringKeyType.count,
                                              context: context,
                                              refs: &refs)
        }
        return refs
    }

    /// Handles the `=` (stored default) or `{` (computed body) that follows a
    /// `LocalizedStringKey` type annotation. Returns the next scan position.
    private static func consumePropertyDeclaration(from start: Int,
                                                   context: ScanContext,
                                                   refs: inout [LocalizedKeyReference]) -> Int {
        var cursor = start
        while cursor < context.code.count
            && (context.code[cursor] == " " || context.code[cursor] == "\t" || context.code[cursor] == "?") {
            cursor += 1
        }
        if cursor < context.code.count && context.code[cursor] == "=" {
            return consumeStoredDefault(cursor: cursor, context: context, refs: &refs)
        }
        if cursor < context.code.count && context.code[cursor] == "{" {
            let bodyEnd = computedBodyEnd(open: cursor, context: context)
            for slice in context.slices where slice.start > cursor && slice.end <= bodyEnd {
                let template = SourceTokenizer.keyTemplate(from: slice.inner)
                if !template.isEmpty {
                    refs.append(LocalizedKeyReference(keyTemplate: template,
                                                      file: context.file,
                                                      line: lineNumber(in: context.text, at: slice.start)))
                }
            }
            return bodyEnd + 1
        }
        return cursor
    }

    private static func consumeStoredDefault(cursor eq: Int,
                                             context: ScanContext,
                                             refs: inout [LocalizedKeyReference]) -> Int {
        var cursor = eq + 1
        while cursor < context.code.count
            && (context.code[cursor] == " " || context.code[cursor] == "\t") {
            cursor += 1
        }
        if cursor < context.code.count && context.code[cursor] == "\"",
           let inner = context.innerByStart[cursor], !inner.isEmpty {
            let template = SourceTokenizer.keyTemplate(from: inner)
            if !template.isEmpty {
                refs.append(LocalizedKeyReference(keyTemplate: template,
                                                  file: context.file,
                                                  line: lineNumber(in: context.text, at: cursor)))
            }
        }
        return cursor
    }

    /// Walks balanced braces from `open`, skipping string spans, and returns
    /// the index of the matching close brace.
    private static func computedBodyEnd(open: Int, context: ScanContext) -> Int {
        var depth = 0
        var cursor = open
        while cursor < context.code.count {
            if let slice = slice(at: cursor, in: context.slices) {
                cursor = slice.end
                continue
            }
            if context.code[cursor] == "{" {
                depth += 1
            } else if context.code[cursor] == "}" {
                depth -= 1
                if depth == 0 { return cursor }
            }
            cursor += 1
        }
        return cursor
    }

    /// Records one reference when a call-site prefix is immediately followed
    /// by a string literal.
    private static func appendReference(prefixAt prefix: Int,
                                        after: Int,
                                        context: ScanContext,
                                        refs: inout [LocalizedKeyReference]) {
        var cursor = after
        while cursor < context.code.count
            && (context.code[cursor] == " " || context.code[cursor] == "\t") {
            cursor += 1
        }
        guard cursor < context.code.count, context.code[cursor] == "\"",
              let inner = context.innerByStart[cursor], !inner.isEmpty else {
            return
        }
        let template = SourceTokenizer.keyTemplate(from: inner)
        if !template.isEmpty {
            refs.append(LocalizedKeyReference(keyTemplate: template,
                                              file: context.file,
                                              line: lineNumber(in: context.text, at: prefix)))
        }
    }

    /// Returns the index just past a matching call-site prefix at `index`, or
    /// nil when no prefix starts there.
    private static func matchCallSitePrefix(_ code: [Character], at index: Int) -> Int? {
        if isIdentifierChar(code, at: index - 1) == false {
            for prefix in barePrefixes where matches(code, prefix, at: index) {
                return index + prefix.count
            }
        }
        for prefix in dottedPrefixes where matches(code, prefix, at: index) {
            return index + prefix.count
        }
        return nil
    }

    /// True when `LocalizedStringKey` at `index` is the type of a variable
    /// declaration (`var`/`let name: LocalizedStringKey`) and not a parameter
    /// list or a computed return type annotation on its own.
    private static func isPropertyTypeAnnotation(_ code: [Character], at index: Int) -> Bool {
        // Walk backwards: spaces, then optional `?`, then `:`, then the name,
        // then the `var`/`let` keyword preceding it.
        var cursor = index - 1
        while cursor >= 0 && code[cursor] == " " { cursor -= 1 }
        if cursor >= 0 && code[cursor] == "?" { cursor -= 1 }
        while cursor >= 0 && code[cursor] == " " { cursor -= 1 }
        if cursor < 0 || code[cursor] != ":" { return false }
        cursor -= 1
        while cursor >= 0 && code[cursor] == " " { cursor -= 1 }
        guard cursor >= 0, isIdentifierChar(code, at: cursor) else { return false }
        while cursor >= 0 && isIdentifierChar(code, at: cursor) { cursor -= 1 }
        while cursor >= 0 && code[cursor] == " " { cursor -= 1 }
        guard cursor >= 0, isIdentifierChar(code, at: cursor) else { return false }
        let keywordEnd = cursor
        var keywordStart = keywordEnd
        while keywordStart >= 0 && isIdentifierChar(code, at: keywordStart) { keywordStart -= 1 }
        let keyword = String(code[(keywordStart + 1)...keywordEnd])
        return keyword == "var" || keyword == "let"
    }

    private static func slice(at index: Int, in slices: [GateSlice]) -> GateSlice? {
        slices.first { $0.start == index }
    }

    private static func matches(_ code: [Character], _ prefix: String, at index: Int) -> Bool {
        let prefixChars = Array(prefix)
        guard index + prefixChars.count <= code.count else { return false }
        for (offset, expected) in prefixChars.enumerated() where code[index + offset] != expected {
            return false
        }
        return true
    }

    private static func isIdentifierChar(_ chars: [Character], at index: Int) -> Bool {
        guard index >= 0, index < chars.count else { return false }
        let current = chars[index]
        return current.isLetter || current.isNumber || current == "_"
    }

    private static func lineNumber(in text: String, at index: Int) -> Int {
        var line = 1
        var seen = 0
        for current in text where seen < index {
            if current == "\n" { line += 1 }
            seen += 1
        }
        return line
    }
}
