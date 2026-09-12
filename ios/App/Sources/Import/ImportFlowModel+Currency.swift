import Foundation
import TankbookCore

// The import wizard's currency question (RV.113, RV.263) - the answer, the
// pre-filled default and the candidate set the preview, the review list and the
// commit all read. Split from `ImportFlowModel+Wizard` so that file stays under
// the repo's lint floors; the state lives in the model's declaration, these
// extensions only read and mutate it.

extension ImportFlowModel {
    /// Answers the currency question (RV.113, RV.263), once per file. The pick
    /// applies to every money-carrying candidate, and the classification rebuilds
    /// so the preview, the review list and the commit all read the answered
    /// currency - the number the user approves is the number that lands (F6a).
    func answerCurrency(_ code: CurrencyCode) {
        guard hasCurrencyQuestion else { return }
        currencyAnswer = code
        // RV.185: the answer is the new car's home currency too, not just the
        // rows'. A new car is synthesized before the currency question is
        // answered, so it is re-homed in place here - same id, so the classified
        // fills keep their destination and the conversion now runs against the
        // currency the user actually chose. An EXISTING destination car is never
        // touched (RV.152 owns that decision).
        applyHomeCurrencyToNewCars(code)
        rebuildClassification()
    }

    /// RV.185: stamps the answered currency onto every synthesized NEW car (the
    /// single target and each decided lane). Existing cars are left alone - the
    /// import must not re-home a car the user already owns.
    private func applyHomeCurrencyToNewCars(_ code: CurrencyCode) {
        if case .new(var vehicle) = targetCar {
            vehicle.homeCurrency = code
            targetCar = .new(vehicle)
        }
        for index in carPlan.indices {
            guard case .new(var vehicle) = carPlan[index].destination else { continue }
            vehicle.homeCurrency = code
            carPlan[index].destination = .new(vehicle)
        }
    }

    /// The candidates with the chosen date reading applied. The merged parse is
    /// ALREADY the answer applied - `ImportBatchMerge` re-dates per file that
    /// needs it, and re-dating the merged list again would double-flip an
    /// ambiguous file and corrupt a file that proved its dates (RV.85). So this
    /// is simply the merged candidates; the pristine per-file parses are never
    /// mutated, so re-answering stays correct. A `currency` question (RV.113,
    /// RV.263) has the user's answer - or, for a declared currency, the file's
    /// own code - applied here, so the conversion and the commit read the
    /// answered money.
    var effectiveCandidates: [ImportCandidate] {
        guard let parse else { return [] }
        guard hasCurrencyQuestion, let currency = effectiveCurrency else {
            return parse.candidates
        }
        return parse.candidates.map { $0.applyingCurrency(currency) }
    }

    /// The currency the preview, the review list and the commit read: the user's
    /// pick, else the code the file declares, else the destination car's home
    /// currency (the default the wizard offers - hard rule 13, never a fact). A
    /// declared currency is thus pre-filled without a tap (RV.263); a file with
    /// no currency column falls through to the car's home currency.
    var effectiveCurrency: CurrencyCode? {
        currencyAnswer ?? parse?.declaredCurrency ?? defaultCurrency
    }

    var hasCurrencyQuestion: Bool { parse?.hasCurrencyQuestion ?? false }

    /// Whether the currency card still needs the user's pick - a file with no
    /// currency column would otherwise commit a GUESS (F6). A declared currency
    /// is pre-filled, so the card renders but does not gate the commit.
    var needsCurrencyAnswer: Bool { parse?.needsCurrencyAnswer ?? false }

    /// The currency card's subtitle: a declared currency says what the file
    /// says, a no-column file says it could not find one (both editable here).
    var currencyQuestionSubtitle: String {
        guard let parse, !parse.needsCurrencyAnswer, let declared = parse.declaredCurrency else {
            return L10n.currencyQuestionSubtitle
        }
        return L10n.currencyDeclaredSubtitle(declared.rawValue)
    }

    /// The destination car's home currency - the default the currency question
    /// offers. A brand-new car is EUR; an existing car is its own home currency.
    var defaultCurrency: CurrencyCode {
        targetCar?.vehicleValue.homeCurrency ?? liveVehicles.first?.homeCurrency ?? .eur
    }
}
