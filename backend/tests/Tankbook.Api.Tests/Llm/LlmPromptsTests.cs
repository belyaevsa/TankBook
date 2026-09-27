using Tankbook.Api.Llm;

namespace Tankbook.Api.Tests.Llm;

/// <summary>
/// PJ.29 - the per-kind prompt (docs/EXTRACTION.md "The Expense hand-off").
/// The provider itself is never exercised by the suite (it would make a paid
/// call), but the vocabulary the gateway asks for is part of the contract: an
/// expense prompt must not name fuel fields, because a shop receipt has none,
/// and an invoice keeps its header only (the line items are the device's own
/// deterministic split). A regression here would silently ask the model to
/// invent a volume on a parking ticket.
/// </summary>
public class LlmPromptsTests
{
    [Fact]
    public void ExpensePromptNamesExpenseFieldsAndNoFuelFields()
    {
        var prompt = LlmPrompts.SystemPrompt("expense", new ExtractHints("EUR", "ru", null));

        Assert.Contains("category", prompt, StringComparison.Ordinal);
        Assert.DoesNotContain("volume", prompt, StringComparison.Ordinal);
        Assert.DoesNotContain("unitPrice", prompt, StringComparison.Ordinal);
        Assert.DoesNotContain("fuelKind", prompt, StringComparison.Ordinal);

        // The user message names the document, not "the fuel fields".
        Assert.Contains("receipt", LlmPrompts.UserMessage("expense"), StringComparison.Ordinal);
    }

    [Fact]
    public void InvoicePromptKeepsTheHeaderFieldsOnly()
    {
        var prompt = LlmPrompts.SystemPrompt("invoice", new ExtractHints(null, null, null));

        Assert.Contains("vendor", prompt, StringComparison.Ordinal);
        Assert.Contains("total", prompt, StringComparison.Ordinal);
        Assert.DoesNotContain("volume", prompt, StringComparison.Ordinal);
        Assert.DoesNotContain("unitPrice", prompt, StringComparison.Ordinal);
    }

    /// <summary>
    /// PJ.301: the multi-page shape asks the invoice for its line items as
    /// indexed fields beside the header, and names the pages as one document
    /// in order; the single-image shape is byte-for-byte the header-only prompt
    /// an older client relies on.
    /// </summary>
    [Fact]
    public void MultiPageInvoicePromptAsksForIndexedLineItems_AndSingleImageStaysHeaderOnly()
    {
        var hints = new ExtractHints(null, null, null);
        var multi = LlmPrompts.SystemPrompt("invoice", hints, lineItems: true, pageCount: 2);
        Assert.Contains("lineItem[n].title", multi, StringComparison.Ordinal);
        Assert.Contains("lineItem[n].amount", multi, StringComparison.Ordinal);
        Assert.Contains("lineItem[n].category", multi, StringComparison.Ordinal);
        Assert.Contains("2 images that are the pages, in order", multi, StringComparison.Ordinal);
        Assert.Contains("2 pages", LlmPrompts.UserMessage("invoice", pageCount: 2), StringComparison.Ordinal);

        var single = LlmPrompts.SystemPrompt("invoice", hints);
        Assert.DoesNotContain("lineItem", single, StringComparison.Ordinal);
        Assert.Equal(single, LlmPrompts.SystemPrompt("invoice", hints, lineItems: false, pageCount: 1));
    }

    [Fact]
    public void FuelPromptKeepsThePumpCardVocabulary()
    {
        var prompt = LlmPrompts.SystemPrompt("receipt", new ExtractHints(null, null, new[] { "petrol95" }));

        Assert.Contains("volume", prompt, StringComparison.Ordinal);
        Assert.Contains("unitPrice", prompt, StringComparison.Ordinal);
        Assert.Contains("fuelKind", prompt, StringComparison.Ordinal);
    }

    /// <summary>
    /// RV.289: a pump display is its own document. The prompt names the three
    /// numbers and where they sit, the leading-zero padding and the comma
    /// decimal, keeps grade price boards out of the price, and forbids deriving
    /// a number; a display prints no date, station or vendor, so none is asked for.
    /// </summary>
    [Fact]
    public void PumpPromptNamesTheDisplayLayoutAndAsksForNoReceiptFields()
    {
        var prompt = LlmPrompts.SystemPrompt("pump", new ExtractHints("EUR", "et", null));

        Assert.Contains("Allowed field names: total, volume, unitPrice, currency.", prompt, StringComparison.Ordinal);
        Assert.Contains("leading zeros are padding (0032,64 is 32.64)", prompt, StringComparison.Ordinal);
        Assert.Contains("usually the top and largest row", prompt, StringComparison.Ordinal);
        Assert.Contains("price boards, not the transaction", prompt, StringComparison.Ordinal);
        Assert.Contains("never compute one from the other two", prompt, StringComparison.Ordinal);
        foreach (var receiptField in new[] { "date", "station", "vendor", "fuelKind" })
        {
            Assert.DoesNotContain(receiptField, prompt, StringComparison.Ordinal);
        }

        // The receipt prompt is untouched by the pump instruction.
        Assert.DoesNotContain("seven-segment", LlmPrompts.SystemPrompt("receipt", new ExtractHints(null, null, null)),
            StringComparison.Ordinal);
    }
}
