using System.Text.Json;
using System.Text.Json.Serialization;

namespace YTMusic.Player;

/// <summary>Snapshot of the web player, as reported by ytm-bridge.js (see shared/PROTOCOL.md).</summary>
public sealed record PlayerState
{
    public bool HasTrack { get; init; }
    public bool IsAd { get; init; }
    public string? VideoId { get; init; }
    public string Title { get; init; } = "";
    public string Artist { get; init; } = "";
    public string Album { get; init; } = "";
    public string? ArtworkURL { get; init; }
    public bool IsPlaying { get; init; }
    public double Position { get; init; }
    public double Duration { get; init; }
    public string LikeStatus { get; init; } = "indifferent";
    public int Volume { get; init; } = 100;
    public bool Shuffle { get; init; }
    public string RepeatMode { get; init; } = "none";

    public static readonly PlayerState Empty = new();

    /// <summary>Identifies the track for change detection.</summary>
    [JsonIgnore]
    public string TrackKey => VideoId ?? $"{Title}\u001F{Artist}";
}

/// <summary>Commands the host can run in the page (shared/PROTOCOL.md, "Host → page").</summary>
public sealed record PlayerCommand(string Name, object? Argument = null)
{
    public static readonly PlayerCommand PlayPause = new("playPause");
    public static readonly PlayerCommand Play = new("play");
    public static readonly PlayerCommand Pause = new("pause");
    public static readonly PlayerCommand Next = new("next");
    public static readonly PlayerCommand Previous = new("previous");
    public static readonly PlayerCommand Like = new("like");
    public static readonly PlayerCommand Dislike = new("dislike");
    public static readonly PlayerCommand FocusSearch = new("focusSearch");
    public static readonly PlayerCommand ToggleShuffle = new("toggleShuffle");
    public static readonly PlayerCommand CycleRepeat = new("cycleRepeat");

    public static PlayerCommand Seek(double seconds) => new("seek", seconds);
    public static PlayerCommand SetVolume(int volume) => new("setVolume", Math.Clamp(volume, 0, 100));

    /// <summary>JS evaluated in the page to run this command. The argument is JSON, which is valid JS.</summary>
    public string ToJavaScript()
    {
        var argument = Argument is null ? "undefined" : JsonSerializer.Serialize(Argument);
        return $"window.__ytmBridge && window.__ytmBridge.command({JsonSerializer.Serialize(Name)}, {argument});";
    }
}
