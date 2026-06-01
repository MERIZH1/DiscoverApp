import WidgetKit
import SwiftUI
import ActivityKit

@main
struct DiscoverWidgetBundle: WidgetBundle {
    var body: some Widget {
        DiscoverHomeWidget()
        NowPlayingLiveActivity()
    }
}

// MARK: - Home-Screen-Widget (Branding + oeffnet die App)
struct DiscoverEntry: TimelineEntry { let date: Date }

struct DiscoverProvider: TimelineProvider {
    func placeholder(in context: Context) -> DiscoverEntry { DiscoverEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (DiscoverEntry) -> Void) {
        completion(DiscoverEntry(date: Date()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<DiscoverEntry>) -> Void) {
        completion(Timeline(entries: [DiscoverEntry(date: Date())], policy: .never))
    }
}

struct DiscoverHomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DiscoverHomeWidget", provider: DiscoverProvider()) { _ in
            DiscoverHomeWidgetView()
        }
        .configurationDisplayName("Discover")
        .description("Discover oeffnen")
        .supportedFamilies([.systemSmall])
    }
}

struct DiscoverHomeWidgetView: View {
    private let bg = Color(red: 0.07, green: 0.07, blue: 0.07)
    var body: some View {
        let content = VStack(spacing: 8) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 44)).foregroundColor(Color(red: 0.12, green: 0.84, blue: 0.38))
            Text("Discover").font(.system(size: 15, weight: .bold)).foregroundColor(.white)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
        if #available(iOS 17.0, *) {
            content.containerBackground(bg, for: .widget)
        } else {
            ZStack { bg; content }
        }
    }
}

// MARK: - Live Activity / Dynamic Island
struct NowPlayingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NowPlayingAttributes.self) { context in
            // Lock-Screen / Banner
            HStack(spacing: 12) {
                Image(systemName: "music.note")
                    .font(.title2).foregroundColor(Color(red: 0.12, green: 0.84, blue: 0.38))
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.title).font(.headline).lineLimit(1)
                    Text(context.state.artist).font(.subheadline).foregroundColor(.secondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill").font(.title3)
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.85))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "music.note").foregroundColor(Color(red: 0.12, green: 0.84, blue: 0.38))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.title).font(.headline).lineLimit(1)
                        Text(context.state.artist).font(.caption).foregroundColor(.secondary).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: "music.note").foregroundColor(Color(red: 0.12, green: 0.84, blue: 0.38))
            } compactTrailing: {
                Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
            } minimal: {
                Image(systemName: "music.note").foregroundColor(Color(red: 0.12, green: 0.84, blue: 0.38))
            }
        }
    }
}
