import SwiftUI
import PDFKit
import Vision

struct PDFPreviewView: View {
    @EnvironmentObject var documentManager: DocumentManager
    @Environment(\.dismiss) var dismiss
    let document: ScannedDocument

    @State private var isEditing = false
    @State private var editedName: String = ""
    @State private var showShareSheet = false
    @State private var showOCRSheet = false
    @State private var ocrText: String = ""
    @State private var isRunningOCR = false
    @State private var copiedToast = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                PDFKitView(url: documentManager.pdfURL(for: document))
                    .ignoresSafeArea(edges: .bottom)

                if copiedToast {
                    Text("Copied to clipboard")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .padding(.bottom, 40)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle(document.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            showShareSheet = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }

                        Menu {
                            Button {
                                extractText()
                            } label: {
                                Label("Extract Text (OCR)", systemImage: "doc.text.magnifyingglass")
                            }

                            Button {
                                editedName = document.name
                                isEditing = true
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }

                            Button(role: .destructive) {
                                documentManager.delete(document)
                                dismiss()
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .alert("Rename Document", isPresented: $isEditing) {
                TextField("Name", text: $editedName)
                Button("Save") {
                    let trimmed = editedName.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        documentManager.rename(document, to: trimmed)
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showShareSheet) {
                ActivityView(activityItems: [documentManager.pdfURL(for: document)])
            }
            .sheet(isPresented: $showOCRSheet) {
                OCRResultView(text: ocrText) {
                    UIPasteboard.general.string = ocrText
                    showOCRSheet = false
                    withAnimation { copiedToast = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation { copiedToast = false }
                    }
                }
            }
            .overlay {
                if isRunningOCR {
                    Color.black.opacity(0.3).ignoresSafeArea()
                    ProgressView("Extracting text...")
                        .padding(24)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }

    private func extractText() {
        isRunningOCR = true
        let url = documentManager.pdfURL(for: document)

        DispatchQueue.global(qos: .userInitiated).async {
            let text = OCREngine.extractText(from: url)
            DispatchQueue.main.async {
                ocrText = text
                isRunningOCR = false
                showOCRSheet = true
            }
        }
    }
}

// MARK: - OCR Result Sheet

struct OCRResultView: View {
    let text: String
    let onCopy: () -> Void

    @Environment(\.dismiss) var dismiss
    @State private var showShareSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if text.isEmpty {
                    VStack(spacing: 16) {
                        Spacer().frame(height: 60)
                        Image(systemName: "text.magnifyingglass")
                            .font(.system(size: 50))
                            .foregroundStyle(.secondary)
                        Text("No text found")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("The scanned page may not contain\nreadable text.")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                } else {
                    Text(text)
                        .font(.body)
                        .textSelection(.enabled)
                        .padding()
                }
            }
            .navigationTitle("Extracted Text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !text.isEmpty {
                        HStack(spacing: 16) {
                            Button(action: onCopy) {
                                Image(systemName: "doc.on.doc")
                            }
                            Button {
                                showShareSheet = true
                            } label: {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ActivityView(activityItems: [text])
            }
        }
    }
}

// MARK: - OCR Engine

enum OCREngine {
    static func extractText(from pdfURL: URL) -> String {
        guard let pdf = PDFDocument(url: pdfURL) else { return "" }

        var allText = ""

        for i in 0..<pdf.pageCount {
            guard let page = pdf.page(at: i) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let scale: CGFloat = 2.0
            let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)

            let image = page.thumbnail(of: size, for: .mediaBox)
            guard let cgImage = image.cgImage else { continue }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])

            guard let observations = request.results else { continue }

            let pageText = observations
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")

            if !pageText.isEmpty {
                if !allText.isEmpty { allText += "\n\n--- Page \(i + 1) ---\n\n" }
                allText += pageText
            }
        }

        return allText
    }
}

// MARK: - PDFKit Wrapper

struct PDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.document = PDFDocument(url: url)
        view.backgroundColor = .systemGroupedBackground
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {}
}
