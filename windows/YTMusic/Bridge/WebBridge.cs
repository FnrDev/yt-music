using System.Diagnostics;
using System.Text.Json;
using Microsoft.Web.WebView2.Core;
using YTMusic.Player;

namespace YTMusic.Bridge;

/// <summary>
/// Connects ytm-bridge.js (shared with macOS) running in the page to <see cref="PlayerModel"/>.
/// The script posts JSON strings through window.chrome.webview.postMessage.
/// </summary>
public sealed class WebBridge
{
    private const int SupportedVersion = 1;

    private static readonly JsonSerializerOptions JsonOptions = new() { PropertyNameCaseInsensitive = true };

    private readonly PlayerModel _model;
    private CoreWebView2? _core;

    public WebBridge(PlayerModel model)
    {
        _model = model;
    }

    /// <summary>The page's top bar asked to move or zoom the window (unused while the system title bar is shown).</summary>
    public event Action? WindowDragRequested;
    public event Action? WindowZoomRequested;

    public async Task InstallAsync(CoreWebView2 core)
    {
        _core = core;
        // Runs in every frame at document creation; the script itself returns
        // early outside the top-level frame.
        await core.AddScriptToExecuteOnDocumentCreatedAsync(Resources.Read("ytm-bridge.js"));
        core.WebMessageReceived += OnWebMessageReceived;
        _model.CommandSink = command => _ = RunAsync(command);
    }

    private async Task RunAsync(PlayerCommand command)
    {
        if (_core is null) return;
        try
        {
            await _core.ExecuteScriptAsync(command.ToJavaScript());
        }
        catch (Exception error)
        {
            Debug.WriteLine($"Bridge command {command.Name} failed: {error.Message}");
        }
    }

    private void OnWebMessageReceived(object? sender, CoreWebView2WebMessageReceivedEventArgs e)
    {
        string json;
        try
        {
            json = e.TryGetWebMessageAsString();
        }
        catch (ArgumentException)
        {
            return; // not a string message
        }

        Envelope? envelope;
        try
        {
            envelope = JsonSerializer.Deserialize<Envelope>(json, JsonOptions);
        }
        catch (JsonException error)
        {
            Debug.WriteLine($"Bad bridge message: {error.Message}");
            return;
        }
        if (envelope is null) return;

        switch (envelope.Type)
        {
            case "ready":
                if (envelope.Version != SupportedVersion)
                    Debug.WriteLine($"Unexpected bridge version {envelope.Version}");
                _model.Reset();
                break;
            case "state" when envelope.State is not null:
                _model.Update(envelope.State);
                break;
            case "windowDrag":
                WindowDragRequested?.Invoke();
                break;
            case "windowZoom":
                WindowZoomRequested?.Invoke();
                break;
        }
    }

    private sealed record Envelope(string Type, int? Version, PlayerState? State);
}
