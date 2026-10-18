using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using YTMusic.Shell;

namespace YTMusic.Settings;

public partial class SettingsWindow : System.Windows.Window
{
    private readonly AppSettings _settings;
    private bool _loading = true;

    public SettingsWindow(AppSettings settings)
    {
        _settings = settings;
        InitializeComponent();
        SourceInitialized += (_, _) => NativeMethods.UseDarkTitleBar(new WindowInteropHelper(this).Handle);

        ThemePicker.SelectedItem = ThemePicker.Items.Cast<ComboBoxItem>()
            .First(item => (string)item.Tag == settings.Theme.ToString());
        KeepPlaying.IsChecked = settings.KeepPlayingWhenClosed;
        Notify.IsChecked = settings.NotifyOnTrackChange;
        _loading = false;
    }

    private void OnThemeChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_loading || ThemePicker.SelectedItem is not ComboBoxItem { Tag: string tag }) return;
        _settings.Theme = Enum.Parse<ThemeChoice>(tag);
        _settings.Save(); // the theme controller restyles the page live
    }

    private void OnOptionChanged(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        _settings.KeepPlayingWhenClosed = KeepPlaying.IsChecked == true;
        _settings.NotifyOnTrackChange = Notify.IsChecked == true;
        _settings.Save();
    }
}
