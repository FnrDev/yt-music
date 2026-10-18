using System.Diagnostics;
using System.IO;
using System.Text.Json;

namespace YTMusic.Settings;

public enum ThemeChoice
{
    YouTubeMusic,
    SpotifyStyle,
}

/// <summary>
/// Preferences, saved as JSON in %APPDATA%\YTMusic\settings.json. Used on the UI thread.
/// </summary>
public sealed class AppSettings
{
    public ThemeChoice Theme { get; set; } = ThemeChoice.SpotifyStyle;
    public bool KeepPlayingWhenClosed { get; set; } = true;
    public bool NotifyOnTrackChange { get; set; } = true;
    /// <summary>Last volume on YT Music's slider scale; see <see cref="Player.VolumeKeeper"/>.</summary>
    public int? LastVolume { get; set; }
    public WindowBounds? Window { get; set; }

    public sealed record WindowBounds(double Left, double Top, double Width, double Height, bool Maximized);

    /// <summary>Raised after <see cref="Save"/>.</summary>
    public event Action? Changed;

    private static readonly string FilePath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "YTMusic", "settings.json");

    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };

    public static AppSettings Load()
    {
        try
        {
            if (File.Exists(FilePath))
                return JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(FilePath), JsonOptions) ?? new();
        }
        catch (Exception error) when (error is IOException or JsonException or UnauthorizedAccessException)
        {
            Debug.WriteLine($"Settings unreadable, using defaults: {error.Message}");
        }
        return new();
    }

    public void Save()
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
            File.WriteAllText(FilePath, JsonSerializer.Serialize(this, JsonOptions));
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            Debug.WriteLine($"Settings not saved: {error.Message}");
        }
        Changed?.Invoke();
    }
}
