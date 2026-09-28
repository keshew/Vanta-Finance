import SwiftUI

enum AppTab: Hashable { case today, journal, plan, analytics, more }

struct MainTabView: View {
    @EnvironmentObject private var store: FinanceStore
    @State private var selection = AppTab.today
    @State private var composer: TransactionKind?
    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { TodayView(composer: $composer) }.tabItem { Label("Today", systemImage: "sun.max") }.tag(AppTab.today)
            NavigationStack { JournalView(composer: $composer) }.tabItem { Label("Journal", systemImage: "book.closed") }.tag(AppTab.journal)
            NavigationStack { PlanView(composer: $composer) }.tabItem { Label("Plan", systemImage: "flag.checkered") }.tag(AppTab.plan)
            NavigationStack { AnalyticsView() }.tabItem { Label("Analytics", systemImage: "chart.bar.xaxis") }.tag(AppTab.analytics)
            NavigationStack { MoreView() }.tabItem { Label("More", systemImage: "ellipsis") }.tag(AppTab.more)
        }
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(VantaTheme.paper.opacity(0.96), for: .tabBar)
        .sheet(item: $composer) { kind in TransactionEditorView(kind: kind) }
    }
}

struct AddMenu: View {
    @Binding var composer: TransactionKind?
    var body: some View {
        Menu {
            Button { composer = .expense } label: { Label("Add expense", systemImage: "arrow.up.right") }
            Button { composer = .income } label: { Label("Add income", systemImage: "arrow.down.left") }
            Button { composer = .transfer } label: { Label("Make transfer", systemImage: "arrow.left.arrow.right") }
        } label: { Image(systemName: "plus").font(.subheadline.weight(.bold)).frame(width: 38, height: 38).background(VantaTheme.ink, in: Circle()).foregroundStyle(.white).overlay(Circle().stroke(VantaTheme.gold.opacity(0.55), lineWidth: 0.7)).shadow(color: VantaTheme.ink.opacity(0.16), radius: 8, y: 4) }.accessibilityLabel("Add transaction")
    }
}

struct TodayView: View {
    @EnvironmentObject private var store: FinanceStore
    @Binding var composer: TransactionKind?
    @State private var showAccounts = false
    private var cashFlow: (income: Decimal, expense: Decimal) { store.monthIncomeExpense() }
    private var activeBudgets: [Budget] { let p = store.financialPeriod(); return store.budgets.filter { $0.periodStart < p.end && $0.periodEnd > p.start } }
    private var upcoming: [RecurringOccurrence] { store.occurrences.filter { $0.status == .pending }.sorted { $0.plannedDate < $1.plannedDate }.prefix(3).map { $0 } }
    private var net: Decimal { cashFlow.income - cashFlow.expense }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                brandHeader
                if store.activeAccounts.isEmpty {
                    EmptyState(icon: "wallet.pass", title: "Start with an account", message: "Add a bank account, card, or cash wallet to begin your private ledger.", actionTitle: "Create account") { showAccounts = true }
                } else {
                    balanceHero
                    quickActions
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Private accounts", action: "View portfolio") { showAccounts = true }
                        ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 12) { ForEach(store.activeAccounts) { account in NavigationLink(value: account) { AccountMiniCard(account: account) }.buttonStyle(.plain) } } }
                    }
                    budgetSummary
                    upcomingSummary
                    recentSummary
                    insight
                }
            }.padding(.horizontal, 18).padding(.bottom, 34)
        }
        .vantaBackground().navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .navigationBarTrailing) { AddMenu(composer: $composer) } }
        .navigationDestination(for: Account.self) { AccountDetailView(accountID: $0.id) }
        .navigationDestination(isPresented: $showAccounts) { AccountsView() }
    }

    private var brandHeader: some View {
        HStack(alignment: .center, spacing: 11) {
            MonogramMark()
            VStack(alignment: .leading, spacing: 1) {
                Text("VANTA").font(.caption.weight(.bold)).tracking(2.4)
                Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day())).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("PRIVATE LEDGER").font(.caption2.weight(.bold)).tracking(1.2).foregroundStyle(VantaTheme.gold)
        }.padding(.top, 4)
    }

    private var balanceHero: some View {
        PremiumHeroCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("CONSOLIDATED WEALTH").font(.caption2.weight(.bold)).tracking(1.5).foregroundStyle(.white.opacity(0.58))
                    Spacer()
                    Button { store.updateSettings { $0.amountVisibility.toggle() } } label: {
                        Image(systemName: store.settings.amountVisibility ? "eye" : "eye.slash").font(.subheadline).foregroundStyle(.white.opacity(0.72)).frame(width: 36, height: 36).background(.white.opacity(0.07), in: Circle())
                    }.accessibilityLabel(store.settings.amountVisibility ? "Hide amounts" : "Show amounts")
                }
                Text(store.money(store.totalBalance())).font(.system(size: 39, weight: .medium, design: .serif)).monospacedDigit().minimumScaleFactor(0.55).lineLimit(1)
                PremiumDivider()
                HStack(spacing: 0) {
                    heroMetric("INCOME", store.money(cashFlow.income), VantaTheme.forest)
                    Rectangle().fill(.white.opacity(0.12)).frame(width: 0.7, height: 40).padding(.horizontal, 17)
                    heroMetric("OUTFLOW", store.money(cashFlow.expense), VantaTheme.terracotta)
                    Spacer(minLength: 12)
                    PremiumPill(text: net >= 0 ? "Positive" : "Watch", icon: net >= 0 ? "arrow.up.right" : "arrow.down.right", tint: net >= 0 ? Color(hex: "8FC4AB") : Color(hex: "E0A28F"))
                }
            }
        }
    }

    private func heroMetric(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) { Circle().fill(color).frame(width: 5, height: 5); Text(title).font(.system(size: 9, weight: .bold)).tracking(1).foregroundStyle(.white.opacity(0.48)) }
            Text(value).font(.subheadline.weight(.medium)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    private var quickActions: some View {
        HStack(spacing: 10) {
            quickButton("Expense", "arrow.up.right", VantaTheme.terracotta) { composer = .expense }
            quickButton("Income", "arrow.down.left", VantaTheme.forest) { composer = .income }
            quickButton("Transfer", "arrow.left.arrow.right", VantaTheme.cobalt) { composer = .transfer }
        }
    }

    private func quickButton(_ title: String, _ icon: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.subheadline.weight(.semibold)).foregroundStyle(color).frame(width: 34, height: 34).background(color.opacity(0.1), in: Circle())
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.primary)
            }.frame(maxWidth: .infinity).padding(.vertical, 12).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.045), lineWidth: 0.7))
        }.buttonStyle(.plain)
    }

    @ViewBuilder private var budgetSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Monthly plan")
            if activeBudgets.isEmpty { NavigationLink { BudgetsView() } label: { HStack(spacing: 14) { ZStack { RingProgress(progress: 0.72, lineWidth: 5, tint: VantaTheme.gold); Image(systemName: "plus").font(.caption.bold()) }.frame(width: 46, height: 46); VStack(alignment: .leading, spacing: 3) { Text("Design your monthly plan").font(.subheadline.weight(.semibold)); Text("Set precise limits by category").font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).padding(16).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 20)).overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.primary.opacity(0.05), lineWidth: 0.7)) }.buttonStyle(.plain) }
            else {
                let limit = activeBudgets.reduce(Decimal.zero) { $0 + $1.limitAmount }, spent = activeBudgets.reduce(Decimal.zero) { $0 + store.spent(for: $1) }
                NavigationLink { BudgetsView() } label: { HStack(spacing: 16) { ZStack { RingProgress(progress: decimalDouble(spent / max(limit, 1)), lineWidth: 6, tint: spent > limit ? VantaTheme.terracotta : VantaTheme.gold); Text("\(Int(min(decimalDouble(spent / max(limit, 1)) * 100, 999)))").font(.caption2.bold()) }.frame(width: 54, height: 54); VStack(alignment: .leading, spacing: 5) { Text(store.money(spent)).font(.title3.weight(.medium)); Text("of \(store.money(limit)) allocated").font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }.padding(16).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 20)).overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.primary.opacity(0.05), lineWidth: 0.7)) }.buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private var upcomingSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Coming up")
            if upcoming.isEmpty { HStack { Image(systemName: "calendar.badge.checkmark").foregroundStyle(VantaTheme.gold); Text("Your next 30 days are clear").font(.subheadline.weight(.medium)); Spacer(); Text("No commitments").font(.caption).foregroundStyle(.secondary) }.padding(16).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 18)) }
            else { VStack(spacing: 0) { ForEach(upcoming) { occurrence in if let rule = store.recurringRules.first(where: { $0.id == occurrence.ruleID }) { NavigationLink { RecurringDetailView(ruleID: rule.id) } label: { HStack(spacing: 13) { Text(occurrence.plannedDate.formatted(.dateTime.day())).font(.title3.weight(.medium)).frame(width: 38, height: 42).background(VantaTheme.gold.opacity(0.1), in: RoundedRectangle(cornerRadius: 11)); VStack(alignment: .leading, spacing: 3) { Text(rule.name).font(.subheadline.weight(.medium)); Text(occurrence.plannedDate.formatted(.dateTime.month(.abbreviated))).font(.caption2).foregroundStyle(.secondary) }; Spacer(); Text(store.money(rule.amount)).font(.subheadline.weight(.semibold)).monospacedDigit() }.padding(.vertical, 10) }.buttonStyle(.plain) } } }.padding(.horizontal, 15).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 18)) }
        }
    }

    @ViewBuilder private var recentSummary: some View {
        VStack(alignment: .leading, spacing: 10) { SectionHeader(title: "Recent activity"); if store.transactions.isEmpty { EmptyState(icon: "pencil.and.list.clipboard", title: "A clean page", message: "Record your first expense, income, or transfer.", actionTitle: "Add expense") { composer = .expense } } else { VStack(spacing: 0) { ForEach(store.transactions.prefix(5)) { tx in NavigationLink { TransactionDetailView(transactionID: tx.id) } label: { TransactionRow(transaction: tx) }.buttonStyle(.plain); if tx.id != store.transactions.prefix(5).last?.id { Divider().opacity(0.5).padding(.leading, 58) } } }.padding(.horizontal, 15).padding(.vertical, 5).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 20)).overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.primary.opacity(0.045), lineWidth: 0.7)) } }
    }

    private var insight: some View {
        let net = cashFlow.income - cashFlow.expense
        return HStack(alignment: .top, spacing: 14) { MonogramMark(compact: true); VStack(alignment: .leading, spacing: 5) { Text("VANTA NOTE").font(.caption2.weight(.bold)).tracking(1.2).foregroundStyle(VantaTheme.gold); Text(store.transactions.isEmpty ? "Your private insights will become sharper as the journal grows." : net >= 0 ? "Capital retained this month: \(store.money(net)). Your cash flow remains positive." : "Outflow is \(store.money(-net)) above income. Review the largest category before month end.").font(.subheadline).foregroundStyle(.white.opacity(0.8)).lineSpacing(3) } }.padding(18).background(VantaTheme.ink, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct AccountMiniCard: View {
    @EnvironmentObject private var store: FinanceStore
    let account: Account
    var body: some View { VStack(alignment: .leading, spacing: 22) { HStack { Image(systemName: account.iconName).font(.subheadline).frame(width: 32, height: 32).background(.white.opacity(0.1), in: Circle()); Spacer(); Text(account.currencyCode).font(.caption2.weight(.bold)).tracking(1.1).foregroundStyle(.white.opacity(0.6)) }; VStack(alignment: .leading, spacing: 5) { Text(account.name).font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.7)); Text(store.money(store.balance(for: account), code: account.currencyCode)).font(.title3.weight(.medium)).monospacedDigit() }; Rectangle().fill(VantaTheme.gold.opacity(0.55)).frame(width: 28, height: 1) }.foregroundStyle(.white).padding(18).frame(width: 220, alignment: .leading).background(LinearGradient(colors: [Color(hex: account.colorHex).opacity(0.92), VantaTheme.midnight], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 22, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.1), lineWidth: 0.7)).shadow(color: VantaTheme.midnight.opacity(0.14), radius: 12, y: 7) }
}

struct AccountsView: View {
    @EnvironmentObject private var store: FinanceStore
    @State private var editingAccount: Account?
    @State private var add = false
    @State private var showArchived = false
    @State private var archiveRequested: Account?
    var body: some View {
        List {
            Section { HStack { Text("Total in \(store.settings.baseCurrency)").foregroundStyle(.secondary); Spacer(); Text(store.money(store.totalBalance())).font(.title3.bold()) } }
            ForEach(AccountKind.allCases) { kind in let accounts = store.activeAccounts.filter { $0.kind == kind }; if !accounts.isEmpty { Section(kind.rawValue) { ForEach(accounts) { account in NavigationLink { AccountDetailView(accountID: account.id) } label: { accountRow(account) }.contextMenu { Button("Edit") { editingAccount = account }; Button("Archive", role: .destructive) { archiveRequested = account } } } } } }
            Section { Button { showArchived = true } label: { Label("Archived accounts", systemImage: "archivebox") } }
        }.scrollContentBackground(.hidden).vantaBackground().navigationTitle("Accounts")
        .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button { add = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $add) { AccountEditorView() }.sheet(item: $editingAccount) { AccountEditorView(account: $0) }
        .navigationDestination(isPresented: $showArchived) { ArchivedAccountsView() }
        .confirmationDialog("Archive this account?", isPresented: Binding(get: { archiveRequested != nil }, set: { if !$0 { archiveRequested = nil } }), titleVisibility: .visible) { Button("Archive", role: .destructive) { if let archiveRequested { store.archiveAccount(archiveRequested.id) }; archiveRequested = nil } } message: { Text("Its history stays available, but the account is removed from active totals and new transaction forms.") }
    }
    private func accountRow(_ account: Account) -> some View { HStack { Image(systemName: account.iconName).foregroundStyle(Color(hex: account.colorHex)).frame(width: 30); VStack(alignment: .leading) { Text(account.name); Text(account.currencyCode).font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(store.money(store.balance(for: account), code: account.currencyCode)).fontWeight(.semibold) } }
}

struct AccountDetailView: View {
    @EnvironmentObject private var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
    let accountID: UUID
    @State private var edit = false
    @State private var reconcile = false
    @State private var archiveConfirm = false
    private var account: Account? { store.accounts.first { $0.id == accountID } }
    var body: some View {
        Group { if let account { List { Section { VStack(alignment: .leading, spacing: 6) { Text("Current balance").font(.caption).foregroundStyle(.secondary); Text(store.money(store.balance(for: account), code: account.currencyCode)).font(.largeTitle.bold()); Text("Opening balance: \(store.money(account.openingBalance, code: account.currencyCode))").font(.caption).foregroundStyle(.secondary) }.padding(.vertical, 8) } header: { Text(account.kind.rawValue) }; Section("Activity") { let items = store.transactions(forAccount: accountID); if items.isEmpty { Text("No transactions yet").foregroundStyle(.secondary) } else { ForEach(items) { tx in NavigationLink { TransactionDetailView(transactionID: tx.id) } label: { TransactionRow(transaction: tx) } } } }; Section("Account actions") { Button("Reconcile balance") { reconcile = true }; Button("Edit account") { edit = true }; Button("Archive account", role: .destructive) { archiveConfirm = true } } }.scrollContentBackground(.hidden).vantaBackground().navigationTitle(account.name).sheet(isPresented: $edit) { AccountEditorView(account: account) }.sheet(isPresented: $reconcile) { ReconcileView(account: account) }.confirmationDialog("Archive this account?", isPresented: $archiveConfirm, titleVisibility: .visible) { Button("Archive", role: .destructive) { store.archiveAccount(accountID); dismiss() } } message: { Text("Its transaction history will remain available, but the account will no longer appear in active totals.") } } else { EmptyState(icon: "questionmark.folder", title: "Account unavailable", message: "This account may have been removed.") } }
    }
}

struct AccountEditorView: View {
    @EnvironmentObject private var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
    let existing: Account?
    @State private var name: String
    @State private var kind: AccountKind
    @State private var currency: String
    @State private var balance: String
    @State private var color = "315CFF"
    init(account: Account? = nil) { existing = account; _name = State(initialValue: account?.name ?? ""); _kind = State(initialValue: account?.kind ?? .checking); _currency = State(initialValue: account?.currencyCode ?? "USD"); _balance = State(initialValue: account.map { NSDecimalNumber(decimal: $0.openingBalance).stringValue } ?? "0"); _color = State(initialValue: account?.colorHex ?? "315CFF") }
    var body: some View { NavigationStack { Form { Section("Identity") { TextField("Account name", text: $name); Picker("Type", selection: $kind) { ForEach(AccountKind.allCases) { Label($0.rawValue, systemImage: $0.icon).tag($0) } }; Picker("Currency", selection: $currency) { ForEach(CurrencyCatalog.common, id: \.code) { Text("\($0.code) — \($0.name)").tag($0.code) } } }; Section("Balance") { TextField("Opening balance", text: $balance).keyboardType(.decimalPad) }; Section("Color") { HStack { ForEach(["315CFF", "23856D", "D9684A", "C88A21", "6B68A9"], id: \.self) { value in Button { color = value } label: { Circle().fill(Color(hex: value)).frame(width: 30, height: 30).overlay { if color == value { Image(systemName: "checkmark").foregroundStyle(.white).font(.caption.bold()) } } }.buttonStyle(.plain) } } } }.navigationTitle(existing == nil ? "New account" : "Edit account").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || Decimal.parse(balance) == nil) } } } }
    private func save() { var item = existing ?? Account(name: name, kind: kind, currencyCode: currency, openingBalance: 0, iconName: kind.icon, colorHex: color); item.name = name.trimmingCharacters(in: .whitespaces); item.kind = kind; item.currencyCode = currency; item.openingBalance = store.rounded(Decimal.parse(balance) ?? 0, currencyCode: currency); item.iconName = kind.icon; item.colorHex = color; existing == nil ? store.addAccount(item) : store.updateAccount(item); dismiss() }
}

struct ReconcileView: View {
    @EnvironmentObject private var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
    let account: Account
    @State private var actual = ""
    var difference: Decimal? { Decimal.parse(actual).map { store.balance(for: account) - $0 } }
    var body: some View { NavigationStack { Form { Section { Text("Recorded balance"); Text(store.money(store.balance(for: account), code: account.currencyCode)).font(.title2.bold()); TextField("Actual balance", text: $actual).keyboardType(.decimalPad) } footer: { if let difference { Text("Vanta will create an adjustment of \(store.money(absDecimal(difference), code: account.currencyCode)).") } } }.navigationTitle("Reconcile").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Reconcile") { save() }.disabled(difference == nil || difference == 0) } } } }
    private func save() { guard let actual = Decimal.parse(actual) else { return }; let current = store.balance(for: account), diff = store.rounded(actual - current, currencyCode: account.currencyCode); let kind: TransactionKind = diff >= 0 ? .income : .adjustment; let tx = FinanceTransaction(kind: kind, amount: absDecimal(diff), currencyCode: account.currencyCode, convertedAmount: absDecimal(diff), exchangeRate: 1, date: Date(), note: "Balance reconciliation", accountID: account.id, reconciliationMarker: true); store.addTransaction(tx); dismiss() }
}

struct ArchivedAccountsView: View {
    @EnvironmentObject private var store: FinanceStore
    var body: some View { List { let archived = store.accounts.filter { $0.archivedAt != nil }; if archived.isEmpty { EmptyState(icon: "archivebox", title: "No archived accounts", message: "Accounts you archive will appear here.") } else { ForEach(archived) { account in HStack { Label(account.name, systemImage: account.iconName); Spacer(); Button("Restore") { store.restoreAccount(account.id) } } } } }.navigationTitle("Archived accounts") }
}

func decimalDouble(_ value: Decimal) -> Double { NSDecimalNumber(decimal: value).doubleValue }
func absDecimal(_ value: Decimal) -> Decimal { value < 0 ? -value : value }
