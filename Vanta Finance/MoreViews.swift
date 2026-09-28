import SwiftUI
import UniformTypeIdentifiers
import LocalAuthentication
import UserNotifications

struct MoreView: View {
    @EnvironmentObject private var store: FinanceStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 12) {
                    MonogramMark()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("PRIVATE OFFICE").font(.caption2.bold()).tracking(2)
                        Text("Control center").font(.system(.title2, design: .serif).weight(.medium))
                    }
                    Spacer()
                }

                PremiumHeroCard {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("YOUR FINANCIAL SYSTEM").font(.caption2.bold()).tracking(1.4).foregroundStyle(.white.opacity(0.55))
                                Text("Private by design.").font(.system(size: 27, weight: .medium, design: .serif))
                            }
                            Spacer()
                            Image(systemName: "lock.shield.fill").font(.title).foregroundStyle(VantaTheme.gold)
                        }
                        PremiumDivider()
                        HStack {
                            officeMetric("ACCOUNTS", "\(store.activeAccounts.count)")
                            Spacer()
                            officeMetric("CATEGORIES", "\(store.categories.filter { $0.archivedAt == nil }.count)")
                            Spacer()
                            officeMetric("STORAGE", "On device")
                        }
                    }
                }

                officeSection("Portfolio") {
                    PrivateOfficeRow(title: "Accounts", subtitle: "Balances and account structure", icon: "wallet.pass.fill", tint: VantaTheme.cobalt) { AccountsView() }
                    PrivateOfficeRow(title: "Categories", subtitle: "Your allocation taxonomy", icon: "square.grid.2x2.fill", tint: VantaTheme.gold) { CategoriesView() }
                    PrivateOfficeRow(title: "Tags", subtitle: "Flexible context for every entry", icon: "tag.fill", tint: VantaTheme.forest) { TagsView() }
                }

                officeSection("Data stewardship") {
                    PrivateOfficeRow(title: "Import, export & backup", subtitle: "Portable files under your control", icon: "externaldrive.fill", tint: VantaTheme.cobalt) { DataManagementView() }
                    PrivateOfficeRow(title: "Local diagnostics", subtitle: "Inspect the health of your ledger", icon: "stethoscope", tint: VantaTheme.terracotta) { DiagnosticsView() }
                }

                officeSection("Preferences") {
                    PrivateOfficeRow(title: "Appearance", subtitle: "Theme and balance privacy", icon: "circle.lefthalf.filled", tint: VantaTheme.gold) { AppearanceSettingsView() }
                    PrivateOfficeRow(title: "Currencies & rates", subtitle: "Base currency and manual rates", icon: "dollarsign.arrow.circlepath", tint: VantaTheme.forest) { CurrencySettingsView() }
                    PrivateOfficeRow(title: "Formats & calendar", subtitle: "Financial period preferences", icon: "calendar.badge.clock", tint: VantaTheme.cobalt) { FormatSettingsView() }
                    PrivateOfficeRow(title: "Reminders", subtitle: "Private, on-device notifications", icon: "bell.fill", tint: VantaTheme.terracotta) { ReminderSettingsView() }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 36)
        }
        .vantaBackground()
        .navigationBarTitleDisplayMode(.inline)
    }

    private func officeMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 9, weight: .bold)).tracking(1).foregroundStyle(.white.opacity(0.45))
            Text(value).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.9))
        }
    }

    private func officeSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            SectionHeader(title: title)
            VStack(spacing: 0) { content() }
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.primary.opacity(0.05), lineWidth: 0.7))
        }
    }
}

private struct PrivateOfficeRow<Destination: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink(destination: destination()) {
            HStack(spacing: 13) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
        .buttonStyle(.plain)
        PremiumDivider().padding(.leading, 65)
    }
}

struct CategoriesView: View {
    @EnvironmentObject private var store: FinanceStore
    @State private var kind = CategoryKind.expense
    @State private var add = false
    @State private var editing: FinanceCategory?
    @State private var archiveRequested: FinanceCategory?
    @State private var showArchived = false
    var body: some View { List { Section { Picker("Type", selection: $kind) { ForEach(CategoryKind.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented) }; let items = store.categories.filter { $0.kind == kind && $0.archivedAt == nil }; if items.isEmpty { EmptyState(icon: "square.grid.2x2", title: "No categories", message: "Create one to classify transactions.", actionTitle: "Create category") { add = true } } else { ForEach(items) { item in NavigationLink { CategoryDetailView(categoryID: item.id) } label: { HStack { Image(systemName: item.iconName).foregroundStyle(Color(hex: item.colorHex)).frame(width: 30); Text(item.name); Spacer(); Text("\(store.transactions(forCategory: item.id).count)").font(.caption).foregroundStyle(.secondary) } }.contextMenu { Button("Edit") { editing = item }; Button("Archive", role: .destructive) { archiveRequested = item } } } }; Section { Button { showArchived = true } label: { Label("Archived categories", systemImage: "archivebox") } } }.navigationTitle("Categories").toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button { add = true } label: { Image(systemName: "plus") } } }.sheet(isPresented: $add) { CategoryEditorView(kind: kind) }.sheet(item: $editing) { CategoryEditorView(existing: $0, kind: $0.kind) }.navigationDestination(isPresented: $showArchived) { ArchivedCategoriesView() }.confirmationDialog("Archive this category?", isPresented: Binding(get: { archiveRequested != nil }, set: { if !$0 { archiveRequested = nil } }), titleVisibility: .visible) { Button("Archive", role: .destructive) { if let item = archiveRequested { store.archiveCategory(item.id) }; archiveRequested = nil }; Button("Cancel", role: .cancel) { archiveRequested = nil } } message: { Text("Existing transactions keep this category, but it will no longer be available for new entries.") } }
}

struct ArchivedCategoriesView: View {
    @EnvironmentObject private var store: FinanceStore
    var body: some View { List { let items = store.categories.filter { $0.archivedAt != nil }; if items.isEmpty { EmptyState(icon: "archivebox", title: "No archived categories", message: "Archived categories remain attached to their historical transactions.") } else { ForEach(items) { category in HStack { Label(category.name, systemImage: category.iconName); Spacer(); Button("Restore") { store.restoreCategory(category.id) } } } } }.navigationTitle("Archived categories") }
}

struct CategoryDetailView: View {
    @EnvironmentObject private var store: FinanceStore
    let categoryID: UUID
    @State private var edit = false
    @State private var archiveConfirm = false
    @Environment(\.dismiss) private var dismiss
    private var category: FinanceCategory? { store.categories.first { $0.id == categoryID } }
    var body: some View { Group { if let category { let items = store.transactions(forCategory: categoryID), total = items.reduce(Decimal.zero) { $0 + $1.amount }; List { Section { VStack(spacing: 8) { Image(systemName: category.iconName).font(.largeTitle).foregroundStyle(Color(hex: category.colorHex)); Text(category.name).font(.title.bold()); Text(store.money(total)).font(.title2.bold()); Text("\(items.count) transactions").foregroundStyle(.secondary) }.frame(maxWidth: .infinity).padding() }; Section("History") { if items.isEmpty { Text("No linked transactions").foregroundStyle(.secondary) } else { ForEach(items) { tx in NavigationLink { TransactionDetailView(transactionID: tx.id) } label: { TransactionRow(transaction: tx) } } } }; Section { Button("Edit category") { edit = true }; Button("Archive category", role: .destructive) { archiveConfirm = true } } }.navigationTitle("Category").sheet(isPresented: $edit) { CategoryEditorView(existing: category, kind: category.kind) }.confirmationDialog("Archive this category?", isPresented: $archiveConfirm, titleVisibility: .visible) { Button("Archive", role: .destructive) { store.archiveCategory(categoryID); dismiss() } } message: { Text("Historical transactions remain unchanged. The category disappears from new transaction forms.") } } } }
}

struct CategoryEditorView: View {
    @EnvironmentObject private var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
    let existing: FinanceCategory?
    let fixedKind: CategoryKind
    @State private var name: String
    @State private var icon: String
    @State private var color: String
    init(existing: FinanceCategory? = nil, kind: CategoryKind) { self.existing = existing; fixedKind = kind; _name = State(initialValue: existing?.name ?? ""); _icon = State(initialValue: existing?.iconName ?? "circle.grid.2x2"); _color = State(initialValue: existing?.colorHex ?? "315CFF") }
    var body: some View { NavigationStack { Form { TextField("Category name", text: $name); Section("Icon") { LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6)) { ForEach(["house", "basket", "car", "fork.knife", "cross.case", "sparkles", "briefcase", "gift", "cart", "airplane", "pawprint", "graduationcap"], id: \.self) { value in Button { icon = value } label: { Image(systemName: value).frame(width: 36, height: 36).background(icon == value ? VantaTheme.cobalt.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 8)) }.buttonStyle(.plain) } } }; Section("Color") { HStack { ForEach(["315CFF", "23856D", "D9684A", "C88A21", "6B68A9"], id: \.self) { value in Button { color = value } label: { Circle().fill(Color(hex: value)).frame(width: 32, height: 32).overlay { if color == value { Image(systemName: "checkmark").foregroundStyle(.white) } } }.buttonStyle(.plain) } } } }.navigationTitle(existing == nil ? "New category" : "Edit category").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { var item = existing ?? FinanceCategory(name: name, kind: fixedKind, iconName: icon, colorHex: color); item.name = name; item.iconName = icon; item.colorHex = color; existing == nil ? store.addCategory(item) : store.updateCategory(item); dismiss() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) } } } }
}

struct TagsView: View {
    @EnvironmentObject private var store: FinanceStore
    @State private var name = ""
    @State private var editing: FinanceTag?
    @State private var deleting: FinanceTag?
    var body: some View { List { Section("New tag") { HStack { TextField("Tag name", text: $name); Button("Add") { store.addTag(FinanceTag(name: name.trimmingCharacters(in: .whitespaces), colorHex: "315CFF")); name = "" }.disabled(!canAdd) } }; Section("Tags") { if store.tags.isEmpty { Text("No tags yet").foregroundStyle(.secondary) } else { ForEach(store.tags) { tag in Button { editing = tag } label: { HStack { Circle().fill(Color(hex: tag.colorHex)).frame(width: 10, height: 10); Text(tag.name).foregroundStyle(.primary); Spacer(); Text("\(store.transactions.filter { $0.tagIDs.contains(tag.id) }.count)").foregroundStyle(.secondary); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary) } }.swipeActions { Button("Delete", role: .destructive) { deleting = tag }; Button("Edit") { editing = tag }.tint(VantaTheme.cobalt) } } } } }.navigationTitle("Tags").sheet(item: $editing) { TagEditorView(tag: $0) }.confirmationDialog("Delete this tag?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) { Button("Delete", role: .destructive) { if let deleting { store.deleteTag(deleting.id) }; deleting = nil } } message: { Text("The tag will be removed from every transaction. Financial totals are not affected.") } }
    private var canAdd: Bool { let value = name.trimmingCharacters(in: .whitespacesAndNewlines); return !value.isEmpty && !store.tags.contains { $0.name.localizedCaseInsensitiveCompare(value) == .orderedSame } }
}

struct TagEditorView: View {
    @EnvironmentObject private var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
    let tag: FinanceTag
    @State private var name: String
    @State private var color: String
    init(tag: FinanceTag) { self.tag = tag; _name = State(initialValue: tag.name); _color = State(initialValue: tag.colorHex) }
    var body: some View { NavigationStack { Form { TextField("Tag name", text: $name); Section("Color") { HStack { ForEach(["4057D6", "267765", "C7694F", "B68A42", "6B68A9"], id: \.self) { value in Button { color = value } label: { Circle().fill(Color(hex: value)).frame(width: 34, height: 34).overlay { if color == value { Image(systemName: "checkmark").foregroundStyle(.white).font(.caption.bold()) } } }.buttonStyle(.plain) } } } }.navigationTitle("Edit tag").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { var value = tag; value.name = name.trimmingCharacters(in: .whitespacesAndNewlines); value.colorHex = color; store.updateTag(value); dismiss() }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) } } } }
}

struct AppearanceSettingsView: View {
    @EnvironmentObject private var store: FinanceStore
    var body: some View { Form { Section("Theme") { ForEach(AppearanceMode.allCases) { mode in Button { store.updateSettings { $0.appearance = mode } } label: { HStack { Text(mode.rawValue); Spacer(); if store.settings.appearance == mode { Image(systemName: "checkmark") } } } } }; Section("Balance privacy") { Toggle("Show amounts", isOn: Binding(get: { store.settings.amountVisibility }, set: { value in store.updateSettings { $0.amountVisibility = value } })) } }.navigationTitle("Appearance") }
}

struct CurrencySettingsView: View {
    @EnvironmentObject private var store: FinanceStore
    @State private var from = "EUR"
    @State private var to = "USD"
    @State private var rate = ""
    var body: some View {
        Form {
            Section {
                Picker("Currency", selection: Binding(get: { store.settings.baseCurrency }, set: { value in store.updateSettings { $0.baseCurrency = value } })) {
                    ForEach(CurrencyCatalog.common, id: \.code) { Text("\($0.code) — \($0.name)").tag($0.code) }
                }
            } header: {
                Text("Base currency")
            } footer: {
                Text("Existing transaction amounts are never rewritten. Totals use your latest manual rate.")
            }
            Section("Add manual rate") {
                Picker("From", selection: $from) { ForEach(CurrencyCatalog.common, id: \.code) { Text($0.code).tag($0.code) } }
                Picker("To", selection: $to) { ForEach(CurrencyCatalog.common, id: \.code) { Text($0.code).tag($0.code) } }
                TextField("Rate", text: $rate).keyboardType(.decimalPad)
                Button("Save rate") {
                    if let value = Decimal.parse(rate) {
                        store.addRate(ManualExchangeRate(fromCurrency: from, toCurrency: to, rate: value))
                        rate = ""
                    }
                }
                .disabled(from == to || (Decimal.parse(rate) ?? 0) <= 0)
            }
            Section("Saved rates") {
                if store.exchangeRates.isEmpty {
                    Text("No manual rates").foregroundStyle(.secondary)
                } else {
                    ForEach(store.exchangeRates) { item in
                        LabeledContent("1 \(item.fromCurrency)", value: "\(NSDecimalNumber(decimal: item.rate).stringValue) \(item.toCurrency)")
                            .swipeActions { Button("Delete", role: .destructive) { store.deleteRate(item.id) } }
                    }
                }
            }
        }
        .navigationTitle("Currencies")
    }
}

struct FormatSettingsView: View {
    @EnvironmentObject private var store: FinanceStore
    var body: some View { Form { Picker("Week starts", selection: Binding(get: { store.settings.weekStartsMonday }, set: { v in store.updateSettings { $0.weekStartsMonday = v } })) { Text("Monday").tag(true); Text("Sunday").tag(false) }; Stepper("Financial month starts on day \(store.settings.financialMonthStartDay)", value: Binding(get: { store.settings.financialMonthStartDay }, set: { v in store.updateSettings { $0.financialMonthStartDay = v } }), in: 1...28); Section { Text("Currency, number, and date formatting follows your device locale.").font(.footnote).foregroundStyle(.secondary) } }.navigationTitle("Formats & calendar") }
}

struct SecuritySettingsView: View {
    @EnvironmentObject private var store: FinanceStore
    @State private var message: String?
    var body: some View { Form { Section("App lock") { Toggle("Use Face ID or passcode", isOn: Binding(get: { store.settings.biometricLock }, set: { value in if value { authenticate() } else { store.updateSettings { $0.biometricLock = false } } })); Text("Authentication is performed entirely by iOS. Vanta never sees your biometric data.").font(.footnote).foregroundStyle(.secondary) }; if let message { Section { Text(message).foregroundStyle(.red) } } }.navigationTitle("Privacy & security") }
    private func authenticate() { let context = LAContext(); var error: NSError?; guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { message = "Device authentication is not available."; return }; context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Protect your financial journal") { success, error in DispatchQueue.main.async { if success { store.isUnlocked = true; store.updateSettings { $0.biometricLock = true } } else { message = error?.localizedDescription ?? "Authentication failed." } } } }
}

struct ReminderSettingsView: View {
    @EnvironmentObject private var store: FinanceStore
    @State private var status = ""
    var body: some View { Form { Toggle("Local reminders", isOn: Binding(get: { store.settings.remindersEnabled }, set: { value in if value { requestPermission() } else { store.updateSettings { $0.remindersEnabled = false }; UNUserNotificationCenter.current().removeAllPendingNotificationRequests() } })); Section { Text("Reminders are scheduled on this device only. Vanta does not use push notifications.").font(.footnote).foregroundStyle(.secondary); if !status.isEmpty { Text(status).font(.footnote) } } }.navigationTitle("Reminders") }
    private func requestPermission() { UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in DispatchQueue.main.async { store.updateSettings { $0.remindersEnabled = granted }; if granted { store.rescheduleNotifications() }; status = granted ? "Permission granted. Reminders are scheduled for recurring items that have an alert." : (error?.localizedDescription ?? "Permission was not granted.") } } }
}
