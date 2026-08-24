import Foundation
import LocalizationGate

// P0.3 localization gate - CI step that fails the build on a user-facing
// string the String Catalog cannot resolve in Russian.
//
//   swift run localization-gate
//   swift run localization-gate --sources ios/App/Sources
//     --catalogue ios/App/Sources/Localizable.xcstrings
//
// Defaults resolve relative to the working directory, and also try an `ios/`
// prefix so the tool works from both the repo root and `ios/`. Exit code is
// the gate: 0 = clean, 1 = violations, 2 = cannot read inputs.

private func resolve(_ path: String) -> URL {
    let fm = FileManager.default
    if fm.fileExists(atPath: path) { return URL(fileURLWithPath: path) }
    let prefixed = "ios/" + path
    if fm.fileExists(atPath: prefixed) { return URL(fileURLWithPath: prefixed) }
    return URL(fileURLWithPath: path)
}

var sourcesPath = "App/Sources"
var cataloguePath = "App/Sources/Localizable.xcstrings"

var args = Array(CommandLine.arguments.dropFirst())
while !args.isEmpty {
    let flag = args.removeFirst()
    switch flag {
    case "--sources":
        guard !args.isEmpty else { fatalError("--sources needs a path") }
        sourcesPath = args.removeFirst()
    case "--catalogue":
        guard !args.isEmpty else { fatalError("--catalogue needs a path") }
        cataloguePath = args.removeFirst()
    case "--help", "-h":
        print("""
        localization-gate: fails when app code references a string the String
        Catalog cannot resolve in Russian.

        Usage: localization-gate [--sources <dir>] [--catalogue <path>]
        """)
        exit(0)
    default:
        fputs("unknown flag: \(flag)\n", stderr)
        exit(2)
    }
}

let catalogueURL = resolve(cataloguePath)
let sourcesURL = resolve(sourcesPath)

guard FileManager.default.fileExists(atPath: catalogueURL.path) else {
    fputs("localization-gate: catalogue not found at \(catalogueURL.path)\n", stderr)
    exit(2)
}
guard FileManager.default.fileExists(atPath: sourcesURL.path) else {
    fputs("localization-gate: sources not found at \(sourcesURL.path)\n", stderr)
    exit(2)
}

let catalogue: LocalizationCatalogue
do {
    catalogue = try LocalizationCatalogue.load(at: catalogueURL)
} catch {
    fputs("localization-gate: \(error.localizedDescription)\n", stderr)
    exit(2)
}

let violations: [LocalizationViolation]
do {
    violations = try LocalizationGate.violations(sources: sourcesURL, catalogue: catalogue)
} catch {
    fputs("localization-gate: \(error.localizedDescription)\n", stderr)
    exit(2)
}

let missingRu = catalogue.keysMissingRu
print("Localization gate: \(catalogue.keyCount) keys, "
      + "\(catalogue.ruCoveragePercent)% RU, "
      + "\(missingRu.count) key(s) missing Russian, "
      + "\(violations.count) violation(s) in app code.")

for key in missingRu {
    print("  catalogue: '\(key)' has no Russian value")
}

if !violations.isEmpty {
    fputs("Localization gate FAILED - strings that will not translate:\n", stderr)
    for violation in violations {
        fputs("  \(violation.description)\n", stderr)
    }
    exit(1)
}
