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

    [Fact]
    public void FuelPromptKeepsThePumpCardVocabulary()
    {
        var prompt = LlmPrompts.SystemPrompt("receipt", new ExtractHints(null, null, new[] { "petrol95" }));

        Assert.Contains("volume", prompt, StringComparison.Ordinal);
        Assert.Contains("unitPrice", prompt, StringComparison.Ordinal);
        Assert.Contains("fuelKind", prompt, StringComparison.Ordinal);
    }
}
