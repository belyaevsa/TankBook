import Foundation

// MARK: - The capture.pipeline line, emitted at the confirm commit (OB.2)

/// Builds the `capture.pipeline` event at the moment a capture is committed
/// (docs/LOGGING.md §4, OB.2). The pipeline's recognition fields and
/// confidence live in the `ExtractionMeta` the save writes; `userCorrected` is
/// only knowable here, when the saved values are compared with what the scan
/// proposed - which is why the line is emitted at the commit, not when Vision
/// returned.
///
/// Privacy: the meta is decoded down to field *names*, confidence values and
/// the corrected flag before anything is attached. The `FieldExtraction.value`
/// of every field - the extracted station, amount, note - is Never-class and
/// deliberately never read by this builder; `ExtractionMeta` holds it, this
/// type does not forward it (hard rule 12, docs/LOGGING.md §4 aggregate-safe by
/// construction).
public enum CaptureCommitLog {
    /// Whether the user edited any value the scan proposed. A flag that is
    /// always true measures nothing, so this is the aggregate over the meta's
    /// per-field `userCorrected` flags: it is true when at least one proposed
    /// value was changed and false when the user accepted every proposal.
    public static func userCorrected(meta: ExtractionMeta) -> Bool {
        meta.fields.values.contains { $0.userCorrected }
    }

    /// The event. `durationMs` is the recognition time measured by the
    /// pipeline that produced the prefill; `crossCheck` is the committed
    /// entry's own cross-check state.
    public static func event(meta: ExtractionMeta,
                             crossCheck: CrossCheckState?,
                             durationMs: Int) -> CapturePipeline {
        let fields = meta.fields
            .sorted { $0.key.stringValue < $1.key.stringValue }
            .map { CapturedField(name: $0.key, confidence: $0.value.confidence) }
        return CapturePipeline(
            pipelineId: meta.pipeline,
            durationMs: durationMs,
            fields: fields,
            crossCheck: crossCheck,
            userCorrected: userCorrected(meta: meta)
        )
    }
}
