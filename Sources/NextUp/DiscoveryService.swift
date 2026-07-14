import Foundation
import AppKit
import CoreImage

struct TVMazeImage: Codable, Hashable {
    var medium: String?
    var original: String?
}

struct TVMazeShow: Codable, Identifiable, Hashable {
    var id: Int
    var url: String?
    var name: String
    var status: String?
    var premiered: String?
    var summary: String?
    var image: TVMazeImage?

    var plainSummary: String {
        (summary ?? "No description available.")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }
}

struct TVMazeSearchResult: Codable {
    var score: Double
    var show: TVMazeShow
}

struct TVMazeEpisode: Codable, Identifiable, Hashable {
    var id: Int
    var name: String
    var season: Int?
    var number: Int?
    var airdate: String?
    var runtime: Int?
}

@MainActor
final class DiscoveryModel: ObservableObject {
    @Published var results: [TVMazeShow] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func search(_ query: String) async {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            var components = URLComponents(string: "https://api.tvmaze.com/search/shows")!
            components.queryItems = [URLQueryItem(name: "q", value: clean)]
            let (data, response) = try await URLSession.shared.data(from: components.url!)
            try validate(response)
            results = try JSONDecoder().decode([TVMazeSearchResult].self, from: data).map(\.show)
        } catch {
            errorMessage = "Couldn't search TVmaze: \(error.localizedDescription)"
        }
    }

    func episodes(for show: TVMazeShow) async throws -> [TVMazeEpisode] {
        let url = URL(string: "https://api.tvmaze.com/shows/\(show.id)/episodes?specials=1")!
        let (data, response) = try await URLSession.shared.data(from: url)
        try validate(response)
        return try JSONDecoder().decode([TVMazeEpisode].self, from: data)
    }

    func show(id: String) async throws -> TVMazeShow {
        let url = URL(string: "https://api.tvmaze.com/shows/\(id)")!
        let (data, response) = try await URLSession.shared.data(from: url)
        try validate(response)
        return try JSONDecoder().decode(TVMazeShow.self, from: data)
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}

enum ArtworkPalette {
    static func accentHex(from urlString: String, fallbackSeed: String) async -> String? {
        guard let url = URL(string: urlString) else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let image = CIImage(data: data), !image.extent.isEmpty,
                  let filter = CIFilter(name: "CIAreaAverage", parameters: [
                    kCIInputImageKey: image,
                    kCIInputExtentKey: CIVector(cgRect: image.extent)
                  ]), let output = filter.outputImage else { return fallbackAccent(for: fallbackSeed) }

            var pixel = [UInt8](repeating: 0, count: 4)
            CIContext().render(
                output,
                toBitmap: &pixel,
                rowBytes: 4,
                bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                format: .RGBA8,
                colorSpace: CGColorSpaceCreateDeviceRGB()
            )
            let color = NSColor(
                red: CGFloat(pixel[0]) / 255,
                green: CGFloat(pixel[1]) / 255,
                blue: CGFloat(pixel[2]) / 255,
                alpha: 1
            )
            var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
            color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
            if saturation < 0.16 { return fallbackAccent(for: fallbackSeed) }
            let vivid = NSColor(
                hue: hue,
                saturation: min(0.92, max(0.58, saturation * 1.25)),
                brightness: min(0.94, max(0.72, brightness * 1.35)),
                alpha: 1
            )
            return hex(vivid)
        } catch {
            return fallbackAccent(for: fallbackSeed)
        }
    }

    static func fallbackAccent(for seed: String) -> String {
        let palette = ["7C5CFC", "00B8A9", "E05D87", "F4A340", "3D8BFF", "9B6DFF", "E0673F", "43B581"]
        let value = seed.unicodeScalars.reduce(0) { (($0 &* 31) &+ Int($1.value)) & 0x7fffffff }
        return palette[value % palette.count]
    }

    private static func hex(_ color: NSColor) -> String {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return "6C63FF" }
        return String(format: "%02X%02X%02X", Int(rgb.redComponent * 255), Int(rgb.greenComponent * 255), Int(rgb.blueComponent * 255))
    }
}
