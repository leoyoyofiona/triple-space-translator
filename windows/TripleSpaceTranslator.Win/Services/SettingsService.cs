using System.Text.Json;
using TripleSpaceTranslator.Win.Models;

namespace TripleSpaceTranslator.Win.Services;

public sealed class SettingsService
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true
    };

    public string SettingsPath { get; }

    public SettingsService()
    {
        var appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        var dir = Path.Combine(appData, "TripleSpaceTranslator");
        Directory.CreateDirectory(dir);
        SettingsPath = Path.Combine(dir, "settings.json");
    }

    public AppSettings Load()
    {
        try
        {
            if (!File.Exists(SettingsPath))
            {
                var defaults = new AppSettings();
                Save(defaults);
                return defaults;
            }

            var json = File.ReadAllText(SettingsPath);
            var settings = JsonSerializer.Deserialize<AppSettings>(json, JsonOptions);
            var normalized = settings ?? new AppSettings();
            var changed = NormalizeForOutOfBox(normalized);
            if (changed)
            {
                Save(normalized);
            }

            return normalized;
        }
        catch
        {
            return new AppSettings();
        }
    }

    public void Save(AppSettings settings)
    {
        var json = JsonSerializer.Serialize(settings, JsonOptions);
        File.WriteAllText(SettingsPath, json);
    }

    private static bool NormalizeForOutOfBox(AppSettings settings)
    {
        var changed = false;

        if (string.IsNullOrWhiteSpace(settings.Provider))
        {
            settings.Provider = "OfflineModel";
            changed = true;
        }
        else if (!string.Equals(settings.Provider, "OfflineModel", StringComparison.OrdinalIgnoreCase) &&
                 !string.Equals(settings.Provider, "Offline", StringComparison.OrdinalIgnoreCase) &&
                 !string.Equals(settings.Provider, "OpenAI", StringComparison.OrdinalIgnoreCase) &&
                 !string.Equals(settings.Provider, "LibreTranslate", StringComparison.OrdinalIgnoreCase))
        {
            settings.Provider = "OfflineModel";
            changed = true;
        }
        else if (string.Equals(settings.Provider, "OpenAI", StringComparison.OrdinalIgnoreCase) &&
                 string.IsNullOrWhiteSpace(settings.OpenAiApiKey))
        {
            settings.Provider = "OfflineModel";
            changed = true;
        }

        if (string.IsNullOrWhiteSpace(settings.LibreTranslateUrl))
        {
            settings.LibreTranslateUrl = "https://translate.argosopentech.com/translate";
            changed = true;
        }

        return changed;
    }
}
