using TripleSpaceTranslator.Win.Models;

namespace TripleSpaceTranslator.Win.Services.Translation;

public static class TranslatorFactory
{
    public static ITranslator Create(AppSettings settings, HttpClient httpClient)
    {
        if (string.Equals(settings.Provider, "LibreTranslate", StringComparison.OrdinalIgnoreCase))
        {
            return new LibreTranslateTranslator(httpClient, settings);
        }

        return new OpenAiTranslator(httpClient, settings);
    }
}
