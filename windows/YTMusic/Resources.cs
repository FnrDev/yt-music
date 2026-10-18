using System.IO;
using System.Reflection;

namespace YTMusic;

/// <summary>Reads the shared page-side files embedded from ../../shared (see YTMusic.csproj).</summary>
internal static class Resources
{
    public static string Read(string logicalName)
    {
        using var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(logicalName)
            ?? throw new InvalidOperationException($"Embedded resource {logicalName} is missing");
        using var reader = new StreamReader(stream);
        return reader.ReadToEnd();
    }

    public static string? TryRead(string logicalName)
    {
        try
        {
            return Read(logicalName);
        }
        catch (InvalidOperationException)
        {
            return null;
        }
    }
}
