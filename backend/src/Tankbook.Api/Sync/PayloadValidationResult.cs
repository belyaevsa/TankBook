namespace Tankbook.Api.Sync;

/// <summary>
/// Outcome of one payload validation. <see cref="IsAccepted"/> is true exactly
/// when <see cref="Code"/> is <see cref="PayloadRejectionCode.None"/>; otherwise
/// <see cref="WireCode"/> carries the docs/API.md error code and <see cref="Pointer"/>
/// is the JSON pointer to the failing field (never its value - see
/// docs/SYNC.md "What the server enforces").
/// </summary>
public sealed record PayloadValidationResult(PayloadRejectionCode Code, string? Pointer)
{
    public static readonly PayloadValidationResult Accepted =
        new(PayloadRejectionCode.None, Pointer: null);

    public bool IsAccepted => Code == PayloadRejectionCode.None;

    public string? WireCode => IsAccepted ? null : Code.ToWireCode();

    public static PayloadValidationResult Reject(PayloadRejectionCode code, string? pointer = null)
    {
        ArgumentOutOfRangeException.ThrowIfEqual(code, PayloadRejectionCode.None);
        return new PayloadValidationResult(code, pointer);
    }
}
