using System.Diagnostics;
using System.Text;

namespace TripleSpaceTranslator.Win.Services.Translation;

public sealed class OfflineModelTranslator : ITranslator
{
    public async Task<string> TranslateAsync(string text, string sourceLang, string targetLang, CancellationToken cancellationToken)
    {
        var pythonExe = ResolvePythonExecutablePath();
        var scriptPath = ResolveScriptPath();
        var seedHome = ResolveSeedHomePath();
        var offlineHome = ResolveOfflineHomePath();
        var userSitePackages = ResolveUserSitePackagesPath();

        if (!File.Exists(pythonExe))
        {
            throw new InvalidOperationException($"Offline runtime missing python executable: {pythonExe}");
        }

        if (!File.Exists(scriptPath))
        {
            throw new InvalidOperationException($"Offline runtime missing translator script: {scriptPath}");
        }

        var source = NormalizeLang(sourceLang);
        var target = NormalizeLang(targetLang);
        Directory.CreateDirectory(offlineHome);
        Directory.CreateDirectory(userSitePackages);

        if (!IsSupportedPair(source, target))
        {
            throw new InvalidOperationException($"Offline model only supports zh<->en currently. Requested: {source}->{target}");
        }

        var startInfo = new ProcessStartInfo
        {
            FileName = pythonExe,
            Arguments = $"\"{scriptPath}\" --source {source} --target {target}",
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8
        };
        startInfo.EnvironmentVariables["PYTHONUTF8"] = "1";
        startInfo.EnvironmentVariables["PYTHONNOUSERSITE"] = "1";
        startInfo.EnvironmentVariables["HOME"] = offlineHome;
        startInfo.EnvironmentVariables["USERPROFILE"] = offlineHome;
        startInfo.EnvironmentVariables["ARGOS_STANZA_AVAILABLE"] = "0";
        var pythonRoot = Path.Combine(AppContext.BaseDirectory, "offline-runtime", "python");
        var sitePackages = Path.Combine(pythonRoot, "Lib", "site-packages");
        startInfo.EnvironmentVariables["PYTHONPATH"] = string.Join(";", new[] { pythonRoot, sitePackages, userSitePackages });
        startInfo.EnvironmentVariables["TST_OFFLINE_USER_SITE"] = userSitePackages;
        if (Directory.Exists(seedHome))
        {
            startInfo.EnvironmentVariables["TST_OFFLINE_SEED_HOME"] = seedHome;
        }

        using var process = new Process { StartInfo = startInfo };
        if (!process.Start())
        {
            throw new InvalidOperationException("Failed to start offline translator process.");
        }

        using var reg = cancellationToken.Register(() =>
        {
            try
            {
                if (!process.HasExited)
                {
                    process.Kill(entireProcessTree: true);
                }
            }
            catch
            {
                // ignore cancellation kill failures
            }
        });

        await process.StandardInput.WriteAsync(text.AsMemory(), cancellationToken);
        await process.StandardInput.FlushAsync();
        process.StandardInput.Close();

        var stdoutTask = process.StandardOutput.ReadToEndAsync(cancellationToken);
        var stderrTask = process.StandardError.ReadToEndAsync(cancellationToken);
        await process.WaitForExitAsync(cancellationToken);

        var stdout = (await stdoutTask).Trim();
        var stderr = (await stderrTask).Trim();

        if (process.ExitCode != 0)
        {
            var detail = string.IsNullOrWhiteSpace(stderr) ? $"exit code {process.ExitCode}" : stderr;
            throw new InvalidOperationException($"Offline translator failed: {detail}");
        }

        if (string.IsNullOrWhiteSpace(stdout))
        {
            throw new InvalidOperationException("Offline translator returned empty text.");
        }

        return stdout;
    }

    private static bool IsSupportedPair(string source, string target)
    {
        return (source == "zh" && target == "en") || (source == "en" && target == "zh");
    }

    private static string NormalizeLang(string lang)
    {
        if (string.IsNullOrWhiteSpace(lang))
        {
            return string.Empty;
        }

        var value = lang.Trim().ToLowerInvariant();
        if (value.StartsWith("zh"))
        {
            return "zh";
        }

        if (value.StartsWith("en"))
        {
            return "en";
        }

        var dash = value.IndexOf('-');
        return dash > 0 ? value[..dash] : value;
    }

    private static string ResolvePythonExecutablePath()
    {
        var envOverride = Environment.GetEnvironmentVariable("TST_OFFLINE_PYTHON");
        if (!string.IsNullOrWhiteSpace(envOverride))
        {
            return envOverride;
        }

        return Path.Combine(AppContext.BaseDirectory, "offline-runtime", "python", "python.exe");
    }

    private static string ResolveScriptPath()
    {
        var envOverride = Environment.GetEnvironmentVariable("TST_OFFLINE_SCRIPT");
        if (!string.IsNullOrWhiteSpace(envOverride))
        {
            return envOverride;
        }

        return Path.Combine(AppContext.BaseDirectory, "offline-runtime", "translate_once.py");
    }

    private static string ResolveOfflineHomePath()
    {
        var envOverride = Environment.GetEnvironmentVariable("TST_OFFLINE_HOME");
        if (!string.IsNullOrWhiteSpace(envOverride))
        {
            return envOverride;
        }

        var localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        return Path.Combine(localAppData, "TripleSpaceTranslator", "offline-home");
    }

    private static string ResolveSeedHomePath()
    {
        var envOverride = Environment.GetEnvironmentVariable("TST_OFFLINE_SEED_HOME");
        if (!string.IsNullOrWhiteSpace(envOverride))
        {
            return envOverride;
        }

        return Path.Combine(AppContext.BaseDirectory, "offline-runtime", "home");
    }

    private static string ResolveUserSitePackagesPath()
    {
        var envOverride = Environment.GetEnvironmentVariable("TST_OFFLINE_USER_SITE");
        if (!string.IsNullOrWhiteSpace(envOverride))
        {
            return envOverride;
        }

        var localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        return Path.Combine(localAppData, "TripleSpaceTranslator", "offline-site-packages");
    }
}
