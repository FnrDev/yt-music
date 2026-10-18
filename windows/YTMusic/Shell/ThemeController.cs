using System.Text.Json;
using Microsoft.Web.WebView2.Core;
using YTMusic.Settings;

namespace YTMusic.Shell;

/// <summary>
/// Injects the selected stylesheet from shared/themes (plus its optional
/// companion script) and swaps it live when the setting changes.
/// </summary>
public sealed class ThemeController
{
    private const string StyleElementId = "ytm-host-theme";

    private readonly AppSettings _settings;
    private CoreWebView2? _core;
    private string? _scriptId;
    private ThemeChoice? _applied;

    public ThemeController(AppSettings settings)
    {
        _settings = settings;
    }

    public async Task InstallAsync(CoreWebView2 core)
    {
        _core = core;
        await ApplyAsync(_settings.Theme);
        _settings.Changed += () => _ = ApplyAsync(_settings.Theme);
    }

    private async Task ApplyAsync(ThemeChoice theme)
    {
        if (_core is null || theme == _applied) return;
        _applied = theme;

        var source = Script(Stylesheet(theme), CompanionScript(theme));
        // Unlike WKWebView, WebView2 can remove one injected script by id.
        if (_scriptId is not null) _core.RemoveScriptToExecuteOnDocumentCreated(_scriptId);
        _scriptId = await _core.AddScriptToExecuteOnDocumentCreatedAsync(source);
        // Restyle the page that's already loaded.
        await _core.ExecuteScriptAsync(source);
    }

    private static string StylesheetName(ThemeChoice theme) => theme switch
    {
        ThemeChoice.SpotifyStyle => "spotify-style",
        _ => "",
    };

    private static string Stylesheet(ThemeChoice theme)
    {
        var name = StylesheetName(theme);
        // The system title bar sits above the page here, so the page needs no
        // room for window controls (macOS sets --ytm-host-titlebar-left).
        return name.Length == 0 ? "" : Resources.TryRead($"themes.{name}.css") ?? "";
    }

    private static string CompanionScript(ThemeChoice theme)
    {
        var name = StylesheetName(theme);
        return name.Length == 0 ? "" : Resources.TryRead($"themes.{name}.js") ?? "";
    }

    /// <summary>
    /// JS that installs (or, for empty CSS, removes) a single &lt;style&gt; element
    /// and swaps the theme's companion script; the previous one is cleaned up via
    /// window.__ytmThemeCleanup, which each companion registers. Same as macOS,
    /// plus a frame guard: WebView2 also runs injected scripts in child frames.
    /// </summary>
    private static string Script(string css, string behaviour) => $$"""
        (() => {
          if (window.top !== window) return;
          const css = {{JsonSerializer.Serialize(css)}};
          window.__ytmThemeCleanup?.();
          {{behaviour}}
          const apply = () => {
            let style = document.getElementById('{{StyleElementId}}');
            if (!css) { style?.remove(); return; }
            if (!style) {
              style = document.createElement('style');
              style.id = '{{StyleElementId}}';
            }
            style.textContent = css;
            // Append last so it wins over the site's own stylesheets.
            (document.head || document.documentElement).appendChild(style);
          };
          if (document.documentElement) apply();
          else document.addEventListener('readystatechange', apply, { once: true });
          document.addEventListener('DOMContentLoaded', apply, { once: true });
        })();
        """;
}
