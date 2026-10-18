using System.Windows;
using YTMusic.Player;
using YTMusic.Settings;
using Drawing = System.Drawing;
using Forms = System.Windows.Forms;

namespace YTMusic.Shell;

/// <summary>
/// Notification-area ("tray") icon: left-click shows or hides the window,
/// right-click opens playback controls. Also posts track-change notifications.
/// </summary>
public sealed class TrayController : IDisposable
{
    private const int MaxTooltipLength = 127; // NotifyIcon.Text limit

    private readonly PlayerModel _model;
    private readonly AppSettings _settings;
    private readonly Action _showWindow;
    private readonly Action _toggleWindow;
    private readonly Action _showSettings;
    private readonly Action _quit;
    private readonly Func<bool> _isWindowActive;
    private readonly Forms.NotifyIcon _icon;

    public TrayController(
        PlayerModel model,
        AppSettings settings,
        Action showWindow,
        Action toggleWindow,
        Action showSettings,
        Action quit,
        Func<bool> isWindowActive)
    {
        _model = model;
        _settings = settings;
        _showWindow = showWindow;
        _toggleWindow = toggleWindow;
        _showSettings = showSettings;
        _quit = quit;
        _isWindowActive = isWindowActive;

        _icon = new Forms.NotifyIcon
        {
            Icon = LoadIcon(),
            Text = "YT Music",
            Visible = true,
            ContextMenuStrip = new Forms.ContextMenuStrip(),
        };
        _icon.MouseClick += (_, e) =>
        {
            if (e.Button == Forms.MouseButtons.Left) _toggleWindow();
        };
        _icon.BalloonTipClicked += (_, _) => _showWindow();
        // Built on demand so it always reflects the current state.
        _icon.ContextMenuStrip.Opening += (_, _) => BuildMenu(_icon.ContextMenuStrip);

        model.StateChanged += OnStateChanged;
    }

    private static Drawing.Icon LoadIcon()
    {
        var resource = Application.GetResourceStream(new Uri("pack://application:,,,/Assets/AppIcon.ico"));
        using var stream = resource.Stream;
        return new Drawing.Icon(stream, Forms.SystemInformation.SmallIconSize);
    }

    private void OnStateChanged(PlayerState old, PlayerState state)
    {
        var tooltip = state.HasTrack ? $"{state.Title} — {state.Artist}" : "YT Music";
        _icon.Text = tooltip.Length > MaxTooltipLength ? tooltip[..(MaxTooltipLength - 1)] + "…" : tooltip;

        var trackChanged = old.TrackKey != state.TrackKey || !old.HasTrack;
        if (trackChanged && state.HasTrack && state.IsPlaying && !state.IsAd
            && _settings.NotifyOnTrackChange && !_isWindowActive())
        {
            // Shown as a toast on Windows 10/11.
            var details = string.Join(" — ", new[] { state.Artist, state.Album }.Where(s => s.Length > 0));
            _icon.ShowBalloonTip(4000, state.Title, details.Length > 0 ? details : " ", Forms.ToolTipIcon.None);
        }
    }

    private void BuildMenu(Forms.ContextMenuStrip menu)
    {
        var state = _model.State;
        menu.Items.Clear();

        if (state.HasTrack)
        {
            menu.Items.Add(new Forms.ToolStripMenuItem(state.Title) { Enabled = false, Font = new Drawing.Font(menu.Font, Drawing.FontStyle.Bold) });
            if (state.Artist.Length > 0) menu.Items.Add(new Forms.ToolStripMenuItem(state.Artist) { Enabled = false });
        }
        else
        {
            menu.Items.Add(new Forms.ToolStripMenuItem("Nothing playing") { Enabled = false });
        }
        menu.Items.Add(new Forms.ToolStripSeparator());

        menu.Items.Add(Item(state.IsPlaying ? "Pause" : "Play", state.HasTrack, () => _model.Send(PlayerCommand.PlayPause)));
        menu.Items.Add(Item("Next", state.HasTrack, () => _model.Send(PlayerCommand.Next)));
        menu.Items.Add(Item("Previous", state.HasTrack, () => _model.Send(PlayerCommand.Previous)));
        menu.Items.Add(new Forms.ToolStripSeparator());

        menu.Items.Add(Item("Like", state.HasTrack, () => _model.Send(PlayerCommand.Like), state.LikeStatus == "like"));
        menu.Items.Add(Item("Dislike", state.HasTrack, () => _model.Send(PlayerCommand.Dislike), state.LikeStatus == "dislike"));
        menu.Items.Add(Item("Shuffle", state.HasTrack, () => _model.Send(PlayerCommand.ToggleShuffle), state.Shuffle));
        var repeat = state.RepeatMode switch { "all" => "Repeat: All", "one" => "Repeat: One", _ => "Repeat: Off" };
        menu.Items.Add(Item(repeat, state.HasTrack, () => _model.Send(PlayerCommand.CycleRepeat), state.RepeatMode != "none"));
        menu.Items.Add(new Forms.ToolStripSeparator());

        menu.Items.Add(Item("Show YT Music", true, _showWindow));
        menu.Items.Add(Item("Settings…", true, _showSettings));
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add(Item("Quit YT Music", true, _quit));
    }

    private static Forms.ToolStripMenuItem Item(string title, bool enabled, Action action, bool isChecked = false)
    {
        var item = new Forms.ToolStripMenuItem(title) { Enabled = enabled, Checked = isChecked };
        item.Click += (_, _) => action();
        return item;
    }

    public void Dispose()
    {
        _model.StateChanged -= OnStateChanged;
        _icon.Visible = false;
        _icon.Dispose();
    }
}
