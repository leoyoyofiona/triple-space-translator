using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using System.Windows.Automation;
using System.Windows.Forms;

namespace TripleSpaceTranslator.Win.Services;

public sealed class InputAutomationService
{
    private static readonly Regex ChineseRegex = new("[\u3400-\u9FFF]", RegexOptions.Compiled);

    public string? ReadFocusedText()
    {
        var element = AutomationElement.FocusedElement;
        if (element is null)
        {
            return null;
        }

        if (element.TryGetCurrentPattern(ValuePattern.Pattern, out var valuePatternObj))
        {
            var valuePattern = (ValuePattern)valuePatternObj;
            if (!string.IsNullOrEmpty(valuePattern.Current.Value))
            {
                return valuePattern.Current.Value;
            }
        }

        if (element.TryGetCurrentPattern(TextPattern.Pattern, out var textPatternObj))
        {
            var textPattern = (TextPattern)textPatternObj;
            var text = textPattern.DocumentRange.GetText(-1);
            if (!string.IsNullOrWhiteSpace(text))
            {
                return text;
            }
        }

        return CopyAllTextFallback();
    }

    public bool ReplaceFocusedText(string translated)
    {
        var element = AutomationElement.FocusedElement;
        if (element is null)
        {
            return false;
        }

        if (element.TryGetCurrentPattern(ValuePattern.Pattern, out var valuePatternObj))
        {
            var valuePattern = (ValuePattern)valuePatternObj;
            if (!valuePattern.Current.IsReadOnly)
            {
                valuePattern.SetValue(translated);
                return true;
            }
        }

        if (TrySetSelectedTextPattern(element, translated))
        {
            return true;
        }

        if (PasteReplaceFallback(translated))
        {
            return true;
        }

        return TypeReplaceFallback(translated);
    }

    public static bool LooksLikeChinese(string value)
    {
        return ChineseRegex.IsMatch(value);
    }

    public static string RemoveTrailingSpaces(string input, int count)
    {
        var result = input;
        for (var i = 0; i < count && result.EndsWith(' '); i++)
        {
            result = result[..^1];
        }

        return result;
    }

    private static bool TrySetSelectedTextPattern(AutomationElement element, string translated)
    {
        try
        {
            SendCtrlChord(Keys.A);
            Thread.Sleep(80);

            if (element.TryGetCurrentPattern(TextPattern.Pattern, out _))
            {
                SendUnicodeText(translated);
                return true;
            }
        }
        catch
        {
            // ignore and continue fallback chain
        }

        return false;
    }

    private static string? CopyAllTextFallback()
    {
        IDataObject? snapshot = null;
        try
        {
            snapshot = Clipboard.GetDataObject();
        }
        catch
        {
            // ignore
        }

        try
        {
            SendCtrlChord(Keys.A);
            Thread.Sleep(60);
            SendCtrlChord(Keys.C);
            Thread.Sleep(100);

            var text = Clipboard.ContainsText() ? Clipboard.GetText() : null;
            return string.IsNullOrWhiteSpace(text) ? null : text;
        }
        finally
        {
            TryRestoreClipboard(snapshot);
        }
    }

    private static bool PasteReplaceFallback(string translated)
    {
        IDataObject? snapshot = null;
        try
        {
            snapshot = Clipboard.GetDataObject();
        }
        catch
        {
            // ignore
        }

        try
        {
            Clipboard.SetText(translated);
            SendCtrlChord(Keys.A);
            Thread.Sleep(60);
            SendCtrlChord(Keys.V);
            Thread.Sleep(120);
            return true;
        }
        catch
        {
            return false;
        }
        finally
        {
            TryRestoreClipboard(snapshot);
        }
    }

    private static bool TypeReplaceFallback(string translated)
    {
        try
        {
            SendCtrlChord(Keys.A);
            Thread.Sleep(50);
            SendKey(Keys.Back);
            Thread.Sleep(20);
            SendUnicodeText(translated);
            return true;
        }
        catch
        {
            return false;
        }
    }

    private static void TryRestoreClipboard(IDataObject? snapshot)
    {
        if (snapshot is null)
        {
            return;
        }

        try
        {
            Clipboard.SetDataObject(snapshot, true);
        }
        catch
        {
            // ignore
        }
    }

    private static void SendCtrlChord(Keys key)
    {
        SendKey(Keys.ControlKey, keyDown: true);
        SendKey(key, keyDown: true);
        SendKey(key, keyDown: false);
        SendKey(Keys.ControlKey, keyDown: false);
    }

    private static void SendKey(Keys key, bool keyDown = true)
    {
        var input = new Input
        {
            type = 1,
            U = new InputUnion
            {
                ki = new KeyboardInput
                {
                    wVk = (ushort)key,
                    wScan = 0,
                    dwFlags = keyDown ? 0u : 0x0002u,
                    time = 0,
                    dwExtraInfo = IntPtr.Zero
                }
            }
        };

        var sent = SendInput(1, new[] { input }, Marshal.SizeOf<Input>());
        if (sent == 0)
        {
            throw new InvalidOperationException("Failed to send key input.");
        }
    }

    private static void SendUnicodeText(string text)
    {
        foreach (var ch in text)
        {
            var down = new Input
            {
                type = 1,
                U = new InputUnion
                {
                    ki = new KeyboardInput
                    {
                        wVk = 0,
                        wScan = ch,
                        dwFlags = 0x0004,
                        time = 0,
                        dwExtraInfo = IntPtr.Zero
                    }
                }
            };

            var up = down;
            up.U.ki.dwFlags = 0x0004 | 0x0002;

            var sent = SendInput(2, new[] { down, up }, Marshal.SizeOf<Input>());
            if (sent == 0)
            {
                throw new InvalidOperationException("Failed to send unicode input.");
            }
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Input
    {
        public uint type;
        public InputUnion U;
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct InputUnion
    {
        [FieldOffset(0)]
        public KeyboardInput ki;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KeyboardInput
    {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint nInputs, Input[] pInputs, int cbSize);
}
