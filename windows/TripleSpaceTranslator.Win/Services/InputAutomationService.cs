using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using System.Windows.Forms;

namespace TripleSpaceTranslator.Win.Services;

public sealed class InputAutomationService
{
    private static readonly Regex ChineseRegex = new("[\u3400-\u9FFF]", RegexOptions.Compiled);

    public string? ReadFocusedText()
    {
        return CopyAllTextFallback();
    }

    public bool ReplaceFocusedText(string translated)
    {
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
        SendKey(Keys.LControlKey, keyDown: true);
        SendKey(key, keyDown: true);
        SendKey(key, keyDown: false);
        SendKey(Keys.LControlKey, keyDown: false);
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
                    dwExtraInfo = UIntPtr.Zero
                }
            }
        };

        var sent = SendInput(1, new[] { input }, Marshal.SizeOf<Input>());
        if (sent == 0)
        {
            var error = Marshal.GetLastWin32Error();
            throw new InvalidOperationException($"Failed to send key input. Win32Error={error} ({new Win32Exception(error).Message})");
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
                        dwExtraInfo = UIntPtr.Zero
                    }
                }
            };

            var up = down;
            up.U.ki.dwFlags = 0x0004 | 0x0002;

            var sent = SendInput(2, new[] { down, up }, Marshal.SizeOf<Input>());
            if (sent == 0)
            {
                var error = Marshal.GetLastWin32Error();
                throw new InvalidOperationException($"Failed to send unicode input. Win32Error={error} ({new Win32Exception(error).Message})");
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
        public MouseInput mi;

        [FieldOffset(0)]
        public KeyboardInput ki;

        [FieldOffset(0)]
        public HardwareInput hi;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MouseInput
    {
        public int dx;
        public int dy;
        public uint mouseData;
        public uint dwFlags;
        public uint time;
        public UIntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct HardwareInput
    {
        public uint uMsg;
        public ushort wParamL;
        public ushort wParamH;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KeyboardInput
    {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public UIntPtr dwExtraInfo;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint nInputs, Input[] pInputs, int cbSize);
}
