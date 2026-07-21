import SwiftUI
import UIKit

struct GameAssetImage: View {
    let path: String
    var fallbackSystemName: String = "photo"
    var contentMode: ContentMode = .fit

    var body: some View {
        Group {
            if let image = GameAssetLibrary.image(for: path) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Image(systemName: fallbackSystemName)
                    .resizable()
                    .scaledToFit()
                    .padding(8)
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
        .accessibilityHidden(true)
    }
}

private enum GameAssetLibrary {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(for sourcePath: String) -> UIImage? {
        guard !sourcePath.isEmpty else { return nil }
        let normalized = sourcePath.replacingOccurrences(of: "\\", with: "/")
        let pngPath = (normalized as NSString).deletingPathExtension + ".png"
        let cacheKey = pngPath as NSString

        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        guard let url = locate(pngPath), let image = UIImage(contentsOfFile: url.path) else {
            return nil
        }
        cache.setObject(image, forKey: cacheKey)
        return image
    }

    private static func locate(_ normalizedPath: String) -> URL? {
        if let current = ContentUpdateStorage.currentURL {
            let override = current.appendingPathComponent(normalizedPath)
            if FileManager.default.fileExists(atPath: override.path) {
                return override
            }
        }

        let path = normalizedPath as NSString
        let name = path.lastPathComponent.replacingOccurrences(of: ".png", with: "")
        let folder = path.deletingLastPathComponent
        let locations = [
            Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "GameContent/\(folder)"),
            Bundle.main.url(forResource: name, withExtension: "png", subdirectory: folder),
            Bundle.main.url(forResource: name, withExtension: "png")
        ]
        return locations.compactMap { $0 }.first
    }
}
