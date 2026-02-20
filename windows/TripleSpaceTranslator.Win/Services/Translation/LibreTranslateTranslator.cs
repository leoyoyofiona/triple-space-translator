using System.Text;
using System.Text.Json;
using TripleSpaceTranslator.Win.Models;

namespace TripleSpaceTranslator.Win.Services.Translation;

public sealed class LibreTranslateTranslator : ITranslator
{
    private readonly HttpClient _httpClient;
    private readonly AppSettings _settings;
    private static readonly string[] PublicFallbackEndpoints =
    {
        "https://translate.argosopentech.com/translate",
        "https://libretranslate.com/translate"
    };

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

        var attempts = new List<string>();
        foreach (var endpoint in BuildEndpointCandidates())
        {
            try
            {
                using var request = new HttpRequestMessage(HttpMethod.Post, endpoint);
                request.Content = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json");

                using var response = await _httpClient.SendAsync(request, cancellationToken);
                var responseBody = await response.Content.ReadAsStringAsync(cancellationToken);
                if (!response.IsSuccessStatusCode)
                {
                    attempts.Add($"{endpoint} -> HTTP {(int)response.StatusCode}");
                    continue;
                }

                using var json = JsonDocument.Parse(responseBody);
                if (!json.RootElement.TryGetProperty("translatedText", out var translated))
                {
                    attempts.Add($"{endpoint} -> missing translatedText");
                    continue;
                }

                var result = translated.GetString()?.Trim() ?? string.Empty;
                if (!string.IsNullOrWhiteSpace(result))
                {
                    return result;
                }

                attempts.Add($"{endpoint} -> empty translatedText");
            }
            catch (Exception ex)
            {
                attempts.Add($"{endpoint} -> {ex.GetType().Name}");
            }
        }

        var summary = attempts.Count == 0 ? "no endpoint attempts" : string.Join("; ", attempts);
        throw new InvalidOperationException($"LibreTranslate request failed across all endpoints: {summary}");
    }

    private IEnumerable<string> BuildEndpointCandidates()
    {
        var unique = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var configured = NormalizeEndpoint(_settings.LibreTranslateUrl);
        if (!string.IsNullOrWhiteSpace(configured) && unique.Add(configured))
        {
            yield return configured;
        }

        foreach (var endpoint in PublicFallbackEndpoints)
        {
            var normalized = NormalizeEndpoint(endpoint);
            if (!string.IsNullOrWhiteSpace(normalized) && unique.Add(normalized))
            {
                yield return normalized;
            }
        }
    }

    private static string NormalizeEndpoint(string? endpoint)
    {
        if (string.IsNullOrWhiteSpace(endpoint))
        {
            return string.Empty;
        }

        var normalized = endpoint.Trim();
        if (normalized.EndsWith('/'))
        {
            normalized = normalized.TrimEnd('/');
        }

        if (!normalized.EndsWith("/translate", StringComparison.OrdinalIgnoreCase))
        {
            normalized += "/translate";
        }

        return normalized;
    }
}
