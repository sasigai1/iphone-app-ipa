import SwiftUI
import UIKit
#if canImport(VLCKitSPM)
import VLCKitSPM
#endif
#if canImport(MobileVLCKit)
import MobileVLCKit
#endif

/// FFmpeg-based fallback player (VLCKit) for files AVPlayer can't open (MKV, DTS, TrueHD, ASS subs…).
enum VLCSupport {
    #if canImport(MobileVLCKit)
    static let available = true
    #else
    static let available = false
    #endif
}

#if canImport(MobileVLCKit)
final class VLCBox: NSObject, ObservableObject, VLCMediaPlayerDelegate {
    let player = VLCMediaPlayer()
    @Published var playing = false
    @Published var position: Float = 0
    @Published var timeText = ""
    @Published var errorText: String?

    func start(_ url: URL, startSeconds: Double) {
        let m = VLCMedia(url: url)
        m.addOption(":network-caching=1500")
        if startSeconds > 1 { m.addOption(":start-time=\(Int(startSeconds))") }
        player.media = m
        player.delegate = self
        player.play()
    }
    var seconds: Double { Double(player.time.intValue) / 1000 }
    func toggle() { player.isPlaying ? player.pause() : player.play() }
    func jump(_ s: Int32) { s > 0 ? player.jumpForward(s) : player.jumpBackward(-s) }
    func stop() { player.stop() }

    func mediaPlayerStateChanged(_ n: Notification) {
        DispatchQueue.main.async {
            self.playing = self.player.isPlaying
            if self.player.state == .error { self.errorText = "VLC 也无法播放（可能是网络或链接失效）" }
        }
    }
    func mediaPlayerTimeChanged(_ n: Notification) {
        DispatchQueue.main.async {
            self.position = self.player.position
            self.timeText = (self.player.time.stringValue ?? "") + " / " + (self.player.media?.length.stringValue ?? "")
        }
    }
}

struct VLCSurface: UIViewRepresentable {
    let box: VLCBox
    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .black
        box.player.drawable = v
        return v
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

struct VLCPlayerView: View {
    let url: URL
    let startSeconds: Double
    var onStop: (Double) -> Void
    @StateObject private var box = VLCBox()
    @State private var showUI = true

    var body: some View {
        ZStack {
            VLCSurface(box: box).ignoresSafeArea()
                .onTapGesture { withAnimation { showUI.toggle() } }
            if let e = box.errorText {
                Text(e).foregroundColor(.white).padding().glassCard(radius: 16)
            }
            if showUI {
                VStack {
                    Spacer()
                    VStack(spacing: 10) {
                        Slider(value: Binding(get: { Double(box.position) }, set: { box.player.position = Float($0) }), in: 0...1)
                        HStack(spacing: 28) {
                            Button { box.jump(-15) } label: { Image(systemName: "gobackward.15") }
                            Button { box.toggle() } label: { Image(systemName: box.playing ? "pause.fill" : "play.fill").font(.title) }
                            Button { box.jump(30) } label: { Image(systemName: "goforward.30") }
                            Spacer()
                            Text(box.timeText).font(.caption.monospacedDigit())
                        }
                        .font(.title2)
                    }
                    .foregroundColor(.white)
                    .padding(16)
                    .glassCard(radius: 22)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
            }
        }
        .onAppear { box.start(url, startSeconds: startSeconds) }
        .onDisappear { let s = box.seconds; box.stop(); onStop(s) }
    }
}
#else
struct VLCPlayerView: View {
    let url: URL
    let startSeconds: Double
    var onStop: (Double) -> Void
    var body: some View { Text("此版本未包含备用播放器").foregroundColor(.white) }
}
#endif
