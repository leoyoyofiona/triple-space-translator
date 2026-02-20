using System.Net.Http;
using System.Text;
using TripleSpaceTranslator.Win.Models;
using TripleSpaceTranslator.Win.Services;
using TripleSpaceTranslator.Win.Services.Translation;

namespace TripleSpaceTranslator.Win;

public sealed class MainForm : Form
{
    private readonly SettingsService _settingsService = new();
    private readonly GlobalKeyboardHook _keyboardHook = new();
    private readonly TripleSpaceDetector _detector = new();
    private readonly InputAutomationService _inputService = new();
    private readonly HttpClient _httpClient = new();

    private AppSettings _settings = new();

    private readonly Label _statusLabel = new();
    private readonly Button _toggleButton = new();
    private readonly Button _saveButton = new();
    private readonly NumericUpDown _windowMsNumeric = new();
    private readonly ComboBox _providerCombo = new();
    private readonly TextBox _apiKeyText = new();
    private readonly TextBox _baseUrlText = new();
    private readonly TextBox _modelText = new();
    private readonly NotifyIcon _trayIcon = new();
    private readonly ContextMenuStrip _trayMenu = new();
    private ToolStripMenuItem? _trayToggleMenuItem;

    private bool _running = true;
    private bool _busy;
    private bool _allowClose;
    private readonly Dictionary<string, string> _translationCache = new(StringComparer.Ordinal);
    private readonly Queue<string> _translationCacheOrder = new();
    private (string Left, string Right)? _lastTranslationPair;
    private string? _lastAppliedOutputText;
    private DateTime _lastAppliedAtUtc = DateTime.MinValue;
    private const int MaxCacheEntries = 200;

    public MainForm()
    {
        Text = "Triple Space Translator (Windows Stable)";
        AutoScaleMode = AutoScaleMode.Dpi;
        Width = 980;
        Height = 700;
        MinimumSize = new Size(900, 620);
        StartPosition = FormStartPosition.CenterScreen;

        InitializeUi();

        _settings = _settingsService.Load();
        ApplySettingsToUi();
        UpdateStatus("Ready. Press triple-space quickly in any input field (bidirectional toggle enabled).");

        InitializeTray();

        _keyboardHook.KeyPressed += OnGlobalKeyPressed;
        _keyboardHook.Start();

        FormClosing += OnFormClosing;
        Resize += OnFormResize;
    }

    private void InitializeUi()
    {
        var root = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 2,
            RowCount = 8,
            Padding = new Padding(12),
            AutoSize = false
        };

        root.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 300));
        root.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));

        root.Controls.Add(MakeLabel("Trigger window (ms):"), 0, 0);
        _windowMsNumeric.Minimum = 250;
        _windowMsNumeric.Maximum = 1500;
        _windowMsNumeric.Increment = 50;
        _windowMsNumeric.Value = 500;
        _windowMsNumeric.Dock = DockStyle.Fill;
        root.Controls.Add(_windowMsNumeric, 1, 0);

        root.Controls.Add(MakeLabel("Translator provider:"), 0, 1);
        _providerCombo.Dock = DockStyle.Fill;
        _providerCombo.DropDownStyle = ComboBoxStyle.DropDownList;
        _providerCombo.Items.AddRange(new object[] { "Offline (Built-in)", "OpenAI", "LibreTranslate" });
        root.Controls.Add(_providerCombo, 1, 1);

        root.Controls.Add(MakeLabel("API key:"), 0, 2);
        _apiKeyText.Dock = DockStyle.Fill;
        _apiKeyText.UseSystemPasswordChar = true;
        root.Controls.Add(_apiKeyText, 1, 2);

        root.Controls.Add(MakeLabel("Base URL:"), 0, 3);
        _baseUrlText.Dock = DockStyle.Fill;
        root.Controls.Add(_baseUrlText, 1, 3);

        root.Controls.Add(MakeLabel("Model:"), 0, 4);
        _modelText.Dock = DockStyle.Fill;
        root.Controls.Add(_modelText, 1, 4);

        _toggleButton.Text = "Pause Hook";
        _toggleButton.Dock = DockStyle.Fill;
        _toggleButton.Click += (_, _) => ToggleRunningState();
        root.Controls.Add(_toggleButton, 0, 5);

        _saveButton.Text = "Save Settings";
        _saveButton.Dock = DockStyle.Fill;
        _saveButton.Click += (_, _) =>
        {
            CollectSettingsFromUi();
            _settingsService.Save(_settings);
            UpdateStatus($"Settings saved: {_settingsService.SettingsPath}");
        };
        root.Controls.Add(_saveButton, 1, 5);

        root.Controls.Add(MakeLabel("Status:"), 0, 6);
        _statusLabel.Dock = DockStyle.Fill;
        _statusLabel.AutoSize = false;
        _statusLabel.Height = 120;
        _statusLabel.MinimumSize = new Size(0, 150);
        _statusLabel.BorderStyle = BorderStyle.FixedSingle;
        _statusLabel.Padding = new Padding(8);
        root.Controls.Add(_statusLabel, 1, 6);

        var hint = new Label
        {
            Dock = DockStyle.Fill,
            AutoSize = false,
            Text = "Tips: default mode uses built-in offline model (no network/API key). If some apps block replacement, try running this app as Administrator.",
            ForeColor = Color.DimGray
        };
        root.Controls.Add(hint, 0, 7);
        root.SetColumnSpan(hint, 2);

        Controls.Add(root);
    }

    private void InitializeTray()
    {
        _trayMenu.Items.Add("Open", null, (_, _) => ShowMainWindow());
        _trayToggleMenuItem = new ToolStripMenuItem("Pause Hook", null, (_, _) => ToggleRunningState());
        _trayMenu.Items.Add(_trayToggleMenuItem);
        _trayMenu.Items.Add("Exit", null, (_, _) => ExitApplication());

        _trayIcon.Icon = SystemIcons.Application;
        _trayIcon.Text = "Triple Space Translator";
        _trayIcon.ContextMenuStrip = _trayMenu;
        _trayIcon.Visible = true;
        _trayIcon.DoubleClick += (_, _) => ShowMainWindow();
    }

    private static Label MakeLabel(string text)
    {
        return new Label
        {
            Text = text,
            TextAlign = ContentAlignment.MiddleLeft,
            Dock = DockStyle.Fill,
            AutoSize = false
        };
    }

    private void ApplySettingsToUi()
    {
        _windowMsNumeric.Value = Math.Clamp(_settings.TriggerWindowMs, 250, 1500);
        var providerUiValue = ToProviderUiValue(_settings.Provider);
        _providerCombo.SelectedItem = providerUiValue;
        if (providerUiValue == "LibreTranslate")
        {
            _apiKeyText.Text = _settings.LibreTranslateApiKey;
            _baseUrlText.Text = _settings.LibreTranslateUrl;
        }
        else if (providerUiValue == "OpenAI")
        {
            _apiKeyText.Text = _settings.OpenAiApiKey;
            _baseUrlText.Text = _settings.OpenAiBaseUrl;
        }
        else
        {
            _apiKeyText.Text = string.Empty;
            _baseUrlText.Text = "(offline built-in model)";
        }
        _modelText.Text = _settings.OpenAiModel;

        _providerCombo.SelectedIndexChanged += (_, _) =>
        {
            var provider = (_providerCombo.SelectedItem as string) ?? "Offline (Built-in)";
            ApplyProviderUiState(provider);
        };

        ApplyProviderUiState(providerUiValue);
    }

    private void CollectSettingsFromUi()
    {
        var providerUi = (_providerCombo.SelectedItem as string) ?? "Offline (Built-in)";
        var provider = FromProviderUiValue(providerUi);

        _settings.TriggerWindowMs = (int)_windowMsNumeric.Value;
        _settings.Provider = provider;
        _settings.HasUserProviderPreference = true;

        if (provider.Equals("LibreTranslate", StringComparison.OrdinalIgnoreCase))
        {
            _settings.LibreTranslateUrl = _baseUrlText.Text.Trim();
            _settings.LibreTranslateApiKey = _apiKeyText.Text;
        }
        else if (provider.Equals("OpenAI", StringComparison.OrdinalIgnoreCase))
        {
            _settings.OpenAiBaseUrl = _baseUrlText.Text.Trim();
            _settings.OpenAiApiKey = _apiKeyText.Text;
            _settings.OpenAiModel = string.IsNullOrWhiteSpace(_modelText.Text) ? "gpt-4o-mini" : _modelText.Text.Trim();
        }
    }

    private void OnGlobalKeyPressed(Keys key)
    {
        if (!_running || key != Keys.Space)
        {
            return;
        }

        CollectSettingsFromUi();

        var fired = _detector.RegisterPress(_settings.TriplePressCount, _settings.TriggerWindowMs);
        if (!fired)
        {
            return;
        }

        BeginInvoke(new Action(() => _ = HandleTriggerAsync()));
    }

    private async Task HandleTriggerAsync()
    {
        if (_busy)
        {
            return;
        }

        _busy = true;
        try
        {
            UpdateStatus("Triple-space detected. Reading focused input...");

            var original = _inputService.ReadFocusedText();
            if (string.IsNullOrWhiteSpace(original))
            {
                UpdateStatus("No readable focused input.");
                return;
            }

            var text = InputAutomationService.RemoveTrailingSpaces(original, _settings.TriplePressCount);
            if (string.IsNullOrWhiteSpace(text))
            {
                UpdateStatus("Input is empty after removing trigger spaces.");
                return;
            }

            if (TryResolveToggleTarget(text, out var pairTarget))
            {
                var toggled = _inputService.ReplaceFocusedText(pairTarget);
                if (toggled)
                {
                    CacheTranslationPair(text, pairTarget);
                    _lastTranslationPair = (text, pairTarget);
                    RecordAppliedOutput(pairTarget);
                    UpdateStatus("Reverse toggle applied to focused input.");
                }
                else
                {
                    UpdateStatus("Reverse toggle matched but replacement failed in this control.");
                }
                return;
            }

            if (TryGetCachedTranslation(text, out var cachedTarget))
            {
                var replacedFromCache = _inputService.ReplaceFocusedText(cachedTarget);
                if (replacedFromCache)
                {
                    CacheTranslationPair(text, cachedTarget);
                    _lastTranslationPair = (text, cachedTarget);
                    RecordAppliedOutput(cachedTarget);
                    UpdateStatus("Translation toggled from recent cache.");
                }
                else
                {
                    UpdateStatus("Cache toggle matched but replacement failed in this control.");
                }
                return;
            }

            var direction = InputAutomationService.DetectPreferredDirection(text);
            if (direction is null)
            {
                UpdateStatus("Focused text does not contain identifiable Chinese/English content. Skipped.");
                return;
            }

            var sourceLang = direction == TranslationDirection.ZhToEn ? "zh" : "en";
            var targetLang = direction == TranslationDirection.ZhToEn ? "en" : "zh";
            var targetLabel = direction == TranslationDirection.ZhToEn ? "English" : "Chinese";

            UpdateStatus($"Translating to {targetLabel}...");
            var translator = TranslatorFactory.Create(_settings, _httpClient);
            var translated = await translator.TranslateAsync(text, sourceLang, targetLang, CancellationToken.None);
            if (string.IsNullOrWhiteSpace(translated))
            {
                UpdateStatus("Translator returned empty content.");
                return;
            }

            var replaced = _inputService.ReplaceFocusedText(translated);
            if (replaced)
            {
                CacheTranslationPair(text, translated);
                _lastTranslationPair = (text, translated);
                RecordAppliedOutput(translated);
                UpdateStatus($"Translation applied to focused input ({targetLabel}).");
            }
            else
            {
                UpdateStatus("Translation succeeded but replacement failed in this control.");
            }
        }
        catch (Exception ex)
        {
            UpdateStatus($"Error: {ex.Message}");
        }
        finally
        {
            _busy = false;
        }
    }

    private void UpdateStatus(string message)
    {
        _statusLabel.Text = $"{DateTime.Now:HH:mm:ss}  {message}";
        _trayIcon.Text = TrimTrayText(message);
    }

    private void OnFormClosing(object? sender, FormClosingEventArgs e)
    {
        if (!_allowClose && e.CloseReason == CloseReason.UserClosing)
        {
            e.Cancel = true;
            Hide();
            return;
        }

        _keyboardHook.Stop();
        _keyboardHook.Dispose();
        _httpClient.Dispose();
        _settingsService.Save(_settings);
        _trayIcon.Visible = false;
        _trayIcon.Dispose();
        _trayMenu.Dispose();
    }

    private void OnFormResize(object? sender, EventArgs e)
    {
        if (WindowState == FormWindowState.Minimized)
        {
            Hide();
            _trayIcon.ShowBalloonTip(1200, "Triple Space Translator", "App is still running in tray.", ToolTipIcon.Info);
        }
    }

    private void ToggleRunningState()
    {
        _running = !_running;
        _toggleButton.Text = _running ? "Pause Hook" : "Resume Hook";
        if (_trayToggleMenuItem is not null)
        {
            _trayToggleMenuItem.Text = _running ? "Pause Hook" : "Resume Hook";
        }
        UpdateStatus(_running ? "Hook resumed." : "Hook paused.");
    }

    private void ShowMainWindow()
    {
        Show();
        WindowState = FormWindowState.Normal;
        BringToFront();
        Activate();
    }

    private void ExitApplication()
    {
        _allowClose = true;
        Close();
    }

    private static string TrimTrayText(string message)
    {
        const int maxLen = 63;
        if (string.IsNullOrWhiteSpace(message))
        {
            return "Triple Space Translator";
        }

        return message.Length <= maxLen ? message : message[..maxLen];
    }

    private static string ToProviderUiValue(string? provider)
    {
        if (string.Equals(provider, "LibreTranslate", StringComparison.OrdinalIgnoreCase))
        {
            return "LibreTranslate";
        }

        if (string.Equals(provider, "OpenAI", StringComparison.OrdinalIgnoreCase))
        {
            return "OpenAI";
        }

        return "Offline (Built-in)";
    }

    private static string FromProviderUiValue(string providerUi)
    {
        return providerUi switch
        {
            "OpenAI" => "OpenAI",
            "LibreTranslate" => "LibreTranslate",
            _ => "OfflineModel"
        };
    }

    private void ApplyProviderUiState(string providerUi)
    {
        if (providerUi == "LibreTranslate")
        {
            _baseUrlText.Text = _settings.LibreTranslateUrl;
            _apiKeyText.Text = _settings.LibreTranslateApiKey;
            _apiKeyText.Enabled = true;
            _baseUrlText.Enabled = true;
            _modelText.Enabled = false;
            return;
        }

        if (providerUi == "OpenAI")
        {
            _baseUrlText.Text = _settings.OpenAiBaseUrl;
            _apiKeyText.Text = _settings.OpenAiApiKey;
            _apiKeyText.Enabled = true;
            _baseUrlText.Enabled = true;
            _modelText.Enabled = true;
            return;
        }

        _baseUrlText.Text = "(offline built-in model)";
        _apiKeyText.Text = string.Empty;
        _apiKeyText.Enabled = false;
        _baseUrlText.Enabled = false;
        _modelText.Enabled = false;
    }

    private bool TryResolveToggleTarget(string currentInput, out string target)
    {
        target = string.Empty;
        if (_lastTranslationPair is null || string.IsNullOrWhiteSpace(_lastAppliedOutputText))
        {
            return false;
        }

        if ((DateTime.UtcNow - _lastAppliedAtUtc).TotalSeconds > 90)
        {
            return false;
        }

        var pair = _lastTranslationPair.Value;
        var currentMatchesEither = LooksEquivalent(currentInput, pair.Left) || LooksEquivalent(currentInput, pair.Right);
        if (!currentMatchesEither && (DateTime.UtcNow - _lastAppliedAtUtc).TotalSeconds > 2)
        {
            return false;
        }

        if (LooksEquivalent(_lastAppliedOutputText!, pair.Left))
        {
            target = pair.Right;
            return true;
        }

        if (LooksEquivalent(_lastAppliedOutputText!, pair.Right))
        {
            target = pair.Left;
            return true;
        }

        if (LooksEquivalent(currentInput, pair.Left))
        {
            target = pair.Right;
            return true;
        }

        if (LooksEquivalent(currentInput, pair.Right))
        {
            target = pair.Left;
            return true;
        }

        return false;
    }

    private bool TryGetCachedTranslation(string source, out string target)
    {
        target = string.Empty;
        var normalizedSource = NormalizeCacheKey(source);
        if (string.IsNullOrEmpty(normalizedSource))
        {
            return false;
        }

        if (_translationCache.TryGetValue(normalizedSource, out var direct) && !LooksEquivalent(direct, source))
        {
            target = direct;
            return true;
        }

        var sourceLoose = LooseCacheKey(normalizedSource);
        if (string.IsNullOrEmpty(sourceLoose))
        {
            return false;
        }

        foreach (var entry in _translationCache)
        {
            if (LooseCacheKey(entry.Key) == sourceLoose && !LooksEquivalent(entry.Value, source))
            {
                target = entry.Value;
                return true;
            }
        }

        foreach (var entry in _translationCache)
        {
            if (LooksEquivalent(normalizedSource, entry.Key) && !LooksEquivalent(entry.Value, source))
            {
                target = entry.Value;
                return true;
            }
        }

        return false;
    }

    private void CacheTranslationPair(string source, string target)
    {
        var sourceKey = NormalizeCacheKey(source);
        var targetKey = NormalizeCacheKey(target);
        if (string.IsNullOrEmpty(sourceKey) || string.IsNullOrEmpty(targetKey) || sourceKey == targetKey)
        {
            return;
        }

        UpsertTranslationCache(sourceKey, target);
        UpsertTranslationCache(targetKey, source);
    }

    private void UpsertTranslationCache(string key, string value)
    {
        if (!_translationCache.ContainsKey(key))
        {
            _translationCacheOrder.Enqueue(key);
        }

        _translationCache[key] = value;

        while (_translationCacheOrder.Count > MaxCacheEntries)
        {
            var oldest = _translationCacheOrder.Dequeue();
            _translationCache.Remove(oldest);
        }
    }

    private void RecordAppliedOutput(string output)
    {
        _lastAppliedOutputText = output;
        _lastAppliedAtUtc = DateTime.UtcNow;
    }

    private static bool LooksEquivalent(string lhs, string rhs)
    {
        var left = NormalizeCacheKey(lhs);
        var right = NormalizeCacheKey(rhs);
        if (string.IsNullOrEmpty(left) || string.IsNullOrEmpty(right))
        {
            return false;
        }

        if (string.Equals(left, right, StringComparison.Ordinal))
        {
            return true;
        }

        var leftLoose = LooseCacheKey(left);
        var rightLoose = LooseCacheKey(right);
        if (leftLoose.Length == 0 || rightLoose.Length == 0)
        {
            return false;
        }

        if (string.Equals(leftLoose, rightLoose, StringComparison.Ordinal))
        {
            return true;
        }

        var minLen = Math.Min(leftLoose.Length, rightLoose.Length);
        return minLen >= 4 && (leftLoose.Contains(rightLoose, StringComparison.Ordinal) || rightLoose.Contains(leftLoose, StringComparison.Ordinal));
    }

    private static string NormalizeCacheKey(string value)
    {
        return string.IsNullOrWhiteSpace(value) ? string.Empty : value.Trim();
    }

    private static string LooseCacheKey(string value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return string.Empty;
        }

        var builder = new StringBuilder(value.Length);
        var pendingSpace = false;

        foreach (var ch in value)
        {
            if (char.IsLetterOrDigit(ch))
            {
                if (pendingSpace && builder.Length > 0)
                {
                    builder.Append(' ');
                    pendingSpace = false;
                }

                builder.Append(char.ToLowerInvariant(ch));
                continue;
            }

            if (char.IsWhiteSpace(ch))
            {
                pendingSpace = builder.Length > 0;
            }
        }

        return builder.ToString();
    }
}
