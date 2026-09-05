using Microsoft.AspNetCore.Http.Features;
using Microsoft.AspNetCore.Mvc;
using Tankbook.Api.Logging;

namespace Tankbook.Api.Http;

/// <summary>
/// Enforces the per-endpoint request-body caps declared by
/// <see cref="BodySizeLimitAttribute"/> (docs/API.md "Request body caps",
/// PR.17). Runs after routing so the endpoint's metadata is visible. An oversize
/// body is refused with a 413 problem+json carrying its traceId - before any
/// byte is read - and never surfaces as a bare connection reset. For chunked
/// bodies (no Content-Length) Kestrel enforces the feature as the bytes stream
/// in; the feature is a no-op where it is absent (the in-memory test host).
/// </summary>
public sealed class BodySizeLimitMiddleware
{
    private readonly RequestDelegate _next;

    public BodySizeLimitMiddleware(RequestDelegate next)
    {
        _next = next;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        var limit = context.GetEndpoint()?.Metadata.GetMetadata<BodySizeLimitAttribute>()?.MaxBytes;

        if (limit is not null)
        {
            if (context.Request.ContentLength is long length && length > limit.Value)
            {
                await WriteTooLargeAsync(context, limit.Value);
                return;
            }

            var feature = context.Features.Get<IHttpMaxRequestBodySizeFeature>();
            if (feature is not null)
            {
                feature.MaxRequestBodySize = limit.Value;
            }
        }

        await _next(context);
    }

    private static ProblemDetails WithCode(ProblemDetails problem)
    {
        problem.Extensions[ProblemResponses.ErrorEnvelopeCodeKey] = TankbookErrorCodes.PayloadTooLarge;
        return problem;
    }

    private static async Task WriteTooLargeAsync(HttpContext context, long maxBytes)
    {
        context.Response.StatusCode = StatusCodes.Status413PayloadTooLarge;

        // Written through IProblemDetailsService so the body is problem+json and
        // the traceId extension member rides it (docs/LOGGING.md §2), exactly like
        // every other error surface.
        var problemService = context.RequestServices.GetService<IProblemDetailsService>();
        if (problemService is not null)
        {
            await problemService.TryWriteAsync(new ProblemDetailsContext
            {
                HttpContext = context,
                ProblemDetails = WithCode(new ProblemDetails
                {
                    Status = StatusCodes.Status413PayloadTooLarge,
                    Title = "Payload too large.",
                    Type = "about:blank",
                    Detail = $"The request body may be at most {maxBytes} bytes.",
                }),
            });
            return;
        }

        context.Response.StatusCode = StatusCodes.Status413PayloadTooLarge;
        context.Response.ContentType = "application/problem+json";
        var traceId = context.Items[TraceCorrelationMiddleware.TraceIdItemKey] as string;
        var problem = WithCode(new ProblemDetails
        {
            Status = StatusCodes.Status413PayloadTooLarge,
            Title = "Payload too large.",
            Type = "about:blank",
            Detail = $"The request body may be at most {maxBytes} bytes.",
        });
        if (traceId is not null)
        {
            problem.Extensions["traceId"] = traceId;
        }

        await context.Response.WriteAsJsonAsync(problem, context.RequestAborted);
    }
}
