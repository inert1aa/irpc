import Foundation
import MediaPlayer
import UIKit
import CryptoKit

/// Uploads only embedded cover art, never audio or track metadata.
/// Anonymous Catbox uploads are public and cannot be deleted by the uploader.
actor AnonymousArtworkUploader {
    static let shared = AnonymousArtworkUploader()
    private var inFlight: Set<String> = []

    func artworkURL(for title: String, artist: String) async -> URL? {
        let player = await MainActor.run { MPMusicPlayerController.systemMusicPlayer }
        let item = await MainActor.run { player.nowPlayingItem }
        guard item?.title == title, item?.artist == artist,
              let image = item?.artwork?.image(at: CGSize(width: 1024, height: 1024)),
              let data = image.jpegData(compressionQuality: 0.88) else { return nil }

        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let key = "artwork.catbox." + digest
        if let cached = UserDefaults.standard.string(forKey: key),
           let url = URL(string: cached), url.scheme == "https" { return url }
        guard !inFlight.contains(digest) else { return nil }
        inFlight.insert(digest)
        defer { inFlight.remove(digest) }

        guard let endpoint = URL(string: "https://catbox.moe/user/api.php") else { return nil }
        let boundary = UUID().uuidString
        var body = Data()
        func append(_ string: String) { body.append(Data(string.utf8)) }
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"reqtype\"\r\n\r\nfileupload\r\n")
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"fileToUpload\"; filename=\"cover.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n")
        body.append(data)
        append("\r\n--\(boundary)--\r\n")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 25
        do {
            let (response, result) = try await URLSession.shared.data(for: request)
            guard (result as? HTTPURLResponse)?.statusCode == 200,
                  let value = String(data: response, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let url = URL(string: value), url.scheme == "https",
                  url.host == "files.catbox.moe" else { return nil }
            UserDefaults.standard.set(url.absoluteString, forKey: key)
            return url
        } catch { return nil }
    }
}
