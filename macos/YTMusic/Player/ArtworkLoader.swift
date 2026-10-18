import AppKit

/// Downloads and caches album art for Now Playing, the menu bar and notifications.
@MainActor
final class ArtworkLoader {
    private let cache = NSCache<NSURL, NSImage>()
    private var inFlight: [URL: Task<NSImage?, Never>] = [:]

    init() {
        cache.countLimit = 32
    }

    func image(for url: URL) async -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        if let task = inFlight[url] { return await task.value }

        let task = Task<NSImage?, Never> {
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return NSImage(data: data)
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image { cache.setObject(image, forKey: url as NSURL) }
        return image
    }

    /// Writes the image to a temp file, for APIs that want a file URL.
    func fileURL(for url: URL) async -> URL? {
        guard let image = await image(for: url),
              let tiff = image.tiffRepresentation,
              let jpeg = NSBitmapImageRep(data: tiff)?.representation(using: .jpeg, properties: [:]) else { return nil }
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")
        do {
            try jpeg.write(to: file)
            return file
        } catch {
            return nil
        }
    }
}
