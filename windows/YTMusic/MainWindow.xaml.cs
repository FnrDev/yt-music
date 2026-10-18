using System.ComponentModel;
using System.IO;
using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using Microsoft.Web.WebView2.Core;
using YTMusic.Bridge;
using YTMusic.Player;
using YTMusic.Settings;
using YTMusic.Shell;

namespace YTMusic;

public partial class MainWindow : System.Windows.Window
{
    public const string HomeUrl = "https://music.youtube.com/";

    private readonly PlayerModel _model;
    private readonly WebBridge _bridge;
    private readonly ThemeController _theme;
    private readonly AppSettings _settings;

    /// <summary>Set when quitting; otherwise closing may only hide the window.</summary>
    public bool AllowClose { get; set; }

    public MainWindow(PlayerModel model, WebBridge bridge, ThemeController theme, AppSettings settings)
    {
        _model = model;
        _bridge = bridge;
        _theme = theme;
        _settings = settings;

        InitializeComponent();
        RestoreWindowBounds();
        WebView.DefaultBackgroundColor = System.Drawing.Color.Black; // no white flash while loading

        SourceInitialized += (_, _) => NativeMethods.UseDarkTitleBar(new WindowInteropHelper(this).Handle);
        Loaded += async (_, _) => await InitializeWebViewAsync();
        PreviewKeyDown += OnPreviewKeyDown;
        Closing += OnClosing;
    }

    private async Task InitializeWebViewAsync()
    {
        try
        {
            // Persistent profile, so the Google sign-in survives restarts.
            var userData = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "YTMusic", "WebView2");
            var environment = await CoreWebView2Environment.CreateAsync(null, userData);
            await WebView.EnsureCoreWebView2Async(environment);
        }
        catch (WebView2RuntimeNotFoundException)
        {
            ShowLoadError("YT Music needs the Microsoft Edge WebView2 Runtime, which is part of Windows 10 and 11.\n"
                + "Install it from https://go.microsoft.com/fwlink/p/?LinkId=2124703 and restart YT Music.");
            return;
        }

        var core = WebView.CoreWebView2;
        core.Settings.IsStatusBarEnabled = false;
#if DEBUG
        core.Settings.AreDevToolsEnabled = true;
#else
        core.Settings.AreDevToolsEnabled = false;
#endif

        await _bridge.InstallAsync(core);
        await _theme.InstallAsync(core);

        core.NavigationStarting += (_, e) =>
        {
            if (NavigationPolicy.BelongsInApp(e.Uri)) return;
            e.Cancel = true;
            NavigationPolicy.OpenExternally(e.Uri);
        };
        // target=_blank links and window.open.
        core.NewWindowRequested += (_, e) =>
        {
            e.Handled = true;
            if (NavigationPolicy.BelongsInApp(e.Uri)) core.Navigate(e.Uri);
            else NavigationPolicy.OpenExternally(e.Uri);
        };
        core.ProcessFailed += (_, e) =>
        {
            if (e.ProcessFailedKind == CoreWebView2ProcessFailedKind.RenderProcessExited) core.Reload();
        };

        core.Navigate(HomeUrl);
    }

    private void ShowLoadError(string message)
    {
        WebView.Visibility = Visibility.Collapsed;
        LoadError.Text = message;
        LoadError.Visibility = Visibility.Visible;
    }

    // MARK: Keyboard shortcuts

    private void OnPreviewKeyDown(object sender, KeyEventArgs e)
    {
        var ctrl = Keyboard.Modifiers == ModifierKeys.Control;
        var alt = Keyboard.Modifiers == ModifierKeys.Alt;
        var key = e.Key == Key.System ? e.SystemKey : e.Key;

        Action? action = (ctrl, alt, key) switch
        {
            (true, _, Key.Right) => () => _model.Send(PlayerCommand.Next),
            (true, _, Key.Left) => () => _model.Send(PlayerCommand.Previous),
            (true, _, Key.Up) => () => _model.AdjustVolume(10),
            (true, _, Key.Down) => () => _model.AdjustVolume(-10),
            (true, _, Key.L) => () => _model.Send(PlayerCommand.Like),
            (true, _, Key.S) => () => _model.Send(PlayerCommand.ToggleShuffle),
            (true, _, Key.R) => () => _model.Send(PlayerCommand.CycleRepeat),
            (true, _, Key.F) => () => _model.Send(PlayerCommand.FocusSearch),
            (_, true, Key.Left) => () => WebView.CoreWebView2?.GoBack(),
            (_, true, Key.Right) => () => WebView.CoreWebView2?.GoForward(),
            (false, false, Key.F5) => () => WebView.CoreWebView2?.Reload(),
            _ => null,
        };
        if (action is null) return;
        action();
        e.Handled = true;
    }

    // MARK: Closing and window position

    private void OnClosing(object? sender, CancelEventArgs e)
    {
        SaveWindowBounds();
        if (AllowClose || !_settings.KeepPlayingWhenClosed)
        {
            if (!AllowClose) ((App)Application.Current).Quit();
            return;
        }
        // Hide instead of closing so the web view (and the music) keeps running.
        e.Cancel = true;
        Hide();
    }

    private void RestoreWindowBounds()
    {
        if (_settings.Window is not { } bounds) return;
        var screen = new Rect(SystemParameters.VirtualScreenLeft, SystemParameters.VirtualScreenTop,
            SystemParameters.VirtualScreenWidth, SystemParameters.VirtualScreenHeight);
        var saved = new Rect(bounds.Left, bounds.Top, bounds.Width, bounds.Height);
        if (!screen.IntersectsWith(saved)) return; // the monitor it was on is gone
        WindowStartupLocation = WindowStartupLocation.Manual;
        Left = bounds.Left;
        Top = bounds.Top;
        Width = Math.Max(bounds.Width, MinWidth);
        Height = Math.Max(bounds.Height, MinHeight);
        if (bounds.Maximized) WindowState = WindowState.Maximized;
    }

    private void SaveWindowBounds()
    {
        var normal = WindowState == WindowState.Normal ? new Rect(Left, Top, Width, Height) : RestoreBounds;
        if (normal.IsEmpty) return;
        _settings.Window = new AppSettings.WindowBounds(normal.Left, normal.Top, normal.Width, normal.Height,
            WindowState == WindowState.Maximized);
        _settings.Save();
    }
}
