import Foundation
import MediaPlayer
import UIKit
import CryptoKit

/// Reads the exact cover from the Music player, then uploads only the JPEG.
/// Anonymous uploads are public; no audio, artist or title is transmitted.
actor AnonymousArtworkUploader {
    static let shared = AnonymousArtworkUploader()
    private var uploads: [String: Task<URL?, Never>] = [:]
    private var retryAfter: [String: Date] = [:]
    private let endpoint = URL(string: "https://catbox.moe/user/api.php")!

    func artworkURL(for title: String, artist: String) async -> URL? {
        // Fetch and compress on the main actor to avoid UIKit thread issues.
        let jpeg: Data? = await MainActor.run {
            let item = MPMusicPlayerController.systemMusicPlayer.nowPlayingItem
            guard item?.title == title, item?.artist == artist,
                  let image = item?.artwork?.image(at: CGSize(width: 768, height: 768)) else { return nil }
            return image.jpegData(compressionQuality: 0.82)
        }
        guard let jpeg else { return nil }
        let hash = SHA256.hash(data: jpeg).map { String(format: "%02x", $0) }.joined()
        let cacheKey = "artwork.catbox." + hash
        if let stored = UserDefaults.standard.string(forKey: cacheKey),
           let url = URL(string: stored), url.scheme == "https",
           url.host == "files.catbox.moe" { return url }
        if let existing = uploads[hash] { return await existing.value }
        if let next = retryAfter[hash], next > Date() { return nil }

        let endpoint = self.endpoint
        let task = Task<URL?, Never> {
            let boundary = UUID().uuidString
            var body = Data()
            func add(_ value: String) { body.append(contentsOf: value.utf8) }
            add("--\(boundary)\r\nContent-Disposition: form-data; name=\"reqtype\"\r\n\r\nfileupload\r\n")
            add("--\(boundary)\r\nContent-Disposition: form-data; name=\"fileToUpload\"; filename=\"cover.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n")
            body.append(jpeg)
            add("\r\n--\(boundary)--\r\n")
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
            request.timeoutInterval = 15
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                      let string = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      let url = URL(string: string),
                      url.scheme == "https", url.host == "files.catbox.moe" else { return nil }
                return url
            } catch { return nil }
        }
        uploads[hash] = task
        let url = await task.value
        uploads[hash] = nil
        if let url {
            UserDefaults.standard.set(url.absoluteString, forKey: cacheKey)
            retryAfter[hash] = nil
        } else {
            retryAfter[hash] = Date().addingTimeInterval(60)
        }
        return url
    }
}
