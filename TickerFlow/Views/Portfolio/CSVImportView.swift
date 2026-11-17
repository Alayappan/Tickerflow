import SwiftUI
import UniformTypeIdentifiers

public struct CSVImportView: View {
    @Environment(\.dismiss) private var dismiss
    public let store: FinanceStore

    @State private var csvText: String = ""
    @State private var selectedFileName: String?
    @State private var fileReadError: String?
    @State private var showFileImporter: Bool = false
    @State private var parseResult: FinancialCSVParser.ParseResult?
    @State private var importSuccess: Bool = false
    @State private var targetPortfolioId: UUID?

    public init(store: FinanceStore) {
        self.store = store
        _targetPortfolioId = State(initialValue: store.currentPortfolio?.id)
    }

    private var activePortfolio: Portfolio? {
        store.portfolio(for: targetPortfolioId) ?? store.currentPortfolio
    }

    public var body: some View {
        NavigationStack {
            Form {
                if !store.portfolios.isEmpty {
                    Section("Target Portfolio") {
                        Picker("Import Into", selection: Binding(
                            get: { activePortfolio?.id ?? store.portfolios[0].id },
                            set: { targetPortfolioId = $0 }
                        )) {
                            ForEach(store.portfolios) { portfolio in
                                Text("\(portfolio.name) (\(portfolio.currency))").tag(portfolio.id)
                            }
                        }
                    }
                }

                Section("CSV File") {
                    Text("Select a .csv file exported from your broker, Google Finance, or Yahoo Finance.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let fileName = selectedFileName {
                        HStack(spacing: 10) {
                            Image(systemName: "doc.text.fill")
                                .font(.title3)
                                .foregroundColor(.blue)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(fileName)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text("File loaded")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Button("Change File") {
                                showFileImporter = true
                            }
                            .font(.caption.bold())
                            .buttonStyle(.bordered)
                        }
                        .padding(.vertical, 4)
                    } else {
                        Button {
                            showFileImporter = true
                        } label: {
                            Label("Choose CSV File", systemImage: "doc.badge.plus")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.vertical, 4)
                    }

                    if let error = fileReadError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                if let result = parseResult {
                    Section("Preview: \(result.detectedSource)") {
                        if !result.errors.isEmpty {
                            ForEach(result.errors, id: \.self) { err in
                                Text(err)
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }

                        Text("Valid trades ready to import: \(result.transactions.count)")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        ForEach(result.transactions.prefix(5)) { tx in
                            HStack {
                                HStack(spacing: 6) {
                                    Text(tx.type.rawValue)
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(tx.type == .buy ? Color.blue.opacity(0.15) : Color.orange.opacity(0.15))
                                        .foregroundColor(tx.type == .buy ? .blue : .orange)
                                        .cornerRadius(4)

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(tx.symbol)
                                            .font(.headline)
                                        Text(tx.date.formatted(date: .abbreviated, time: .omitted))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                Text("\(String(format: "%.2f", tx.shares)) shares @ \(StockQuote.formatAmount(tx.pricePerShare, currency: activePortfolio?.currency ?? "USD"))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        if result.transactions.count > 5 {
                            Text("... and \(result.transactions.count - 5) more")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                if importSuccess {
                    Section {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Portfolio imported successfully!")
                                .font(.headline)
                                .foregroundColor(.green)
                        }
                    }
                }
            }
            .navigationTitle("Import Portfolio CSV")
            .navigationBarTitleDisplayMode(.inline)
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.commaSeparatedText, .plainText, .tabSeparatedText]
            ) { result in
                handleFileSelection(result)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        performImport()
                    }
                    .disabled(parseResult?.transactions.isEmpty ?? true)
                }
            }
        }
    }

    private func handleFileSelection(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let didStartAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let data = try Data(contentsOf: url)
                let decoded = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .utf16)
                    ?? String(data: data, encoding: .isoLatin1)

                guard let decoded, !decoded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    fileReadError = "The selected file is empty or uses an unsupported text encoding."
                    selectedFileName = url.lastPathComponent
                    csvText = ""
                    parseResult = nil
                    return
                }

                fileReadError = nil
                selectedFileName = url.lastPathComponent
                csvText = decoded
                previewCSV()
            } catch {
                fileReadError = "Unable to read file: \(error.localizedDescription)"
                csvText = ""
                parseResult = nil
            }

        case .failure(let error):
            fileReadError = "File selection failed: \(error.localizedDescription)"
        }
    }

    private func previewCSV() {
        guard !csvText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            parseResult = nil
            return
        }
        parseResult = FinancialCSVParser.parseCSV(text: csvText)
    }

    private func performImport() {
        let result = store.importCSV(text: csvText, portfolioId: activePortfolio?.id)
        if !result.transactions.isEmpty {
            importSuccess = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                dismiss()
            }
        }
    }
}
