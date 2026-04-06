import SwiftUI

struct ContentView: View {
    @EnvironmentObject var documentManager: DocumentManager
    @State private var showSourcePicker = false
    @State private var showScanner = false
    @State private var scanSourceType: UIImagePickerController.SourceType = .camera
    @State private var selectedDocument: ScannedDocument?

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
            Group {
                if documentManager.documents.isEmpty {
                    emptyState
                } else {
                    documentGrid
                }
            }
            .navigationTitle("SnapPDF")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showSourcePicker = true } label: {
                        Image(systemName: "camera.fill")
                            .font(.title3)
                    }
                }
            }
            .confirmationDialog("New Scan", isPresented: $showSourcePicker) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Take Photo") {
                        scanSourceType = .camera
                        showScanner = true
                    }
                }
                Button("Choose from Library") {
                    scanSourceType = .photoLibrary
                    showScanner = true
                }
            }
            .fullScreenCover(isPresented: $showScanner) {
                ScannerFlowView(sourceType: scanSourceType)
                    .environmentObject(documentManager)
            }
            .sheet(item: $selectedDocument) { doc in
                PDFPreviewView(document: doc)
                    .environmentObject(documentManager)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 80))
                .foregroundStyle(.blue.opacity(0.5))

            Text("No Documents Yet")
                .font(.title2.bold())

            Text("Tap the camera icon to take a photo\nor choose from your library")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                showSourcePicker = true
            } label: {
                Label("Scan Document", systemImage: "camera.fill")
                    .font(.headline)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(.blue)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Document Grid

    private var documentGrid: some View {
        ScrollView {
            Text("Tap the camera icon to take a photo or choose from your library")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)

            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(documentManager.documents) { doc in
                    DocumentCard(document: doc)
                        .onTapGesture { selectedDocument = doc }
                        .contextMenu {
                            Button {
                                shareDocument(doc)
                            } label: {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                            Button(role: .destructive) {
                                withAnimation { documentManager.delete(doc) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
            .padding()
        }
    }

    private func shareDocument(_ doc: ScannedDocument) {
        let url = documentManager.pdfURL(for: doc)
        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.keyWindow?.rootViewController {
            if let popover = av.popoverPresentationController {
                popover.sourceView = root.view
                popover.sourceRect = CGRect(x: root.view.bounds.midX, y: root.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            root.present(av, animated: true)
        }
    }
}

// MARK: - Document Card

struct DocumentCard: View {
    @EnvironmentObject var documentManager: DocumentManager
    let document: ScannedDocument

    @State private var showShareSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let thumb = documentManager.thumbnail(for: document) {
                        Image(uiImage: thumb)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Color(.systemGray5)
                            .overlay {
                                Image(systemName: "doc.text")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                            }
                    }
                }
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Button {
                    showShareSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.caption.bold())
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                .padding(8)
            }
            .shadow(color: .black.opacity(0.08), radius: 4, y: 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(document.name)
                    .font(.caption.bold())
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text("\(document.pageCount) pg")
                    Text("·")
                    Text(document.createdAt, style: .date)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ActivityView(activityItems: [documentManager.pdfURL(for: document)])
        }
    }
}
