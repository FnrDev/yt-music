using System.Threading;
using System.Windows;
using YTMusic.Bridge;
using YTMusic.Player;
using YTMusic.Settings;
using YTMusic.Shell;

namespace YTMusic;

public partial class App : Application
{
    private const string InstanceMutexName = @"Local\YTMusic.SingleInstance";
    private const string ShowEventName = @"Local\YTMusic.Show";

    private Mutex? _instanceMutex;
    private EventWaitHandle? _showSignal;
    private AppSettings _settings = new();
    private VolumeKeeper? _volumeKeeper;
    private MainWindow? _window;
    private TrayController? _tray;
    private SettingsWindow? _settingsWindow;

    protected override void OnStartup(StartupEventArgs e)
    {
        // One instance: a second launch just brings the running one forward.
        _instanceMutex = new Mutex(true, InstanceMutexName, out var isFirstInstance);
        if (!isFirstInstance)
        {
            if (EventWaitHandle.TryOpenExisting(ShowEventName, out var running)) running.Set();
            Shutdown();
            return;
        }
        _showSignal = new EventWaitHandle(false, EventResetMode.AutoReset, ShowEventName);
        ThreadPool.RegisterWaitForSingleObject(_showSignal, (_, _) => Dispatcher.Invoke(ShowMainWindow), null, -1, false);

        base.OnStartup(e);

        _settings = AppSettings.Load();
        var model = new PlayerModel();
        _volumeKeeper = new VolumeKeeper(model, _settings);
        _window = new MainWindow(model, new WebBridge(model), new ThemeController(_settings), _settings);
        _tray = new TrayController(model, _settings,
            showWindow: ShowMainWindow,
            toggleWindow: ToggleMainWindow,
            showSettings: ShowSettings,
            quit: Quit,
            isWindowActive: () => _window.IsActive);

        _window.Show();
    }

    public void ShowMainWindow()
    {
        if (_window is null) return;
        _window.Show();
        if (_window.WindowState == WindowState.Minimized) _window.WindowState = WindowState.Normal;
        _window.Activate();
    }

    private void ToggleMainWindow()
    {
        if (_window is { IsVisible: true, IsActive: true }) _window.Hide();
        else ShowMainWindow();
    }

    private void ShowSettings()
    {
        if (_settingsWindow is null)
        {
            _settingsWindow = new SettingsWindow(_settings);
            if (_window?.IsVisible == true) _settingsWindow.Owner = _window;
            _settingsWindow.Closed += (_, _) => _settingsWindow = null;
        }
        _settingsWindow.Show();
        _settingsWindow.Activate();
    }

    public void Quit()
    {
        _tray?.Dispose();
        _tray = null;
        if (_window is not null)
        {
            _window.AllowClose = true;
            _window.Close();
        }
        Shutdown();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _tray?.Dispose();
        _showSignal?.Dispose();
        _instanceMutex?.Dispose();
        base.OnExit(e);
    }
}
