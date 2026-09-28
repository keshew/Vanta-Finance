import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct DataManagementView: View {
    @EnvironmentObject private var store: FinanceStore
    @State private var exportDocument: DataFile?
    @State private var exportType = UTType.json
    @State private var exportName = "Vanta-Backup"
    @State private var exporting = false
    @State private var importing = false
    @State private var importPreview: ImportPreview?
    @State private var errorMessage: String?
    @State private var resetStage = 0

    var body: some View {
        List {
            Section("Export") {
                Button { prepareJSON() } label: { Label("Export complete JSON backup", systemImage: "doc.badge.arrow.up") }
                Button { prepareCSV() } label: { Label("Export transactions as CSV", systemImage: "tablecells") }
            }
            Section("Import & restore") {
                Button { importing = true } label: { Label("Choose JSON or CSV file", systemImage: "doc.badge.arrow.down") }
                Text("JSON restores a complete backup. CSV adds transactions that use existing account and category names. Every file is validated before any data changes.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Reset") {
                Button("Delete all local data", role: .destructive) { resetStage = 1 }
            }
        }
        .navigationTitle("Your data")
        .fileExporter(isPresented: $exporting, document: exportDocument, contentType: exportType, defaultFilename: exportName) { result in if case .failure(let error) = result { errorMessage = error.localizedDescription } }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .commaSeparatedText, .plainText]) { result in handleImport(result) }
        .sheet(item: $importPreview) { preview in ImportPreviewView(preview: preview) { do { switch preview.payload { case .json(let data): try store.importJSON(data); case .transactions(let transactions): try store.importTransactions(transactions) }; importPreview = nil } catch { errorMessage = error.localizedDescription } } }
        .alert("Unable to continue", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK") {} } message: { Text(errorMessage ?? "") }
        .confirmationDialog("Delete every account and transaction?", isPresented: Binding(get: { resetStage == 1 }, set: { if !$0 { resetStage = 0 } }), titleVisibility: .visible) { Button("Continue", role: .destructive) { resetStage = 2 }; Button("Cancel", role: .cancel) {} } message: { Text("This removes all accounts, transactions, budgets, goals, and settings from this device.") }
        .alert("Final confirmation", isPresented: Binding(get: { resetStage == 2 }, set: { if !$0 { resetStage = 0 } })) { Button("Delete everything", role: .destructive) { store.reset(); resetStage = 0 }; Button("Cancel", role: .cancel) {} } message: { Text("Export a backup first if you may need this data later. This action cannot be undone.") }
    }

    private func prepareJSON() { do { exportDocument = DataFile(data: try store.exportJSON()); exportType = .json; exportName = "Vanta-Backup-\(Date().formatted(.iso8601.year().month().day()))"; exporting = true } catch { errorMessage = error.localizedDescription } }
    private func prepareCSV() { exportDocument = DataFile(data: store.csvData()); exportType = .commaSeparatedText; exportName = "Vanta-Transactions"; exporting = true }
    private func handleImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            guard url.startAccessingSecurityScopedResource() else { throw ImportFailure.access }
            defer { url.stopAccessingSecurityScopedResource() }
            let data = try Data(contentsOf: url)
            if url.pathExtension.lowercased() == "json" {
                let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
                let snapshot = try decoder.decode(AppSnapshot.self, from: data)
                let duplicateCount = snapshot.transactions.filter { tx in store.transactions.contains(where: { $0.id == tx.id }) }.count
                importPreview = ImportPreview(payload: .json(data), title: "Backup preview", accounts: snapshot.accounts.count, transactions: snapshot.transactions.count, categories: snapshot.categories.count, duplicates: duplicateCount, errors: [])
            } else {
                importPreview = try csvPreview(data)
            }
        } catch { errorMessage = error.localizedDescription }
    }

    private func csvPreview(_ data: Data) throws -> ImportPreview {
        guard let text = String(data: data, encoding: .utf8) else { throw ImportFailure.encoding }
        let rows = CSVParser.rows(in: text)
        guard let header = rows.first?.map({ $0.lowercased() }), header == ["id", "date", "type", "amount", "currency", "account", "destination", "category", "note"] else { throw ImportFailure.header }
        var transactions: [FinanceTransaction] = []
        var errors: [String] = []
        let formatter = ISO8601DateFormatter()
        for (offset, row) in rows.dropFirst().enumerated() where row.contains(where: { !$0.isEmpty }) {
            let line = offset + 2
            guard row.count == 9 else { errors.append("Row \(line): expected 9 columns."); continue }
            guard let id = UUID(uuidString: row[0]), let date = formatter.date(from: row[1]), let kind = TransactionKind(rawValue: row[2]), let amount = Decimal.parse(row[3]), amount >= 0 else { errors.append("Row \(line): invalid ID, date, type, or amount."); continue }
            guard let source = store.accounts.first(where: { $0.name == row[5] }) else { errors.append("Row \(line): account ‘\(row[5])’ was not found."); continue }
            let destination = row[6].isEmpty || row[6] == "Unknown account" ? nil : store.accounts.first(where: { $0.name == row[6] })?.id
            let category = row[7].isEmpty || row[7] == "Uncategorized" ? nil : store.categories.first(where: { $0.name == row[7] })?.id
            if kind == .transfer && destination == nil { errors.append("Row \(line): transfer destination was not found."); continue }
            if kind != .transfer && kind != .adjustment && category == nil { errors.append("Row \(line): category ‘\(row[7])’ was not found."); continue }
            transactions.append(FinanceTransaction(id: id, kind: kind, amount: amount, currencyCode: row[4], convertedAmount: amount, exchangeRate: 1, date: date, note: row[8], accountID: source.id, destinationAccountID: destination, categoryID: category))
        }
        let duplicates = transactions.filter { candidate in store.transactions.contains { $0.id == candidate.id } }.count
        return ImportPreview(payload: .transactions(transactions), title: "CSV import preview", accounts: 0, transactions: transactions.count, categories: 0, duplicates: duplicates, errors: errors)
    }

    enum ImportFailure: LocalizedError {
        case access, encoding, header
        var errorDescription: String? { switch self { case .access: return "Vanta could not securely access this file."; case .encoding: return "The CSV file is not valid UTF-8 text."; case .header: return "The CSV columns do not match a Vanta transaction export." } }
    }
}

enum ImportPayload {
    case json(Data)
    case transactions([FinanceTransaction])
}

struct ImportPreview: Identifiable {
    let id = UUID()
    let payload: ImportPayload
    let title: String
    let accounts: Int
    let transactions: Int
    let categories: Int
    let duplicates: Int
    let errors: [String]
}

struct ImportPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let preview: ImportPreview
    let confirm: () -> Void
    var body: some View { NavigationStack { List { Section("Validated content") { if preview.accounts > 0 { LabeledContent("Accounts", value: "\(preview.accounts)") }; LabeledContent("Transactions", value: "\(preview.transactions)"); if preview.categories > 0 { LabeledContent("Categories", value: "\(preview.categories)") }; LabeledContent("Matching IDs", value: "\(preview.duplicates)") }; if !preview.errors.isEmpty { Section("Errors") { ForEach(preview.errors.prefix(20), id: \.self) { Text($0).font(.footnote).foregroundStyle(VantaTheme.terracotta) }; if preview.errors.count > 20 { Text("And \(preview.errors.count - 20) more errors…").font(.footnote).foregroundStyle(.secondary) } } }; Section { Text(preview.errors.isEmpty ? "Validation passed. The import is applied in one operation." : "Fix the listed rows and choose the file again. Nothing has been imported.").font(.footnote).foregroundStyle(.secondary) } }.navigationTitle(preview.title).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Import") { confirm() }.disabled(!preview.errors.isEmpty) } } } }
}

enum CSVParser {
    static func rows(in text: String) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = "", quoted = false
        let characters = Array(text)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                if quoted && index + 1 < characters.count && characters[index + 1] == "\"" { field.append("\""); index += 1 }
                else { quoted.toggle() }
            } else if character == "," && !quoted { row.append(field); field = "" }
            else if (character == "\n" || character == "\r") && !quoted {
                if character == "\r" && index + 1 < characters.count && characters[index + 1] == "\n" { index += 1 }
                row.append(field); rows.append(row); row = []; field = ""
            } else { field.append(character) }
            index += 1
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }
}

struct DiagnosticsView: View {
    @EnvironmentObject private var store: FinanceStore
    var body: some View { List { Section("Local records") { LabeledContent("Accounts", value: "\(store.accounts.count)"); LabeledContent("Transactions", value: "\(store.transactions.count)"); LabeledContent("Categories", value: "\(store.categories.count)"); LabeledContent("Budgets", value: "\(store.budgets.count)"); LabeledContent("Goals", value: "\(store.goals.count)"); LabeledContent("Recurring rules", value: "\(store.recurringRules.count)"); LabeledContent("Database size", value: ByteCountFormatter.string(fromByteCount: store.databaseSize, countStyle: .file)) }; Section("Integrity") { let issues = store.integrityIssues(); Label(issues.isEmpty ? "References are consistent" : "\(issues.count) integrity issue\(issues.count == 1 ? "" : "s")", systemImage: issues.isEmpty ? "checkmark.seal.fill" : "exclamationmark.triangle.fill").foregroundStyle(issues.isEmpty ? VantaTheme.forest : VantaTheme.terracotta); ForEach(issues, id: \.self) { Text($0).font(.footnote) }; Text("This check runs locally and sends no diagnostics anywhere.").font(.footnote).foregroundStyle(.secondary) } }.navigationTitle("Diagnostics") }
}

struct PrivacyView: View {
    var body: some View { ScrollView { VStack(alignment: .leading, spacing: 18) { Image(systemName: "hand.raised.fill").font(.system(size: 48)).foregroundStyle(VantaTheme.cobalt); Text("Private by default").font(.largeTitle.bold()); Text("Vanta Finance stores your financial journal on this device using Apple's Core Data framework. The app has no user accounts, advertising, analytics, tracking SDKs, or remote data endpoints."); privacySection("What Vanta stores", "Accounts, transactions, categories, budgets, goals, recurring schedules, manual exchange rates, and preferences you create."); privacySection("When data leaves the app", "Only when you explicitly export or share a backup or CSV file through the iOS share sheet. You choose the destination."); privacySection("Device permissions", "Biometric authentication and local notification permission are requested only after you enable those features. Biometric templates remain controlled by iOS."); privacySection("Your control", "You can export a complete JSON backup or permanently reset all local data from Data settings."); Text("Privacy policy · Version 1.0 · Stored inside the app").font(.caption).foregroundStyle(.secondary).padding(.top) }.font(.body).lineSpacing(5).padding() }.vantaBackground().navigationTitle("Privacy") }
    private func privacySection(_ title: String, _ text: String) -> some View { VStack(alignment: .leading, spacing: 6) { Text(title).font(.headline); Text(text).foregroundStyle(.secondary) } }
}

struct HelpView: View {
    private let questions = [
        ("How are balances calculated?", "A balance is the opening balance plus income, minus expenses, with transfers applied to both participating accounts."),
        ("Do transfers count as income?", "No. Transfers move money between your accounts and are excluded from income, spending, and budgets."),
        ("Why does a foreign account need a rate?", "Vanta keeps original amounts intact. A manual rate converts them only when calculating totals in your base currency."),
        ("Will recurring bills post automatically?", "No. Vanta creates a pending occurrence and waits for you to post or skip it."),
        ("How do I move my data?", "Export a JSON backup from More › Import, export & backup. Restore that file on the other device."),
        ("Can I recover deleted data?", "A deleted transaction cannot be recovered inside the app. Export regular backups if you need restore points.")
    ]
    var body: some View { List { Section { Text("Straight answers about your private financial journal.").foregroundStyle(.secondary) }; ForEach(questions, id: \.0) { question in DisclosureGroup(question.0) { Text(question.1).foregroundStyle(.secondary).padding(.vertical, 6) } }; Section("Support") { Button { UIPasteboard.general.string = "support@vantafinance.app" } label: { Label("Copy support email", systemImage: "doc.on.doc") }; Text("support@vantafinance.app").font(.caption).foregroundStyle(.secondary) } }.navigationTitle("Help & FAQ") }
}

struct AboutView: View {
    var body: some View { List { Section { VStack(spacing: 14) { Image(systemName: "circle.hexagongrid.fill").font(.system(size: 60)).foregroundStyle(VantaTheme.cobalt); Text("Vanta Finance").font(.title.bold()); Text("Version \(version) (\(build))").foregroundStyle(.secondary); Text("A quiet place to understand your money.").multilineTextAlignment(.center) }.frame(maxWidth: .infinity).padding(.vertical, 20) }; Section("Built with") { LabeledContent("Interface", value: "SwiftUI"); LabeledContent("Storage", value: "Core Data"); LabeledContent("Charts", value: "Apple Charts") }; Section("Licenses") { Text("Vanta uses only Apple system frameworks. No third-party software components are included.").font(.footnote).foregroundStyle(.secondary) }; Section { Text("© 2026 Vanta Finance. Your data stays yours.").font(.caption).foregroundStyle(.secondary) } }.navigationTitle("About") }
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0" }
    private var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1" }
}
