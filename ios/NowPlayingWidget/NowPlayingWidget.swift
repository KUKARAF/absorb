import AbsorbPlayerCore
import AppIntents
import WidgetKit
import SwiftUI
import AVFAudio

private let appGroup = "group.com.barnabas.absorb"

// Deep-link URL used only by the play button when no session is loaded, so
// the app launches and can cold-resume the last-played item. Must use the
// registered URL scheme (audiobookshelf://) and include ?homeWidget so the
// home_widget Flutter plugin intercepts the URL on launch.
private let playPauseURL = URL(string: "audiobookshelf://widget/play_pause?homeWidget")!

// Intents (AbsorbPlayPauseIntent / AbsorbSkipBackIntent /
// AbsorbSkipForwardIntent) live in the AbsorbPlayerCore Swift package so
// both Runner and this extension see the same Swift type. Without that,
// AppDependencyManager registrations made in Runner's AppDelegate can't
// resolve in widget-process intent invocations, the @Dependency throws,
// and only the optimistic UI flip in perform() takes effect.

// MARK: - Entry

struct NowPlayingEntry: TimelineEntry {
    let date: Date
    let hasBook: Bool
    let title: String
    let author: String
    let isPlaying: Bool
    let progress: Double
    let coverImage: UIImage?
    let skipBack: Int
    let skipForward: Int
}

// MARK: - Provider

struct NowPlayingProvider: TimelineProvider {
    func placeholder(in context: Context) -> NowPlayingEntry {
        NowPlayingEntry(
            date: .now, hasBook: true, title: "Audiobook Title",
            author: "Author Name", isPlaying: false, progress: 0.35,
            coverImage: nil, skipBack: 10, skipForward: 30
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (NowPlayingEntry) -> Void) {
        completion(readEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingEntry>) -> Void) {
        let refreshDate = Date().addingTimeInterval(300)
        completion(Timeline(entries: [readEntry()], policy: .after(refreshDate)))
    }

    private func readEntry() -> NowPlayingEntry {
        let d = UserDefaults(suiteName: appGroup)
        if d == nil {
            NSLog("[WidgetDebug] readEntry: UserDefaults(suiteName:%@) returned nil - app group not accessible from extension", appGroup)
        }
        let hasBook = d?.bool(forKey: "widget_has_book") ?? false
        let title = d?.string(forKey: "widget_title") ?? ""
        let author = d?.string(forKey: "widget_author") ?? ""
        let isPlaying = d?.bool(forKey: "widget_is_playing") ?? false
        let progress = Double(d?.integer(forKey: "widget_progress") ?? 0) / 1000.0
        let skipBack = d?.integer(forKey: "widget_skip_back") ?? 0
        let skipForward = d?.integer(forKey: "widget_skip_forward") ?? 0
        let coverPath = d?.string(forKey: "widget_cover_path") ?? ""

        var cover: UIImage? = nil
        var coverStatus = "empty"
        if !coverPath.isEmpty {
            let exists = FileManager.default.fileExists(atPath: coverPath)
            if !exists {
                coverStatus = "path_missing"
            } else {
                cover = UIImage(contentsOfFile: coverPath)
                coverStatus = cover == nil ? "decode_failed" : "ok"
            }
        }

        NSLog("[WidgetDebug] readEntry: hasBook=%@ title=\"%@\" isPlaying=%@ progress=%.3f coverPath=\"%@\" coverStatus=%@",
              hasBook ? "true" : "false",
              title,
              isPlaying ? "true" : "false",
              progress,
              coverPath,
              coverStatus)

        return NowPlayingEntry(
            date: .now,
            hasBook: hasBook,
            title: title.isEmpty ? "Absorb" : title,
            author: author.isEmpty ? (hasBook ? "" : "Not playing") : author,
            isPlaying: isPlaying,
            progress: progress,
            coverImage: cover,
            skipBack: skipBack > 0 ? skipBack : 10,
            skipForward: skipForward > 0 ? skipForward : 30
        )
    }
}

// MARK: - Cover Art

struct CoverArtView: View {
    let image: UIImage?
    let cornerRadius: CGFloat

    var body: some View {
        if let image = image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.quaternary)
                .overlay {
                    Image(systemName: "book.closed.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
        }
    }
}

// MARK: - Small Widget

struct SmallWidgetView: View {
    let entry: NowPlayingEntry

    var body: some View {
        VStack(spacing: 4) {
            CoverArtView(image: entry.coverImage, cornerRadius: 10)
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)

            Text(entry.title)
                .font(.caption)
                .fontWeight(.semibold)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(entry.author)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 18) {
                Button(intent: AbsorbSkipBackIntent()) {
                    Image(systemName: "backward.fill")
                        .font(.title3)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                if entry.hasBook {
                    Button(intent: AbsorbPlayPauseIntent()) {
                        Image(systemName: entry.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                } else {
                    // No session loaded — tap launches the app so it can
                    // resume the last-played item (AppIntent alone can't
                    // start playback when the app isn't running).
                    Link(destination: playPauseURL) {
                        Image(systemName: "play.fill")
                            .font(.title2)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                }
                Button(intent: AbsorbSkipForwardIntent()) {
                    Image(systemName: "forward.fill")
                        .font(.title3)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Medium Widget

struct MediumWidgetView: View {
    let entry: NowPlayingEntry

    var body: some View {
        HStack(spacing: 12) {
            CoverArtView(image: entry.coverImage, cornerRadius: 12)
                .frame(width: 110, height: 110)

            VStack(alignment: .leading, spacing: 4) {
                Spacer(minLength: 0)

                Text(entry.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(2)

                Text(entry.author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                HStack(spacing: 28) {
                    Button(intent: AbsorbSkipBackIntent()) {
                        Image(systemName: "backward.fill")
                            .font(.title3)
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }

                    if entry.hasBook {
                        Button(intent: AbsorbPlayPauseIntent()) {
                            Image(systemName: entry.isPlaying ? "pause.fill" : "play.fill")
                                .font(.title2)
                                .frame(width: 40, height: 40)
                                .contentShape(Rectangle())
                        }
                    } else {
                        Link(destination: playPauseURL) {
                            Image(systemName: "play.fill")
                                .font(.title2)
                                .frame(width: 40, height: 40)
                                .contentShape(Rectangle())
                        }
                    }

                    Button(intent: AbsorbSkipForwardIntent()) {
                        Image(systemName: "forward.fill")
                            .font(.title3)
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Entry View

struct NowPlayingWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: NowPlayingEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        default:
            MediumWidgetView(entry: entry)
        }
    }
}

// MARK: - Widget

struct AbsorbWidget: Widget {
    let kind = "NowPlayingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NowPlayingProvider()) { entry in
            NowPlayingWidgetView(entry: entry)
        }
        .configurationDisplayName("Now Playing")
        .description("See and control your current audiobook.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Stats Widget

struct StatsEntry: TimelineEntry {
    let date: Date
    let todaySeconds: Int
    let weekSeconds: Int
    let streakDays: Int
    let booksThisYear: Int
}

struct StatsProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatsEntry {
        StatsEntry(date: .now, todaySeconds: 1800, weekSeconds: 14400, streakDays: 12, booksThisYear: 8)
    }

    func getSnapshot(in context: Context, completion: @escaping (StatsEntry) -> Void) {
        completion(readEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatsEntry>) -> Void) {
        // Re-read from the app group every 15 minutes. Flutter also pushes a
        // reloadTimelines via home_widget whenever it ticks the counters
        // forward, so in practice the widget refreshes more often.
        let refreshDate = Date().addingTimeInterval(900)
        completion(Timeline(entries: [readEntry()], policy: .after(refreshDate)))
    }

    private func readEntry() -> StatsEntry {
        let d = UserDefaults(suiteName: appGroup)
        let today = d?.integer(forKey: "widget_stats_today") ?? 0
        let week = d?.integer(forKey: "widget_stats_week") ?? 0
        let streak = d?.integer(forKey: "widget_stats_streak") ?? 0
        let books = d?.integer(forKey: "widget_stats_books_year") ?? 0
        return StatsEntry(
            date: .now,
            todaySeconds: today,
            weekSeconds: week,
            streakDays: streak,
            booksThisYear: books
        )
    }
}

private func formatListeningTime(_ seconds: Int) -> String {
    if seconds <= 0 { return "0m" }
    let hours = seconds / 3600
    let minutes = (seconds % 3600) / 60
    if hours > 0 {
        return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
    }
    return "\(minutes)m"
}

struct StatTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct StatsWidgetView: View {
    let entry: StatsEntry

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                StatTile(value: formatListeningTime(entry.todaySeconds), label: "Today")
                StatTile(value: formatListeningTime(entry.weekSeconds), label: "This week")
            }
            HStack(spacing: 4) {
                StatTile(value: "\(entry.streakDays)", label: "Day streak")
                StatTile(value: "\(entry.booksThisYear)", label: "Books this year")
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct StatsWidget: Widget {
    let kind = "StatsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StatsProvider()) { entry in
            StatsWidgetView(entry: entry)
        }
        .configurationDisplayName("Listening Stats")
        .description("Today, this week, streak, and books finished this year.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Bundle

@main
struct AbsorbWidgetBundle: WidgetBundle {
    var body: some Widget {
        AbsorbWidget()
        StatsWidget()
    }
}
