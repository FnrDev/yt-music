using System.Runtime.InteropServices;

namespace YTMusic.Shell;

internal static class NativeMethods
{
    private const int DwmwaUseImmersiveDarkMode = 20; // Windows 10 20H1+
    private const int DwmwaCaptionColor = 35;         // Windows 11
    private const int DwmwaTextColor = 36;            // Windows 11

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);

    /// <summary>
    /// Dark title bar; on Windows 11 also a black caption with white text, so it
    /// blends into the page's black top bar. Older systems ignore what they don't support.
    /// </summary>
    public static void UseDarkTitleBar(IntPtr hwnd)
    {
        var enabled = 1;
        DwmSetWindowAttribute(hwnd, DwmwaUseImmersiveDarkMode, ref enabled, sizeof(int));
        var black = 0x000000; // COLORREF (0x00BBGGRR)
        DwmSetWindowAttribute(hwnd, DwmwaCaptionColor, ref black, sizeof(int));
        var white = 0xFFFFFF;
        DwmSetWindowAttribute(hwnd, DwmwaTextColor, ref white, sizeof(int));
    }
}
