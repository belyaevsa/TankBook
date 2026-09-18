namespace Tankbook.Api.Llm;

/// <summary>
/// The compiled limits of POST /extract (docs/API.md "LLM gateway (Pro)";
/// docs/PRACTICES.md constants placement - compiled, because a cap the
/// envelope enforces before the provider is called must be one number the
/// body-size limit, the validator and the served config all reference).
/// </summary>
public static class ExtractLimits
{
    /// <summary>Cap on one base64 image (a page): 4 MB. <see cref="LlmGatewayOptions.MaxImageBytes"/> defaults to it.</summary>
    public const long MaxImageBytes = 4L * 1024 * 1024;

    /// <summary>
    /// Pages of one invoice in one call. Echoed to the device in the config
    /// document as <c>extract.maxInvoicePages</c> so the camera stops at the cap
    /// before the request is built; the server refuses a longer list with a 400.
    /// </summary>
    public const int MaxInvoicePages = 6;

    /// <summary>The only kind whose request may carry <c>images</c> (docs/API.md).</summary>
    public const string MultiPageKind = "invoice";
}
