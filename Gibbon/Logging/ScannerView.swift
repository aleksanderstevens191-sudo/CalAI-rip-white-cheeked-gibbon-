import SwiftUI
import SwiftData
import PhotosUI

struct ScannerView: View {
    @State var mode: ScanMode
    @StateObject private var camera = CameraController()
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var analysis: AnalysisManager

    @State private var pickerItem: PhotosPickerItem?
    @State private var lookingUp = false
    @State private var message: String?
    @State private var manualCode = ""
    @State private var showManualCode = false
    @State private var note = ""
    @State private var showNote = false
    @State private var showTips = false
    /// Product found by barcode/QR, waiting for the quick-add card. Not saved until you tap Log.
    @State private var quickAdd: SnackDraft?
    /// False once the scanner has closed, so a lookup that finishes late doesn't show anything.
    @State private var active = true
    /// Set after the first photo is handled, so a double tap on the shutter can't log (and pay for) two scans.
    @State private var photoHandled = false
    /// A scanned product code the database didn't know; attached to the next label scan so it's remembered.
    @State private var pendingBarcode: String?
    @State private var offerLabelScan = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch camera.state {
            case .running, .idle:
                CameraPreview(session: camera.session).ignoresSafeArea()
            case .unavailable(let reason):
                VStack(spacing: 14) {
                    Image(systemName: "camera.fill").font(.largeTitle)
                    Text(reason).multilineTextAlignment(.center).padding(.horizontal, 40)
                }
                .foregroundStyle(.white.opacity(0.8))
            }

            frameOverlay

            VStack {
                topBar
                Spacer()
                if let message {
                    VStack(spacing: 10) {
                        Text(message)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                        if offerLabelScan {
                            Button {
                                Haptics.tap()
                                mode = .label
                            } label: {
                                Label("Scan the nutrition label", systemImage: "doc.text.viewfinder")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.black)
                                    .padding(.horizontal, 14).padding(.vertical, 9)
                                    .background(.white, in: Capsule())
                            }
                        }
                    }
                    .padding(14)
                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 24)
                    .onTapGesture { self.message = nil }
                } else if mode == .label, pendingBarcode != nil {
                    Label("This label will be remembered for barcode \(pendingBarcode ?? "")", systemImage: "barcode")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.black.opacity(0.6), in: Capsule())
                }
                if lookingUp {
                    ProgressView("Looking up product…")
                        .tint(.white)
                        .foregroundStyle(.white)
                        .padding(14)
                        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
                }
                bottomControls
            }
        }
        .statusBarHidden()
        .onAppear(perform: setup)
        .onDisappear {
            active = false
            camera.stop()
        }
        .onChange(of: mode) { _, new in
            camera.detectBarcodes = new == .barcode
            camera.resetBarcode()
            message = nil
            offerLabelScan = false
            if new == .food { pendingBarcode = nil }
        }
        .sheet(item: $quickAdd) { draft in
            QuickAddSheet(draft: draft, date: app.logTimestamp) { entry, openDetails in
                quickAdd = nil
                guard let entry else { return }
                if openDetails {
                    app.tab = .home
                    app.present(.foodDetail(entry))
                } else {
                    // Stay in the scanner, ready for the next snack.
                    app.showToast("\(entry.name) logged")
                }
            }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                // Clear the selection so picking the same photo again still triggers.
                defer { pickerItem = nil }
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                    handle(img)
                }
            }
        }
        .alert("Enter barcode", isPresented: $showManualCode) {
            TextField("Barcode number", text: $manualCode).keyboardType(.numberPad)
            Button("Look up") {
                let code = manualCode
                manualCode = ""
                Task { await lookup(code) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Add a note for the AI", isPresented: $showNote) {
            TextField("e.g. cooked in butter, large portion", text: $note)
            Button("Done") {}
        } message: {
            Text("Optional details make the estimate more accurate. The note is used for the next photo you take.")
        }
        .sheet(isPresented: $showTips) { ScanTipsSheet() }
    }

    // MARK: Pieces

    private var topBar: some View {
        HStack {
            circleButton("xmark") { app.scanner = nil }
            Spacer()
            Text(mode == .barcode ? "Barcode or QR code" : (mode == .label ? "Scan a nutrition label" : "Scanner"))
                .font(.headline).foregroundStyle(.white)
            Spacer()
            circleButton("questionmark") { showTips = true }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var frameOverlay: some View {
        GeometryReader { geo in
            let w = geo.size.width * (mode == .barcode ? 0.82 : 0.78)
            let h = mode == .barcode ? w * 0.5 : (mode == .label ? w * 1.25 : w)
            CornerBrackets()
                .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .frame(width: w, height: h)
                .position(x: geo.size.width / 2, y: geo.size.height * 0.42)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: mode)
        }
        .allowsHitTesting(false)
    }

    private var bottomControls: some View {
        VStack(spacing: 22) {
            HStack(spacing: 10) {
                ForEach(ScanMode.allCases) { m in
                    modeButton(m.title, m.icon, selected: mode == m) { mode = m }
                }
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    modeTile("Library", "photo.on.rectangle", selected: false)
                }
            }
            .padding(.horizontal, 16)
            HStack {
                circleButton(camera.torchOn ? "bolt.fill" : "bolt.slash.fill", size: 50) { camera.toggleTorch() }
                Spacer()
                if mode == .barcode {
                    Button { showManualCode = true } label: {
                        Text("Type code")
                            .font(.headline)
                            .foregroundStyle(.black)
                            .frame(width: 120, height: 56)
                            .background(.white, in: Capsule())
                    }
                } else {
                    Button { Haptics.tap(); camera.capture() } label: {
                        ZStack {
                            Circle().stroke(.white, lineWidth: 4).frame(width: 78, height: 78)
                            Circle().fill(.white).frame(width: 64, height: 64)
                        }
                    }
                    .disabled(camera.state != .running)
                    .accessibilityLabel("Take photo")
                }
                Spacer()
                circleButton(note.isEmpty ? "text.bubble" : "text.bubble.fill", size: 50) { showNote = true }
                    .opacity(mode == .food ? 1 : 0)
                    .disabled(mode != .food)
            }
            .padding(.horizontal, 28)
        }
        .padding(.bottom, 24)
    }

    private func modeButton(_ title: String, _ icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: { Haptics.tap(); action() }) { modeTile(title, icon, selected: selected) }
            .buttonStyle(.plain)
    }

    private func modeTile(_ title: String, _ icon: String, selected: Bool) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 18, weight: .medium))
            Text(title).font(.system(size: 11, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(selected ? .black : .white)
        .frame(maxWidth: .infinity)
        .frame(height: 62)
        .background(selected ? Color.white : Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func circleButton(_ icon: String, size: CGFloat = 40, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(.white.opacity(0.18), in: Circle())
        }
    }

    // MARK: Actions

    private func setup() {
        camera.detectBarcodes = mode == .barcode
        camera.onPhoto = { handle($0) }
        camera.onBarcode = { code, isUPCE in Task { await lookup(code, isUPCE: isUPCE) } }
        camera.start()
    }

    private func handle(_ image: UIImage) {
        guard mode != .barcode else {
            // A picked photo or screenshot: read any barcode / QR code in it.
            Task {
                if let found = await BarcodeReader.firstCode(in: image) {
                    await lookup(found.payload, isUPCE: found.isUPCE)
                } else {
                    message = "No barcode or QR code found in that photo."
                }
            }
            return
        }
        guard !photoHandled, let data = image.jpegForStorage() else { return }
        photoHandled = true
        camera.onPhoto = nil
        let isLabel = mode == .label
        let entry = FoodEntry(date: app.logTimestamp, name: isLabel ? "Nutrition label" : "Meal",
                              source: isLabel ? .label : .photo,
                              meal: isLabel ? .snack : nil, status: .analyzing)
        entry.imageData = data
        entry.userHint = note
        if isLabel, let code = pendingBarcode {
            // Remember this product: the next scan of the same barcode reuses this label, free and instant.
            entry.barcode = code
            pendingBarcode = nil
        }
        context.insert(entry)
        try? context.save()
        analysis.run(entry, kind: isLabel ? .label : .photo, context: context)
        app.tab = .home
        app.scanner = nil
    }

    private func lookup(_ raw: String, isUPCE: Bool = false) async {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard active, !trimmed.isEmpty, !lookingUp, quickAdd == nil else { return }
        offerLabelScan = false
        guard let code = ProductCode.gtin(from: trimmed, isUPCE: isUPCE) else {
            message = "That code doesn't contain a product number. Snap the nutrition label instead."
            offerLabelScan = true
            return
        }
        message = nil
        // A label is only remembered for the product you scanned right before it.
        if pendingBarcode != code { pendingBarcode = nil }

        // 1. A product you've logged or saved before: rebuild it from the values first read for it.
        if let known = rememberedEntry(for: code), let draft = SnackDraft(remembered: known) {
            pendingBarcode = nil
            quickAdd = draft
            return
        }

        lookingUp = true
        defer { lookingUp = false }

        // 2. USDA Branded Foods: manufacturer-supplied data, the most reliable source for US products.
        if let branded = await USDA.branded(barcode: code) {
            guard active, quickAdd == nil else { return }
            pendingBarcode = nil
            quickAdd = SnackDraft(usda: branded)
            return
        }

        // 3. Open Food Facts: free community database with wide international coverage.
        do {
            let product = try await OpenFoodFacts.product(barcode: code)
            guard active, quickAdd == nil else { return }
            if let product {
                pendingBarcode = nil
                var draft = SnackDraft(product: product)
                draft.barcode = code
                quickAdd = draft
            } else {
                // 4. Unknown product: read the label once, and it's remembered for next time.
                pendingBarcode = code
                message = "Product \(code) isn't in the food database yet. Snap its nutrition label once and it'll be remembered."
                offerLabelScan = true
            }
        } catch {
            guard active else { return }
            message = "Lookup failed: \(error.localizedDescription)"
        }
    }

    /// Most recent entry with this product code that still has the values it was first logged with.
    private func rememberedEntry(for code: String) -> FoodEntry? {
        let target: String? = code
        var descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.barcode == target },
            sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 20
        let matches = (try? context.fetch(descriptor)) ?? []
        return matches.first { $0.status == .ready && $0.productSnapshot != nil }
    }
}

private struct CornerBrackets: Shape {
    func path(in r: CGRect) -> Path {
        let l: CGFloat = min(r.width, r.height) * 0.16
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + l)); p.addLine(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.minX + l, y: r.minY))
        p.move(to: CGPoint(x: r.maxX - l, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY + l))
        p.move(to: CGPoint(x: r.maxX, y: r.maxY - l)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.maxX - l, y: r.maxY))
        p.move(to: CGPoint(x: r.minX + l, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY - l))
        return p
    }
}

private struct ScanTipsSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SheetHeader(title: "Best scanning practices") { dismiss() }
            tip("camera.metering.center.weighted", "Fill the frame", "Get the whole plate in view, shot from a 45° angle so depth is visible.")
            tip("hand.raised.fill", "Include a size reference", "A fork, hand or standard plate next to the food makes portion estimates far more accurate.")
            tip("sun.max.fill", "Use good light", "Avoid harsh shadows and dark rooms. Turn on the flash if needed.")
            tip("text.bubble.fill", "Add a note", "Tell the AI anything hidden: \"fried in butter\", \"extra cheese\", \"half eaten\".")
            tip("square.split.2x1.fill", "One meal per photo", "Scan side dishes separately if they're on different plates.")
            Spacer()
        }
        .padding(.horizontal, 20)
        .presentationDetents([.medium, .large])
    }
    private func tip(_ icon: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            IconBadge(systemName: icon)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(body).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
