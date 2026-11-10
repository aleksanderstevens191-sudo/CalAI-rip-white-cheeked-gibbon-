import SwiftUI
import SwiftData

struct MainView: View {
    @Bindable var profile: Profile
    @EnvironmentObject private var app: AppState
    @State private var showAddMenu = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch app.tab {
                case .home: HomeView(profile: profile)
                case .progress: ProgressTab(profile: profile)
                case .profile: ProfileTab(profile: profile)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showAddMenu {
                AddMenuOverlay(isPresented: $showAddMenu)
                    .transition(.opacity)
            }

            TabBar(showAddMenu: $showAddMenu)

            if let toast = app.toast {
                Toast(text: toast)
                    .padding(.bottom, 100)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .ignoresSafeArea(.keyboard)
        .sheet(item: $app.sheet) { route in
            sheetContent(route)
        }
        .fullScreenCover(item: $app.scanner) { mode in
            ScannerView(mode: mode)
        }
    }

    @ViewBuilder
    private func sheetContent(_ route: SheetRoute) -> some View {
        switch route {
        case .foodDetail(let entry): FoodDetailView(entry: entry, profile: profile)
        case .water: WaterSheet(profile: profile)
        case .weight: LogWeightSheet(profile: profile)
        case .exercise: ExerciseSheet(profile: profile)
        case .describe: DescribeFoodSheet()
        case .search: FoodSearchSheet()
        case .saved: SavedFoodsSheet()
        case .streak: StreakSheet()
        case .badges: BadgesSheet(profile: profile)
        }
    }
}

private struct TabBar: View {
    @EnvironmentObject private var app: AppState
    @Binding var showAddMenu: Bool

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                tab(.home, "Home", "house.fill")
                tab(.progress, "Progress", "chart.bar.fill")
                tab(.profile, "Profile", "person.fill")
            }
            .padding(6)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(Theme.border.opacity(0.6), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.08), radius: 16, y: 6)

            Button {
                Haptics.tap()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showAddMenu.toggle() }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Theme.inkInverse)
                    .rotationEffect(.degrees(showAddMenu ? 45 : 0))
                    .frame(width: 62, height: 62)
                    .background(Theme.ink, in: Circle())
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(showAddMenu ? "Close menu" : "Add")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    private func tab(_ t: MainTab, _ title: String, _ icon: String) -> some View {
        let selected = app.tab == t
        return Button {
            Haptics.tap()
            showAddMenu = false
            app.tab = t
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 17, weight: .semibold))
                Text(title).font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(selected ? Theme.ink : .secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(selected ? Theme.cardMuted : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct AddMenuOverlay: View {
    @EnvironmentObject private var app: AppState
    @Binding var isPresented: Bool

    private struct Action: Identifiable {
        let id: String
        let title: String
        let icon: String
        let run: (AppState) -> Void
    }

    private let actions: [Action] = [
        Action(id: "scan", title: "Scan food", icon: "camera.viewfinder") { $0.openScanner(.food) },
        Action(id: "barcode", title: "Barcode / QR", icon: "qrcode.viewfinder") { $0.openScanner(.barcode) },
        Action(id: "label", title: "Food label", icon: "doc.text.viewfinder") { $0.openScanner(.label) },
        Action(id: "describe", title: "Describe food", icon: "text.bubble") { $0.present(.describe) },
        Action(id: "search", title: "Food database", icon: "magnifyingglass") { $0.present(.search) },
        Action(id: "saved", title: "Saved foods", icon: "bookmark") { $0.present(.saved) },
        Action(id: "exercise", title: "Log exercise", icon: "figure.run") { $0.present(.exercise) },
        Action(id: "water", title: "Log water", icon: "drop") { $0.present(.water) },
        Action(id: "weight", title: "Log weight", icon: "scalemass") { $0.present(.weight) },
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { close() }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                ForEach(actions) { action in
                    Button {
                        Haptics.tap()
                        close()
                        action.run(app)
                    } label: {
                        VStack(spacing: 10) {
                            Image(systemName: action.icon)
                                .font(.system(size: 24, weight: .medium))
                            Text(action.title)
                                .font(.footnote.weight(.semibold))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                        }
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 100)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 90)
        }
    }

    private func close() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { isPresented = false }
    }
}
