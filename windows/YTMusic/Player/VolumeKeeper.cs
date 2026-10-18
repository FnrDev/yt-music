using YTMusic.Settings;

namespace YTMusic.Player;

/// <summary>
/// Remembers the volume across launches. YT Music saves its slider level in a
/// cookie, which isn't reliably flushed before quitting, so we keep our own copy
/// and re-apply it once the player is up. (Same logic as the macOS VolumeKeeper.)
/// </summary>
public sealed class VolumeKeeper
{
    private readonly PlayerModel _model;
    private readonly AppSettings _settings;
    /// <summary>True from a page load until the page's volume is reconciled with ours.</summary>
    private bool _restoring = true;

    public VolumeKeeper(PlayerModel model, AppSettings settings)
    {
        _model = model;
        _settings = settings;
        model.StateChanged += OnStateChanged;
    }

    private void OnStateChanged(PlayerState old, PlayerState state)
    {
        if (state == PlayerState.Empty)
        {
            _restoring = true; // page (re)loaded
            return;
        }
        // The player bar's slider is only reliable once a track is loaded.
        if (!state.HasTrack) return;

        if (_restoring)
        {
            _restoring = false;
            if (_settings.LastVolume is { } saved && saved != state.Volume)
                _model.Send(PlayerCommand.SetVolume(saved));
            else
                Remember(state.Volume);
        }
        else if (state.Volume != old.Volume)
        {
            Remember(state.Volume);
        }
    }

    private void Remember(int volume)
    {
        if (_settings.LastVolume == volume) return;
        _settings.LastVolume = volume;
        _settings.Save();
    }
}
