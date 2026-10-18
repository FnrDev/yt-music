using System.Diagnostics;
using System.Text.RegularExpressions;

namespace YTMusic.Shell;

/// <summary>
/// Keeps YouTube Music and Google sign-in inside the app; sends everything else
/// (artist websites, help pages, …) to the default browser. Same list as macOS.
/// </summary>
internal static partial class NavigationPolicy
{
    private static readonly string[] InAppDomains =
    [
        "youtube.com", "youtu.be", "ytimg.com", "googlevideo.com",
        "google.com", "gstatic.com", "googleusercontent.com", "googleapis.com",
    ];

    // Regional Google sign-in hosts, e.g. accounts.google.com.sa / google.co.uk.
    [GeneratedRegex(@"(^|\.)google\.(co\.)?[a-z]{2,3}(\.[a-z]{2})?$")]
    private static partial Regex RegionalGoogle();

    public static bool BelongsInApp(string url)
    {
        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri)) return false;
        if (uri.Scheme is "about" or "blob" or "data") return true;
        if (uri.Scheme is not ("https" or "http")) return false;
        var host = uri.Host.ToLowerInvariant();
        return InAppDomains.Any(domain => host == domain || host.EndsWith("." + domain))
            || RegionalGoogle().IsMatch(host);
    }

    public static void OpenExternally(string url)
    {
        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri) || uri.Scheme is not ("https" or "http" or "mailto"))
            return; // don't hand arbitrary schemes to the shell
        Process.Start(new ProcessStartInfo(uri.AbsoluteUri) { UseShellExecute = true });
    }
}
