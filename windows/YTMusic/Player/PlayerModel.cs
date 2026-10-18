namespace YTMusic.Player;

/// <summary>
/// Single source of truth for playback state: the window, tray and notifications
/// all read from here. All members are used on the UI thread.
/// </summary>
public sealed class PlayerModel
{
    public PlayerState State { get; private set; } = PlayerState.Empty;

    /// <summary>When <see cref="State"/> was last received, for extrapolating position.</summary>
    public DateTime StateReceivedAt { get; private set; } = DateTime.UtcNow;

    /// <summary>Raised with the previous and new state after every update.</summary>
    public event Action<PlayerState, PlayerState>? StateChanged;

    /// <summary>Executes a command in the page. Set by <see cref="Bridge.WebBridge"/>.</summary>
    public Action<PlayerCommand>? CommandSink { get; set; }

    public void Update(PlayerState state)
    {
        var old = State;
        State = state;
        StateReceivedAt = DateTime.UtcNow;
        StateChanged?.Invoke(old, state);
    }

    public void Reset() => Update(PlayerState.Empty);

    public void Send(PlayerCommand command) => CommandSink?.Invoke(command);

    public void AdjustVolume(int delta) => Send(PlayerCommand.SetVolume(State.Volume + delta));
}
