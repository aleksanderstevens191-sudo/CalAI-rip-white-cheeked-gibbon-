import SwiftUI
import UIKit

struct RingView<Center: View>: View {
    var progress: Double
    var color: Color
    var lineWidth: CGFloat = 8
    var dashed: Bool = false
    @ViewBuilder var center: () -> Center

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.track, style: StrokeStyle(lineWidth: lineWidth, dash: dashed ? [3, 4] : []))
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.7, dampingFraction: 0.85), value: progress)
            center()
        }
    }
}

extension RingView where Center == EmptyView {
    init(progress: Double, color: Color, lineWidth: CGFloat = 8, dashed: Bool = false) {
        self.init(progress: progress, color: color, lineWidth: lineWidth, dashed: dashed) { EmptyView() }
    }
}

struct NutrientIcon: View {
    let kind: NutrientKind
    var size: CGFloat = 14
    var body: some View {
        Image(systemName: kind.icon)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(kind.color)
    }
}

struct IconBadge: View {
    let systemName: String
    var color: Color = Theme.ink
    var size: CGFloat = 36
    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}

struct ProgressBar: View {
    var value: Double
    var color: Color = Theme.ink
    var height: CGFloat = 8
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule().fill(color)
                    .frame(width: max(height, geo.size.width * min(max(value, 0), 1)))
                    .opacity(value <= 0 ? 0 : 1)
            }
        }
        .frame(height: height)
        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: value)
    }
}

struct EmptyStateView: View {
    var icon: String = "chart.bar.xaxis"
    var title: String = "No data to show"
    var message: String = "This will update as you log more food."
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .background(Theme.cardMuted, in: Circle())
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

/// A grouped list of rows inside a white card, used across settings screens.
struct SettingsGroup<Content: View>: View {
    var title: String?
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
            VStack(spacing: 0) { content() }
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                .shadow(color: .black.opacity(0.04), radius: 10, y: 3)
        }
    }
}

struct SettingsRow: View {
    let icon: String
    let title: String
    var detail: String? = nil
    var tint: Color = Theme.ink
    var showsChevron = true
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 24)
            Text(title).foregroundStyle(tint == Theme.ink ? Theme.ink : tint)
            Spacer(minLength: 8)
            if let detail {
                Text(detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 54)
        .contentShape(Rectangle())
    }
}

struct RowDivider: View {
    var body: some View { Divider().padding(.leading, 54) }
}

struct SectionTitle: View {
    let text: String
    var trailing: AnyView? = nil
    var body: some View {
        HStack {
            Text(text).font(.title3.weight(.semibold))
            Spacer()
            trailing
        }
    }
}

struct FoodThumbnail: View {
    let data: Data?
    var source: EntrySource
    var size: CGFloat = 84
    var body: some View {
        Group {
            if let data, let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                ZStack {
                    Theme.cardMuted
                    Image(systemName: source.icon)
                        .font(.system(size: size * 0.3, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

struct SheetHeader: View {
    let title: String
    var onClose: (() -> Void)?
    var body: some View {
        ZStack {
            Text(title).font(.headline)
            if let onClose {
                HStack {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 34, height: 34)
                            .background(Theme.cardMuted, in: Circle())
                    }
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 8)
    }
}

struct ChoiceRow: View {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    let selected: Bool
    var body: some View {
        HStack(spacing: 14) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(selected ? Color.white.opacity(0.15) : Theme.card, in: Circle())
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let subtitle {
                    Text(subtitle).font(.subheadline).opacity(0.7)
                }
            }
            Spacer()
        }
        .foregroundStyle(selected ? Theme.inkInverse : Theme.ink)
        .padding(.horizontal, 18)
        .padding(.vertical, subtitle == nil ? 18 : 14)
        .background(selected ? Theme.ink : Theme.cardMuted, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(Rectangle())
    }
}

/// Number keypad-friendly field that edits a Double.
struct DecimalField: View {
    let title: String
    @Binding var value: Double
    var decimals: Int = 1
    var suffix: String? = nil
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 4) {
            TextField(title, text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused($focused)
                .onAppear { text = Fmt.number(value, decimals: decimals) }
                .onChange(of: text) { _, new in
                    // Only user typing writes back; programmatic formatting must not round stored values.
                    guard focused else { return }
                    if let v = Double(new.replacingOccurrences(of: ",", with: ".")) { value = v }
                    else if new.isEmpty { value = 0 }
                }
                .onChange(of: value) { _, new in
                    if !focused { text = Fmt.number(new, decimals: decimals) }
                }
            if let suffix { Text(suffix).foregroundStyle(.secondary) }
        }
    }
}

struct Toast: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.inkInverse)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Theme.ink, in: Capsule())
            .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
    }
}
