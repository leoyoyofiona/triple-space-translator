using System.Text;
using System.Text.Json;
using TripleSpaceTranslator.Win.Models;

namespace TripleSpaceTranslator.Win.Services.Translation;

public sealed class LibreTranslateTranslator : ITranslator
{
    private readonly HttpClient _httpClient;
    private readonly AppSettings _settings;

    public LibreTranslateTranslator(HttpClient httpClient, AppSettings settings)
    {
        _httpClient = httpClient;
        _settings = settings;
    }

    public async Task<string> TranslateAsync(string text, string sourceLang, string targetLang, CancellationToken cancellationToken)
    {
        var payload = new Dictionary<string, object?>
        {
            ["q"] = text,
            ["source"] = sourceLang,
            ["target"] = targetLang,
            ["format"] = "text"
        };

        if (!string.IsNullOrWhiteSpace(_settings.LibreTranslateApiKey))
        {
            payload["api_key"] = _settings.LibreTranslateApiKey;
        }

        using var request = new HttpRequestMessage(HttpMethod.Post, _settings.LibreTranslateUrl);
        request.Content = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json");

        using var response = await _httpClient.SendAsync(request, cancellationToken);
        var responseBody = await response.Content.ReadAsStringAsync(cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            throw new InvalidOperationException($"LibreTranslate request failed ({(int)response.StatusCode}): {responseBody}");
        }

        using var json = JsonDocument.Parse(responseBody);
        if (!json.RootElement.TryGetProperty("translatedText", out var translated))
        {
            throw new InvalidOperationException("LibreTranslate response missing translatedText field.");
        }

        return translated.GetString()?.Trim() ?? string.Empty;
    }
}
