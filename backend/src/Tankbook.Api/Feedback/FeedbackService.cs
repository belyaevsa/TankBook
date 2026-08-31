using Tankbook.Api.Logging;

namespace Tankbook.Api.Feedback;

/// <summary>
/// The feedback intake surface (docs/API.md "Feedback"): stores one case and
/// logs shape only. The feedback text, the replyTo address and the device-model
/// string have no route into the log event by construction - the same
/// discipline as capture.pipeline (docs/LOGGING.md -> Feedback). 202 means
/// accepted; the row is written before the response, so an accepted case is a
/// stored case.
/// </summary>
public sealed class FeedbackService
{
    private readonly FeedbackRepository _repository;
    private readonly ILogger<FeedbackService> _logger;

    public FeedbackService(FeedbackRepository repository, ILogger<FeedbackService> logger)
    {
        _repository = repository;
        _logger = logger;
    }

    public async Task<Guid> SubmitAsync(
        string category,
        string text,
        string? appVersion,
        string? deviceModel,
        string? replyTo,
        Guid? accountId,
        CancellationToken cancellationToken)
    {
        var id = Guid.NewGuid();

        await _repository.InsertAsync(
            id,
            accountId,
            category,
            text,
            appVersion,
            deviceModel,
            replyTo,
            cancellationToken);

        TankbookLog.FeedbackAccepted(
            _logger,
            id,
            category,
            text.Length,
            replyTo is not null,
            deviceModel is not null,
            accountId is not null);

        return id;
    }
}
