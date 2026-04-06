import SwiftUI

struct ScannerFlowView: View {
    @EnvironmentObject var documentManager: DocumentManager
    @Environment(\.dismiss) var dismiss

    let sourceType: UIImagePickerController.SourceType

    @State private var pages: [UIImage] = []
    @State private var currentImage: UIImage?
    @State private var step: Step = .camera
    @State private var savedDocument: ScannedDocument?

    enum Step { case camera, crop, review, saved }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch step {
            case .camera:
                ImagePickerView(sourceType: sourceType) { image in
                    currentImage = image
                    step = .crop
                } onCancel: {
                    if pages.isEmpty { dismiss() }
                    else { step = .review }
                }
                .ignoresSafeArea()

            case .crop:
                if let image = currentImage {
                    CropView(image: image) { croppedImage in
                        pages.append(croppedImage)
                        currentImage = nil
                        step = .review
                    } onRetake: {
                        currentImage = nil
                        step = .camera
                    } onCancel: {
                        currentImage = nil
                        if pages.isEmpty { dismiss() }
                        else { step = .review }
                    }
                }

            case .review:
                PageReviewView(pages: $pages) {
                    step = .camera
                } onSave: { processedImages in
                    if let doc = documentManager.savePDF(from: processedImages) {
                        savedDocument = doc
                        step = .saved
                    }
                } onCancel: {
                    dismiss()
                }

            case .saved:
                if let doc = savedDocument {
                    SavedView(
                        document: doc,
                        pdfURL: documentManager.pdfURL(for: doc)
                    ) {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Saved View

struct SavedView: View {
    let document: ScannedDocument
    let pdfURL: URL
    let onDone: () -> Void

    @State private var showShareSheet = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)

            Text("PDF Saved!")
                .font(.title.bold())
                .foregroundColor(.white)

            Text(document.name)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))

            Text("\(document.pageCount) page\(document.pageCount == 1 ? "" : "s")")
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))

            Spacer()

            VStack(spacing: 14) {
                Button {
                    showShareSheet = true
                } label: {
                    Label("Share PDF", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .background(Color.blue)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))

                Button {
                    onDone()
                } label: {
                    Label("Home", systemImage: "house.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .background(Color.white.opacity(0.2))
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color.black)
        .sheet(isPresented: $showShareSheet) {
            ActivityView(activityItems: [pdfURL])
        }
    }
}

// MARK: - UIActivityViewController Wrapper

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Page Review (with Filter Modes)

struct PageReviewView: View {
    @Binding var pages: [UIImage]
    let onAddPage: () -> Void
    let onSave: ([UIImage]) -> Void
    let onCancel: () -> Void

    @State private var filterMode: FilterMode = .original
    @State private var filteredPages: [UIImage] = []
    @State private var isProcessing = false
    @State private var adjustments = ManualAdjustments.default
    @State private var showSliders = false

    private var displayPages: [UIImage] {
        filteredPages.isEmpty ? pages : filteredPages
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Picker("Filter", selection: $filterMode) {
                        ForEach(FilterMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Button {
                        withAnimation { showSliders.toggle() }
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.title3)
                            .foregroundStyle(showSliders ? .blue : .secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 4)

                if showSliders {
                    adjustmentSliders
                }

                if isProcessing {
                    Spacer()
                    ProgressView("Applying filter...")
                        .foregroundStyle(.secondary)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 20) {
                            ForEach(displayPages.indices, id: \.self) { index in
                                ZStack(alignment: .topLeading) {
                                    Image(uiImage: displayPages[index])
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        .shadow(color: .black.opacity(0.15), radius: 6, y: 3)

                                    HStack {
                                        Text("Page \(index + 1)")
                                            .font(.caption.bold())
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(.ultraThinMaterial)
                                            .clipShape(Capsule())

                                        Spacer()

                                        Button { rotatePage(at: index) } label: {
                                            Image(systemName: "rotate.right.fill")
                                                .font(.caption.bold())
                                                .padding(8)
                                                .background(.ultraThinMaterial)
                                                .clipShape(Circle())
                                        }

                                        if pages.count > 1 {
                                            Button { deletePage(at: index) } label: {
                                                Image(systemName: "trash")
                                                    .font(.caption.bold())
                                                    .padding(8)
                                                    .background(.ultraThinMaterial)
                                                    .clipShape(Circle())
                                            }
                                        }
                                    }
                                    .padding(12)
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding(.vertical)
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("\(pages.count) Page\(pages.count == 1 ? "" : "s") Scanned")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        onSave(displayPages)
                    } label: {
                        Text("Save PDF").bold()
                    }
                    .disabled(isProcessing)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button(action: onAddPage) {
                        Label("Add Page", systemImage: "plus.circle.fill")
                            .font(.headline)
                    }
                }
            }
            .onChange(of: filterMode) { _ in applyFilter() }
            .onChange(of: adjustments) { _ in applyFilter() }
            .onAppear { applyFilter() }
        }
    }

    private var adjustmentSliders: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "sun.min")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Slider(value: $adjustments.brightness, in: -0.3...0.3, step: 0.01)
                Image(systemName: "sun.max.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text("Brightness")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 65, alignment: .leading)
            }

            HStack {
                Image(systemName: "circle.lefthalf.filled")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Slider(value: $adjustments.contrast, in: 0.5...2.0, step: 0.01)
                Image(systemName: "circle.righthalf.filled")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text("Contrast")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 65, alignment: .leading)
            }

            HStack {
                Image(systemName: "drop")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Slider(value: $adjustments.sharpness, in: 0.0...1.0, step: 0.01)
                Image(systemName: "drop.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text("Sharpness")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 65, alignment: .leading)
            }

            if !adjustments.isDefault {
                Button("Reset") {
                    adjustments = .default
                }
                .font(.caption)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemGroupedBackground))
    }

    private func rotatePage(at index: Int) {
        guard index < pages.count else { return }
        pages[index] = pages[index].rotated90()
        applyFilter()
    }

    private func deletePage(at index: Int) {
        guard pages.count > 1, index < pages.count else { return }
        pages.remove(at: index)
        applyFilter()
    }

    private func movePage(from source: IndexSet, to destination: Int) {
        pages.move(fromOffsets: source, toOffset: destination)
        applyFilter()
    }

    private func applyFilter() {
        isProcessing = true
        let mode = filterMode
        let adj = adjustments
        let originals = pages

        DispatchQueue.global(qos: .userInitiated).async {
            let processed = originals.map {
                ImageEnhancer.shared.apply(mode, to: $0, adjustments: adj)
            }
            DispatchQueue.main.async {
                filteredPages = processed
                isProcessing = false
            }
        }
    }
}
