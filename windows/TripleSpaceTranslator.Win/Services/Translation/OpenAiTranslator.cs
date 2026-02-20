using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using TripleSpaceTranslator.Win.Models;

namespace TripleSpaceTranslator.Win.Services.Translation;

public sealed class OpenAiTranslator : ITranslator
{
    private readonly HttpClient _httpClient;
    private readonly AppSettings _settings;

    public OpenAiTranslator(HttpClient httpClient, AppSettings settings)
    {
        _httpClient = httpClient;
        _settings = settings;
    }

    public async Task<string> TranslateAsync(string text, string sourceLang, string targetLang, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(_settings.OpenAiApiKey))
        {
            throw new InvalidOperationException("OpenAI API key is empty. Set it in the app settings.");
        }

        var endpoint = BuildChatCompletionsEndpoint(_settings.OpenAiBaseUrl);

        using var request = new HttpRequestMessage(HttpMethod.Post, endpoint);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _settings.OpenAiApiKey);

        var payload = new
        {
            model = _settings.OpenAiModel,
            temperature = 0,
            messages = new object[]
            {
                new
                {
                    role = "system",
                    content = BuildSystemPrompt(sourceLang, targetLang)
                },
                new
                {
                    role = "user",
                    content = text
                }
            }
        };

        request.Content = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json");

        using var response = await _httpClient.SendAsync(request, cancellationToken);
        var responseBody = await response.Content.ReadAsStringAsync(cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            throw new InvalidOperationException($"OpenAI request failed ({(int)response.StatusCode}) at {endpoint}: {responseBody}");
        }

        using var json = JsonDocument.Parse(responseBody);
        var content = json.RootElement
            .GetProperty("choices")[0]
            .GetProperty("message")
            .GetProperty("content")
            .GetString();

        return content?.Trim() ?? string.Empty;
    }

    private static string BuildSystemPrompt(string sourceLang, string targetLang)
    {
        var sourceLabel = ToLanguageLabel(sourceLang);
        var targetLabel = ToLanguageLabel(targetLang);
        return $"You are a translation engine. Translate {sourceLabel} to concise natural {targetLabel}. Return only translated text.";
    }

    private static string ToLanguageLabel(string lang)
    {
        return lang.ToLowerInvariant() switch
        {
            "zh" or "zh-cn" or "zh-hans" => "Chinese",
            "en" or "en-us" => "English",
            _ => lang
        };
    }

    private static string BuildChatCompletionsEndpoint(string? rawBaseUrl)
    {
        var baseUrl = string.IsNullOrWhiteSpace(rawBaseUrl)
            ? "https://api.openai.com/v1"
            : rawBaseUrl.Trim();

        baseUrl = baseUrl.TrimEnd('/');

        if (baseUrl.EndsWith("/chat/completions", StringComparison.OrdinalIgnoreCase))
        {
            return baseUrl;
        }

        if (baseUrl.EndsWith("/responses", StringComparison.OrdinalIgnoreCase))
        {
            return baseUrl[..^"/responses".Length] + "/chat/completions";
        }

        if (baseUrl.EndsWith("/chat", StringComparison.OrdinalIgnoreCase))
        {
            return baseUrl + "/completions";
        }

        if (baseUrl.EndsWith("/v1", StringComparison.OrdinalIgnoreCase))
        {
            return baseUrl + "/chat/completions";
        }

        return baseUrl + "/v1/chat/completions";
    }
}
