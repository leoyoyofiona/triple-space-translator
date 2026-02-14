namespace TripleSpaceTranslator.Win.Models;

public sealed class AppSettings
{
    public int TriplePressCount { get; set; } = 3;
    public int TriggerWindowMs { get; set; } = 500;
    public string SourceLanguage { get; set; } = "zh-CN";
    public string TargetLanguage { get; set; } = "en";

    // Translation provider: OpenAI or LibreTranslate
    public string Provider { get; set; } = "OpenAI";

    // OpenAI-compatible settings
    public string OpenAiBaseUrl { get; set; } = "https://api.openai.com/v1";
    public string OpenAiApiKey { get; set; } = string.Empty;
    public string OpenAiModel { get; set; } = "gpt-4o-mini";

    // LibreTranslate settings (for self-host deployments)
    public string LibreTranslateUrl { get; set; } = "https://libretranslate.com/translate";
    public string LibreTranslateApiKey { get; set; } = string.Empty;
}
