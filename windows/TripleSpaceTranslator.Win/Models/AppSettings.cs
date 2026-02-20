namespace TripleSpaceTranslator.Win.Models;

public sealed class AppSettings
{
    public int TriplePressCount { get; set; } = 3;
    public int TriggerWindowMs { get; set; } = 500;
    public string SourceLanguage { get; set; } = "zh-CN";
    public string TargetLanguage { get; set; } = "en";
    public bool HasUserProviderPreference { get; set; } = false;

    // Translation provider: OfflineModel, OpenAI, LibreTranslate
    // Default to OfflineModel for out-of-box offline usage.
    public string Provider { get; set; } = "OfflineModel";

    // OpenAI-compatible settings
    public string OpenAiBaseUrl { get; set; } = "https://api.openai.com/v1";
    public string OpenAiApiKey { get; set; } = string.Empty;
    public string OpenAiModel { get; set; } = "gpt-4o-mini";

    // LibreTranslate settings (for self-host deployments)
    public string LibreTranslateUrl { get; set; } = "https://translate.argosopentech.com/translate";
    public string LibreTranslateApiKey { get; set; } = string.Empty;
}
