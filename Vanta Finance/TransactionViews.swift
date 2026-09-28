import SwiftUI

struct JournalFilter: Equatable {
    var kind: TransactionKind?
    var accountID: UUID?
    var categoryID: UUID?
    var tagID: UUID?
    var usesDateRange = false
    var startDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    var endDate = Date()
    var minimumAmount = ""
    var maximumAmount = ""

    var isEmpty: Bool {
        kind == nil && accountID == nil && categoryID == nil && tagID == nil && !usesDateRange && minimumAmount.isEmpty && maximumAmount.isEmpty
    }
    var count: Int {
        [kind != nil, accountID != nil, categoryID != nil, tagID != nil, usesDateRange, !minimumAmount.isEmpty || !maximumAmount.isEmpty].filter { $0 }.count
    }
}

struct JournalView: View {
    @EnvironmentObject private var store: FinanceStore
    @Binding var composer: TransactionKind?
    @State private var search = ""
    @State private var filter = JournalFilter()
    @State private var showFilters = false
    @State private var showCalendar = false
    private var filtered: [FinanceTransaction] {
        store.transactions.filter { tx in
            let endExclusive = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: filter.endDate)) ?? filter.endDate
            let matchesFilter = (filter.kind == nil || tx.kind == filter.kind)
                && (filter.accountID == nil || tx.accountID == filter.accountID || tx.destinationAccountID == filter.accountID)
                && (filter.categoryID == nil || tx.categoryID == filter.categoryID)
                && filter.tagID.map(tx.tagIDs.contains) != false
                && (!filter.usesDateRange || (tx.date >= Calendar.current.startOfDay(for: filter.startDate) && tx.date < endExclusive))
                && (Decimal.parse(filter.minimumAmount).map { tx.amount >= $0 } ?? true)
                && (Decimal.parse(filter.maximumAmount).map { tx.amount <= $0 } ?? true)
            let matchesSearch = search.isEmpty
                || tx.note.localizedCaseInsensitiveContains(search)
                || store.categoryName(tx.categoryID).localizedCaseInsensitiveContains(search)
                || store.accountName(tx.accountID).localizedCaseInsensitiveContains(search)
                || NSDecimalNumber(decimal: tx.amount).stringValue.localizedCaseInsensitiveContains(search)
            return matchesFilter && matchesSearch
        }
    }
    private var groups: [(Date, [FinanceTransaction])] {
        Dictionary(grouping: filtered) { Calendar.current.startOfDay(for: $0.date) }.sorted { $0.key > $1.key }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                MonogramMark()
                VStack(alignment: .leading, spacing: 2) {
                    Text("PRIVATE LEDGER").font(.caption2.bold()).tracking(2)
                    Text("Journal").font(.system(.title2, design: .serif).weight(.medium))
                }
                Spacer()
                PremiumPill(text: "\(filtered.count) \(filtered.count == 1 ? "entry" : "entries")", icon: "book.closed.fill", tint: VantaTheme.gold)
            }
            .padding(.horizontal, 18)
            .padding(.top, 4)
            .padding(.bottom, 12)

            if !filter.isEmpty {
                HStack(spacing: 9) {
                    Image(systemName: "line.3.horizontal.decrease.circle.fill")
                    Text("\(filter.count) active \(filter.count == 1 ? "filter" : "filters")").font(.caption.weight(.semibold))
                    Spacer()
                    Button("Clear") { filter = JournalFilter() }.font(.caption.weight(.semibold))
                }
                .foregroundStyle(VantaTheme.cobalt)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(VantaTheme.cobalt.opacity(0.08))
            }

            if filtered.isEmpty {
                Spacer(minLength: 60)
                EmptyState(icon: search.isEmpty ? "book.closed" : "magnifyingglass", title: search.isEmpty ? "Your journal is empty" : "No matches", message: search.isEmpty ? "Each transaction becomes a clear, searchable entry." : "Try a different word or remove a filter.", actionTitle: search.isEmpty ? "Add transaction" : nil) { composer = .expense }
                Spacer()
            } else {
                List {
                    ForEach(groups, id: \.0) { day, items in
                        Section {
                            ForEach(items) { tx in
                                NavigationLink { TransactionDetailView(transactionID: tx.id) } label: { TransactionRow(transaction: tx) }
                                    .listRowBackground(Color.clear)
                                    .listRowSeparatorTint(Color.primary.opacity(0.07))
                            }
                        } header: {
                            HStack(alignment: .firstTextBaseline) {
                                Text(day.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(store.money(dayNet(items), signed: true))
                                    .font(.caption.monospacedDigit().weight(.semibold))
                                    .foregroundStyle(dayNet(items) >= 0 ? VantaTheme.forest : VantaTheme.terracotta)
                            }
                            .textCase(nil)
                            .padding(.top, 8)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .vantaBackground()
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Search notes, accounts, categories")
        .toolbar { ToolbarItemGroup(placement: .navigationBarTrailing) { Button { showCalendar = true } label: { Image(systemName: "calendar") }; Button { showFilters = true } label: { Image(systemName: filter.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill") }; AddMenu(composer: $composer) } }
        .sheet(isPresented: $showFilters) { FilterView(filter: $filter) }
        .navigationDestination(isPresented: $showCalendar) { CalendarTransactionsView() }
    }

    private func dayNet(_ items: [FinanceTransaction]) -> Decimal {
        items.reduce(Decimal.zero) { result, transaction in
            switch transaction.kind {
            case .income: return result + store.converted(transaction.amount, from: transaction.currencyCode)
            case .expense: return result - store.converted(transaction.amount, from: transaction.currencyCode)
            case .transfer, .adjustment: return result
            }
        }
    }
}

struct FilterView: View {
    @EnvironmentObject private var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
    @Binding var filter: JournalFilter

    var body: some View {
        NavigationStack {
            Form {
                Section("Transaction type") {
                    Picker("Type", selection: $filter.kind) {
                        Text("All types").tag(nil as TransactionKind?)
                        ForEach(TransactionKind.allCases) { kind in Text(kind.rawValue).tag(kind as TransactionKind?) }
                    }
                }
                Section("Classification") {
                    Picker("Account", selection: $filter.accountID) {
                        Text("All accounts").tag(nil as UUID?)
                        ForEach(store.accounts) { Text($0.name).tag($0.id as UUID?) }
                    }
                    Picker("Category", selection: $filter.categoryID) {
                        Text("All categories").tag(nil as UUID?)
                        ForEach(store.categories.filter { $0.archivedAt == nil }) { Text($0.name).tag($0.id as UUID?) }
                    }
                    Picker("Tag", selection: $filter.tagID) {
                        Text("All tags").tag(nil as UUID?)
                        ForEach(store.tags) { Text($0.name).tag($0.id as UUID?) }
                    }
                }
                Section("Date range") {
                    Toggle("Limit by date", isOn: $filter.usesDateRange)
                    if filter.usesDateRange {
                        DatePicker("From", selection: $filter.startDate, displayedComponents: .date)
                        DatePicker("Through", selection: $filter.endDate, in: filter.startDate..., displayedComponents: .date)
                    }
                }
                Section("Amount") {
                    TextField("Minimum", text: $filter.minimumAmount).keyboardType(.decimalPad)
                    TextField("Maximum", text: $filter.maximumAmount).keyboardType(.decimalPad)
                    if let minimum = Decimal.parse(filter.minimumAmount), let maximum = Decimal.parse(filter.maximumAmount), minimum > maximum {
                        Text("Minimum must not exceed maximum.").font(.footnote).foregroundStyle(VantaTheme.terracotta)
                    }
                }
                Section { Text("Search text and these filters are combined. Transfers match either participating account.").font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle("Filter journal")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: filter.startDate) { value in if filter.endDate < value { filter.endDate = value } }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Reset") { filter = JournalFilter() }.disabled(filter.isEmpty) }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.disabled(invalidRange) }
            }
        }
    }

    private var invalidRange: Bool {
        guard let minimum = Decimal.parse(filter.minimumAmount), let maximum = Decimal.parse(filter.maximumAmount) else { return false }
        return minimum > maximum
    }
}

struct CalendarTransactionsView: View {
    @EnvironmentObject private var store: FinanceStore
    @State private var month = Date()
    @State private var selected: Date?
    private let columns = Array(repeating: GridItem(.flexible()), count: 7)
    private var days: [Date?] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        let first = interval.start
        let offset = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        let count = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        return Array(repeating: nil, count: offset) + (0..<count).map { calendar.date(byAdding: .day, value: $0, to: first) }
    }
    var body: some View { ScrollView { VStack(spacing: 18) { HStack { Button { shift(-1) } label: { Image(systemName: "chevron.left") }; Spacer(); Text(month.formatted(.dateTime.month(.wide).year())).font(.title3.bold()); Spacer(); Button { shift(1) } label: { Image(systemName: "chevron.right") } }.padding(.horizontal); LazyVGrid(columns: columns, spacing: 8) { ForEach(Calendar.current.veryShortWeekdaySymbols, id: \.self) { Text($0).font(.caption2.weight(.semibold)).foregroundStyle(.secondary) }; ForEach(Array(days.enumerated()), id: \.offset) { _, date in if let date { dayCell(date) } else { Color.clear.frame(height: 52) } } }; if let selected { let entries = store.transactions.filter { Calendar.current.isDate($0.date, inSameDayAs: selected) }; VStack(alignment: .leading, spacing: 10) { SectionHeader(title: selected.formatted(date: .long, time: .omitted)); if entries.isEmpty { Text("No activity on this day.").foregroundStyle(.secondary) } else { ForEach(entries) { tx in NavigationLink { TransactionDetailView(transactionID: tx.id) } label: { TransactionRow(transaction: tx) }.buttonStyle(.plain); Divider() } } }.padding() } }.padding(.vertical) }.vantaBackground().navigationTitle("Calendar").navigationBarTitleDisplayMode(.inline) }
    private func dayCell(_ date: Date) -> some View { let txs = store.transactions.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }; return Button { selected = date } label: { VStack(spacing: 5) { Text("\(Calendar.current.component(.day, from: date))").font(.subheadline.weight(Calendar.current.isDateInToday(date) ? .bold : .regular)); HStack(spacing: 2) { if txs.contains(where: { $0.kind == .income }) { Circle().fill(VantaTheme.forest).frame(width: 5, height: 5) }; if txs.contains(where: { $0.kind == .expense }) { Circle().fill(VantaTheme.terracotta).frame(width: 5, height: 5) } }.frame(height: 6) }.frame(maxWidth: .infinity).frame(height: 52).background(selected.map { Calendar.current.isDate($0, inSameDayAs: date) } == true ? VantaTheme.cobalt.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain) }
    private func shift(_ value: Int) { month = Calendar.current.date(byAdding: .month, value: value, to: month) ?? month }
}

struct TransactionDetailView: View {
    @EnvironmentObject private var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
    let transactionID: UUID
    @State private var edit = false
    @State private var deleteConfirm = false
    private var tx: FinanceTransaction? { store.transactions.first { $0.id == transactionID } }
    var body: some View { Group { if let tx { List { Section { VStack(spacing: 8) { Image(systemName: tx.kind.icon).font(.title).foregroundStyle(tx.kind == .income ? VantaTheme.forest : VantaTheme.terracotta); Text(store.money(tx.amount, code: tx.currencyCode)).font(.largeTitle.bold()); Text(tx.kind.rawValue).font(.subheadline).foregroundStyle(.secondary) }.frame(maxWidth: .infinity).padding(.vertical) }; Section("Details") { LabeledContent("Date", value: tx.date.formatted(date: .long, time: .shortened)); LabeledContent("Account", value: store.accountName(tx.accountID)); if tx.kind == .transfer { LabeledContent("To", value: store.accountName(tx.destinationAccountID)); LabeledContent("Exchange rate", value: NSDecimalNumber(decimal: tx.exchangeRate).stringValue) } else { LabeledContent("Category", value: store.categoryName(tx.categoryID)) }; if !tx.note.isEmpty { LabeledContent("Note", value: tx.note) } }; if !tx.tagIDs.isEmpty { Section("Tags") { Text(store.tags.filter { tx.tagIDs.contains($0.id) }.map(\.name).joined(separator: ", ")) } }; Section { Button("Edit transaction") { edit = true }; Button("Delete transaction", role: .destructive) { deleteConfirm = true } } }.navigationTitle("Transaction").sheet(isPresented: $edit) { TransactionEditorView(kind: tx.kind, existing: tx) }.confirmationDialog("Delete this transaction?", isPresented: $deleteConfirm, titleVisibility: .visible) { Button("Delete", role: .destructive) { store.deleteTransaction(transactionID); dismiss() } } message: { Text("Balances and reports will update immediately. This cannot be undone after you leave this screen.") } } else { EmptyState(icon: "doc.questionmark", title: "Transaction unavailable", message: "It may have been deleted.") } } }
}

struct TransactionEditorView: View {
    @EnvironmentObject private var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
    let kind: TransactionKind
    let existing: FinanceTransaction?
    @State private var amount: String
    @State private var convertedAmount: String
    @State private var exchangeRate: String
    @State private var date: Date
    @State private var note: String
    @State private var accountID: UUID?
    @State private var destinationID: UUID?
    @State private var categoryID: UUID?
    @State private var selectedTags: Set<UUID>
    @State private var closeConfirm = false
    @State private var showCategory = false
    @State private var showTags = false
    init(kind: TransactionKind, existing: FinanceTransaction? = nil) {
        self.kind = kind; self.existing = existing
        _amount = State(initialValue: existing.map { NSDecimalNumber(decimal: $0.amount).stringValue } ?? "")
        _convertedAmount = State(initialValue: existing.map { NSDecimalNumber(decimal: $0.convertedAmount).stringValue } ?? "")
        _exchangeRate = State(initialValue: existing.map { NSDecimalNumber(decimal: $0.exchangeRate).stringValue } ?? "1")
        _date = State(initialValue: existing?.date ?? Date()); _note = State(initialValue: existing?.note ?? "")
        _accountID = State(initialValue: existing?.accountID); _destinationID = State(initialValue: existing?.destinationAccountID); _categoryID = State(initialValue: existing?.categoryID); _selectedTags = State(initialValue: Set(existing?.tagIDs ?? []))
    }
    private var valid: Bool { guard let value = Decimal.parse(amount), value > 0, accountID != nil else { return false }; if kind == .transfer { guard destinationID != nil, destinationID != accountID, let rate = Decimal.parse(exchangeRate), rate > 0 else { return false }; return destinationCurrency == currencyCode || (Decimal.parse(convertedAmount) ?? 0) > 0 }; return categoryID != nil }
    private var hasDraft: Bool { !amount.isEmpty || !note.isEmpty || accountID != nil || categoryID != nil }
    var body: some View { NavigationStack { Form { Section { HStack(alignment: .firstTextBaseline) { Text(currencyCode).font(.headline).foregroundStyle(.secondary); TextField("0.00", text: $amount).font(.system(size: 36, weight: .bold, design: .rounded)).keyboardType(.decimalPad).multilineTextAlignment(.trailing) } } footer: { if !amount.isEmpty && (Decimal.parse(amount) ?? 0) <= 0 { Text("Enter an amount greater than zero.").foregroundStyle(.red) } }; Section("From") { Picker("Account", selection: $accountID) { Text("Select account").tag(nil as UUID?); ForEach(store.activeAccounts) { Text("\($0.name) · \($0.currencyCode)").tag($0.id as UUID?) } } }; if kind == .transfer { Section("To") { Picker("Destination", selection: $destinationID) { Text("Select account").tag(nil as UUID?); ForEach(store.activeAccounts.filter { $0.id != accountID }) { Text("\($0.name) · \($0.currencyCode)").tag($0.id as UUID?) } }; TextField("Recipient amount", text: $convertedAmount).keyboardType(.decimalPad); TextField("Exchange rate", text: $exchangeRate).keyboardType(.decimalPad) } } else { Section("Classification") { Button { showCategory = true } label: { HStack { Text("Category"); Spacer(); Text(store.categoryName(categoryID)).foregroundStyle(.secondary); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) } }; Button { showTags = true } label: { HStack { Text("Tags"); Spacer(); Text(selectedTags.isEmpty ? "None" : "\(selectedTags.count) selected").foregroundStyle(.secondary); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) } } } }; Section("When and why") { DatePicker("Date", selection: $date); TextField("Note (optional)", text: $note, axis: .vertical) } }.navigationTitle(existing == nil ? "New \(kind.rawValue.lowercased())" : "Edit transaction").navigationBarTitleDisplayMode(.inline).interactiveDismissDisabled(hasDraft).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if hasDraft && existing == nil { closeConfirm = true } else { dismiss() } } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(!valid) } }.confirmationDialog("Discard this draft?", isPresented: $closeConfirm, titleVisibility: .visible) { Button("Discard", role: .destructive) { dismiss() }; Button("Keep editing", role: .cancel) {} }.sheet(isPresented: $showCategory) { CategoryPickerView(kind: kind == .income ? .income : .expense, selection: $categoryID) }.sheet(isPresented: $showTags) { TagPickerView(selection: $selectedTags) }.onAppear { if accountID == nil { accountID = store.activeAccounts.first?.id }; if categoryID == nil && kind != .transfer { categoryID = store.categories.first(where: { $0.kind == (kind == .income ? .income : .expense) && $0.archivedAt == nil })?.id } } } }
    private var currencyCode: String { store.accounts.first(where: { $0.id == accountID })?.currencyCode ?? store.settings.baseCurrency }
    private var destinationCurrency: String { store.accounts.first(where: { $0.id == destinationID })?.currencyCode ?? currencyCode }
    private func save() { guard let accountID, let value = Decimal.parse(amount) else { return }; let sourceAmount = store.rounded(value, currencyCode: currencyCode); let targetCode = store.accounts.first(where: { $0.id == destinationID })?.currencyCode ?? currencyCode; let recipientAmount = store.rounded(Decimal.parse(convertedAmount) ?? sourceAmount, currencyCode: targetCode); var tx = existing ?? FinanceTransaction(kind: kind, amount: sourceAmount, currencyCode: currencyCode, convertedAmount: recipientAmount, exchangeRate: 1, date: date, note: note, accountID: accountID); tx.kind = kind; tx.amount = sourceAmount; tx.currencyCode = currencyCode; tx.date = date; tx.note = note.trimmingCharacters(in: .whitespacesAndNewlines); tx.accountID = accountID; tx.destinationAccountID = kind == .transfer ? destinationID : nil; tx.categoryID = kind == .transfer ? nil : categoryID; tx.tagIDs = Array(selectedTags); tx.exchangeRate = Decimal.parse(exchangeRate) ?? 1; tx.convertedAmount = kind == .transfer ? recipientAmount : sourceAmount; existing == nil ? store.addTransaction(tx) : store.updateTransaction(tx); dismiss() }
}

struct CategoryPickerView: View {
    @EnvironmentObject private var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
    let kind: CategoryKind
    @Binding var selection: UUID?
    @State private var search = ""
    @State private var add = false
    private var items: [FinanceCategory] { store.categories.filter { $0.kind == kind && $0.archivedAt == nil && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) } }
    var body: some View { NavigationStack { List { ForEach(items) { item in Button { selection = item.id; dismiss() } label: { HStack { Image(systemName: item.iconName).foregroundStyle(Color(hex: item.colorHex)).frame(width: 28); Text(item.name); Spacer(); if selection == item.id { Image(systemName: "checkmark") } } } }; Section { Button { add = true } label: { Label("Create category", systemImage: "plus") } } }.searchable(text: $search).navigationTitle("Choose category").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }.sheet(isPresented: $add) { CategoryEditorView(kind: kind) } } }
}

struct TagPickerView: View {
    @EnvironmentObject private var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: Set<UUID>
    @State private var newName = ""
    var body: some View { NavigationStack { List { ForEach(store.tags) { tag in Button { if selection.contains(tag.id) { selection.remove(tag.id) } else { selection.insert(tag.id) } } label: { HStack { Circle().fill(Color(hex: tag.colorHex)).frame(width: 10, height: 10); Text(tag.name); Spacer(); Image(systemName: selection.contains(tag.id) ? "checkmark.circle.fill" : "circle") } } }; Section("New tag") { HStack { TextField("Tag name", text: $newName); Button("Add") { store.addTag(FinanceTag(name: newName.trimmingCharacters(in: .whitespaces), colorHex: "315CFF")); newName = "" }.disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty) } } }.navigationTitle("Tags").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } } } }
}
