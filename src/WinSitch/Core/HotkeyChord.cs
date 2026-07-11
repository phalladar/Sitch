using System.Text;
using System.Windows.Input;

namespace WinSitch.Core;

/// <summary>A global hotkey combination, serialized as e.g. "Ctrl+Alt+4" or "Ctrl+Shift+PrintScreen".</summary>
public readonly record struct HotkeyChord(ModifierKeys Modifiers, Key Key)
{
    public const uint ModAlt = 0x0001, ModControl = 0x0002, ModShift = 0x0004, ModWin = 0x0008, ModNoRepeat = 0x4000;

    public uint NativeModifiers
    {
        get
        {
            uint m = ModNoRepeat;
            if (Modifiers.HasFlag(ModifierKeys.Alt)) m |= ModAlt;
            if (Modifiers.HasFlag(ModifierKeys.Control)) m |= ModControl;
            if (Modifiers.HasFlag(ModifierKeys.Shift)) m |= ModShift;
            if (Modifiers.HasFlag(ModifierKeys.Windows)) m |= ModWin;
            return m;
        }
    }

    public uint VirtualKey => (uint)KeyInterop.VirtualKeyFromKey(Key);

    public override string ToString()
    {
        var sb = new StringBuilder();
        if (Modifiers.HasFlag(ModifierKeys.Control)) sb.Append("Ctrl+");
        if (Modifiers.HasFlag(ModifierKeys.Alt)) sb.Append("Alt+");
        if (Modifiers.HasFlag(ModifierKeys.Shift)) sb.Append("Shift+");
        if (Modifiers.HasFlag(ModifierKeys.Windows)) sb.Append("Win+");
        sb.Append(KeyName(Key));
        return sb.ToString();
    }

    public static string KeyName(Key key) => key switch
    {
        >= Key.D0 and <= Key.D9 => ((char)('0' + (key - Key.D0))).ToString(),
        >= Key.NumPad0 and <= Key.NumPad9 => "Num" + (key - Key.NumPad0),
        Key.Snapshot => "PrintScreen",
        Key.Oem3 => "`",
        _ => key.ToString(),
    };

    public static bool TryParse(string? text, out HotkeyChord chord)
    {
        chord = default;
        if (string.IsNullOrWhiteSpace(text)) return false;
        var mods = ModifierKeys.None;
        Key key = Key.None;
        foreach (var raw in text.Split('+', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            switch (raw.ToLowerInvariant())
            {
                case "ctrl" or "control": mods |= ModifierKeys.Control; break;
                case "alt": mods |= ModifierKeys.Alt; break;
                case "shift": mods |= ModifierKeys.Shift; break;
                case "win" or "windows": mods |= ModifierKeys.Windows; break;
                case "printscreen" or "prtsc": key = Key.Snapshot; break;
                default:
                    if (raw.Length == 1 && raw[0] is >= '0' and <= '9')
                        key = Key.D0 + (raw[0] - '0');
                    else if (raw.StartsWith("num", StringComparison.OrdinalIgnoreCase) &&
                             raw.Length == 4 && raw[3] is >= '0' and <= '9')
                        key = Key.NumPad0 + (raw[3] - '0');
                    else if (Enum.TryParse<Key>(raw, ignoreCase: true, out var k))
                        key = k;
                    break;
            }
        }
        if (key == Key.None) return false;
        chord = new HotkeyChord(mods, key);
        return true;
    }
}
