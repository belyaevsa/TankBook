import Foundation

/// RV.164 - the source-scan half of `docs/ERRORS.md`'s fourth audit question:
/// **does the next step EXIST?** The three original questions ask what happened,
/// what the preselected next step is, and what happens if it is ignored. None
/// asks whether the route the copy names is a screen the app actually carries,
/// which is how `RV.98`'s alert promised a deleted car "moves to Recently
/// deleted" while the view never queried deleted vehicles.
///
/// The mechanisable slice is narrow on purpose. A route NAMED in error copy is
/// written after the `→` the doc already uses (`View → Reminders`); the scanner
/// extracts it and checks it against the screens `docs/SCREENMAP.md` carries
/// (`ScreenRouteScanner.screenNames` plus its no-route marker). A route whose
/// phrase does not start with a known screen - and is not a reasoned non-route
/// or a `.md` cross-reference - is reported.
///
/// THE RESIDUE, stated so it is not overclaimed: this checks that the route
/// EXISTS, never that it does what the copy promises. `RV.98`'s copy named a
/// real screen; the missing half was the car row inside it, and no route scan
/// can see that. That class is the journey walk's manual check (`REVIEW-SCENARIO`
/// question 5). The RV.98 test below pins the limit rather than pretending the
/// guard catches it.
///
/// A SECOND RESIDUE, added after RV.239: the scan proves a route EXISTS in
/// SCREENMAP, never that a `NavigationLink` reaches a destination from where it
/// is rendered. RV.239's import rows were `NavigationLink(value:)` inside the
/// sign-in sheet, and the only `navigationDestination(for: Route.self)` was on
/// the tab stack - the route existed, the link was hittable, and the tap
/// navigated nowhere. A cheap source scan cannot catch this class: whether a
/// link resolves depends on its presentation context (which `NavigationStack`,
/// if any, encloses it at render time), and the presenting sheet and the link
/// routinely live in different files (`SettingsView` presents the sheet; the
/// row is in `RestoreFailureViews`). A file-local "has `.sheet` but no
/// `navigationDestination`" heuristic would false-positive on `SettingsView`
/// and `WelcomeRootView`, whose `NavigationLink(value:)` rows sit on pushed
/// screens with a real destination. The reachable check is the L4 tap, and the
/// journey walk.
enum ErrorRouteScanner {

    /// One route named by copy that SCREENMAP does not carry.
    struct RouteReference: Equatable {
        let route: String
        let line: Int
    }

    /// A `→`-introduced phrase that is deliberately not a screen, with the reason
    /// a human wrote. A bare entry is a skip list and fails the self-check.
    struct NonRoute {
        let phrase: String
        let reason: String
    }

    // MARK: - The scan

    /// Route references that are not known screens and not reasoned non-routes,
    /// in document order. This is the failing set.
    static func unknownRoutes(in text: String, knownScreens: Set<String>,
                              nonRoutes: [NonRoute] = []) -> [RouteReference] {
        let allowed = Set(nonRoutes.map(\.phrase))
        var found: [RouteReference] = []
        for (offset, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = String(rawLine)
            for phrase in routePhrases(in: line) {
                if allowed.contains(phrase) { continue }
                if knownScreens.contains(where: { startsWithScreen($0, phrase) }) { continue }
                found.append(RouteReference(route: phrase, line: offset + 1))
            }
        }
        return found
    }

    /// Every known screen named anywhere in the copy, arrow or not. This is the
    /// non-vacuity half: the RV.98 teeth below prove the scanner reads a real
    /// promise ("Recently deleted") out of the historical string.
    static func namedScreens(in text: String, knownScreens: Set<String>) -> [String] {
        knownScreens.sorted().filter { containsWord($0, in: text) }
    }

    /// Every route-shaped phrase, known or not. Used only to tell a stale
    /// non-route (its phrase left the copy) from a live one.
    static func routeCandidates(in text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .flatMap { routePhrases(in: String($0)) }
    }

    /// The route-shaped phrases in one line: after a `→`, and after the
    /// navigation verbs error copy uses when it has no arrow (`It moves to
    /// Recently deleted` - RV.98's own sentence). A phrase is taken up to the
    /// next delimiter so `Recently deleted, 30 days` yields `Recently deleted`;
    /// a phrase that starts lowercase, with a digit, or with a quote is not a
    /// route by the doc's convention (`Filled rows → a toast`, `6.9 → 6.8`). An
    /// arrow whose left side is a `.md` reference is a document cross-reference,
    /// never a route.
    static func routePhrases(in line: String) -> [String] {
        arrowPhrases(in: line) + verbPhrases(in: line)
    }

    static func arrowPhrases(in line: String) -> [String] {
        var phrases: [String] = []
        var searchStart = line.startIndex
        while let arrow = line.range(of: "→", range: searchStart..<line.endIndex) {
            let before = line[line.startIndex..<arrow.lowerBound]
            let segmentBefore = before
                .split(whereSeparator: { "·,|(".contains($0) })
                .last.map(String.init) ?? ""
            searchStart = arrow.upperBound
            if segmentBefore.contains(".md") { continue }
            if let phrase = delimitedPhrase(from: line[arrow.upperBound...]) {
                phrases.append(phrase)
            }
        }
        return phrases
    }

    /// The navigation verbs the catalog uses without an arrow. Only the phrase
    /// directly after the verb is considered, so ordinary prose (`goes to the
    /// garage`) is ignored by the capital-letter rule.
    static let navigationVerbs = ["moves to", "opens", "goes to", "returns to",
                                  "lands on", "routes to", "leads to"]

    static func verbPhrases(in line: String) -> [String] {
        var phrases: [String] = []
        for verb in navigationVerbs {
            var searchStart = line.startIndex
            while let range = line.range(of: verb, range: searchStart..<line.endIndex) {
                searchStart = range.upperBound
                if let phrase = delimitedPhrase(from: line[range.upperBound...]) {
                    phrases.append(phrase)
                }
            }
        }
        return phrases
    }

    /// The route-shaped phrase at the start of `rest`, cut at the next delimiter
    /// and rejected when it does not start like a route name.
    private static func delimitedPhrase(from rest: Substring) -> String? {
        var text = rest.drop(while: { $0 == " " })
        if let cut = text.firstIndex(where: { "·,(.;|)".contains($0) }) {
            text = text[..<cut]
        }
        let phrase = text.trimmingCharacters(in: .whitespaces)
        guard let first = phrase.first, first.isLetter, first.isUppercase else { return nil }
        return phrase
    }

    /// Whether `phrase` begins with the screen name as a whole token - so
    /// `Edit entry with discrepancy pre-highlighted` starts with `Edit entry`,
    /// but `Edit entryway` is a different word and does not.
    static func startsWithScreen(_ screen: String, _ phrase: String) -> Bool {
        guard phrase.hasPrefix(screen) else { return false }
        let after = phrase.index(phrase.startIndex, offsetBy: screen.count)
        return after == phrase.endIndex || !isIdentifier(phrase[after])
    }

    static func containsWord(_ needle: String, in haystack: String) -> Bool {
        var searchStart = haystack.startIndex
        while let range = haystack.range(of: needle, range: searchStart..<haystack.endIndex) {
            let beforeOK = range.lowerBound == haystack.startIndex
                || !isIdentifier(haystack[haystack.index(before: range.lowerBound)])
            let afterOK = range.upperBound == haystack.endIndex
                || !isIdentifier(haystack[range.upperBound])
            if beforeOK && afterOK { return true }
            searchStart = range.upperBound
        }
        return false
    }

    private static func isIdentifier(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }

    // MARK: - Self-checks

    static func reasonProblem(in nonRoute: NonRoute) -> String? {
        guard nonRoute.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return "non-route \(nonRoute.phrase) carries no reason - a bare entry is a skip list, "
            + "not a recorded decision"
    }

    /// A non-route that no longer matches any `→` phrase in the copy - the
    /// phrase left the doc. A stale entry hides the next unknown route.
    static func staleNonRoutes(_ nonRoutes: [NonRoute], candidates: [String]) -> [String] {
        nonRoutes.map(\.phrase).filter { !candidates.contains($0) }.sorted()
    }
}
