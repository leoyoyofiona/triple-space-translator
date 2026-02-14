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

        var endpoint = _settings.OpenAiBaseUrl.TrimEnd('/') + "/chat/completions";

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
                    content = "You are a translation engine. Translate Chinese to concise natural English. Return only translated text."
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
            throw new InvalidOperationException($"OpenAI request failed ({(int)response.StatusCode}): {responseBody}");
        }

        using var json = JsonDocument.Parse(responseBody);
        var content = json.RootElement
            .GetProperty("choices")[0]
            .GetProperty("message")
            .GetProperty("content")
            .GetString();

        return content?.Trim() ?? string.Empty;
    }
}
