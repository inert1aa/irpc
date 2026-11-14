import SwiftUI
import MediaPlayer
import UIKit

/// Displays exact embedded artwork supplied by the iOS Music library.
/// Artwork is never replaced with a guessed online image.
struct LocalMusicCard: View {
    @State private var song: MPMediaItem?
    @State private var isPlaying = false

    var body: some View {
        Section("Local Music Library") {
            HStack(spacing: 14) {
                Group {
                    if let image = song?.artwork?.image(at: CGSize(width: 240, height: 240)) {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "music.note")
                            .resizable()
                            .scaledToFit()
                            .padding(24)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 96, height: 96)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 5) {
                    Text(song?.title ?? "No local song detected")
                        .font(.headline)
                        .lineLimit(2)
                    Text(song?.artist ?? "Unknown artist")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let album = song?.albumTitle, !album.isEmpty {
                        Text(album).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Label(isPlaying ? "Playing" : "Paused / unavailable",
                          systemImage: isPlaying ? "play.fill" : "pause.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            Text("Uses artwork stored in your Music library. Discord artwork requires a separately accessible image URL.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: .MPMusicPlayerControllerNowPlayingItemDidChange)) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .MPMusicPlayerControllerPlaybackStateDidChange)) { _ in refresh() }
    }

    private func refresh() {
        let player = MPMusicPlayerController.systemMusicPlayer
        player.beginGeneratingPlaybackNotifications()
        song = player.nowPlayingItem
        isPlaying = player.playbackState == .playing
    }
}
