import SwiftUI

struct PlanView: View {
    @EnvironmentObject private var store: FinanceStore
    @Binding var composer: TransactionKind?
    private var pending: [RecurringOccurrence] { store.occurrences.filter { $0.status == .pending }.sorted { $0.plannedDate < $1.plannedDate } }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                HStack { MonogramMark(); VStack(alignment: .leading, spacing: 2) { Text("FORESIGHT").font(.caption2.bold()).tracking(2); Text("Plan with precision").font(.system(.title2, design: .serif).weight(.medium)) }; Spacer(); AddMenu(composer: $composer) }
                PremiumHeroCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("THE MONTH AHEAD").font(.caption2.bold()).tracking(1.5).foregroundStyle(.white.opacity(0.55))
                        Text("Every commitment,\nclearly anticipated.").font(.system(size: 30, weight: .medium, design: .serif)).fixedSize(horizontal: false, vertical: true)
                        PremiumDivider()
                        HStack { planMetric("BUDGETS", "\(store.budgets.count)"); Spacer(); planMetric("GOALS", "\(store.goals.count)"); Spacer(); planMetric("DUE SOON", "\(pending.count)") }
                    }
                }
                VStack(spacing: 11) {
                    NavigationLink { BudgetsView() } label: { planRow("Monthly budgets", "gauge.with.dots.needle.33percent", store.budgets.isEmpty ? "Build your spending framework" : "\(store.budgets.count) active allocations", VantaTheme.cobalt) }.buttonStyle(.plain)
                    NavigationLink { GoalsView() } label: { planRow("Wealth goals", "target", store.goals.isEmpty ? "Define the next milestone" : "\(store.goals.count) goals in progress", VantaTheme.forest) }.buttonStyle(.plain)
                    NavigationLink { RecurringListView() } label: { planRow("Commitments", "repeat", store.recurringRules.isEmpty ? "Curate recurring cash flow" : "\(store.recurringRules.count) recurring rules", VantaTheme.gold) }.buttonStyle(.plain)
                }
                SectionHeader(title: "Thirty-day outlook")
                if pending.isEmpty {
                    HStack(spacing: 14) { Image(systemName: "calendar.badge.checkmark").foregroundStyle(VantaTheme.gold).frame(width: 42, height: 42).background(VantaTheme.gold.opacity(0.1), in: Circle()); VStack(alignment: .leading, spacing: 3) { Text("A clear horizon").font(.subheadline.weight(.semibold)); Text("No scheduled commitments in the next 30 days").font(.caption).foregroundStyle(.secondary) } }.padding(17).frame(maxWidth: .infinity, alignment: .leading).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 20))
                } else {
                    VStack(spacing: 0) {
                        ForEach(pending.prefix(10)) { occurrence in
                            if let rule = store.recurringRules.first(where: { $0.id == occurrence.ruleID }) {
                                NavigationLink { RecurringDetailView(ruleID: rule.id) } label: {
                                    HStack(spacing: 14) {
                                        VStack(spacing: 1) { Text(occurrence.plannedDate.formatted(.dateTime.day())).font(.title3.weight(.medium)); Text(occurrence.plannedDate.formatted(.dateTime.month(.abbreviated))).font(.caption2).foregroundStyle(.secondary) }.frame(width: 45, height: 50).background(VantaTheme.gold.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(rule.name).font(.subheadline.weight(.medium))
                                            Text(rule.cadence.rawValue).font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Text(store.money(rule.amount)).font(.subheadline.weight(.semibold)).monospacedDigit()
                                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 9)
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 20))
                }
            }
            .padding(.horizontal, 18).padding(.bottom, 34)
        }
        .vantaBackground()
        .navigationBarTitleDisplayMode(.inline)
    }
    private func planMetric(_ title: String, _ value: String) -> some View { VStack(alignment: .leading, spacing: 4) { Text(title).font(.system(size: 9, weight: .bold)).tracking(1.2).foregroundStyle(.white.opacity(0.45)); Text(value).font(.title2.weight(.medium)).monospacedDigit() } }
    private func planRow(_ title: String, _ icon: String, _ detail: String, _ color: Color) -> some View { HStack(spacing: 15) { Image(systemName: icon).font(.subheadline.weight(.semibold)).foregroundStyle(color).frame(width: 44, height: 44).background(color.opacity(0.11), in: RoundedRectangle(cornerRadius: 13)); VStack(alignment: .leading, spacing: 4) { Text(title).font(.subheadline.weight(.semibold)); Text(detail).font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }.padding(15).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 19)).overlay(RoundedRectangle(cornerRadius: 19).stroke(Color.primary.opacity(0.05), lineWidth: 0.7)) }
}

struct BudgetsView: View {
    @EnvironmentObject private var store: FinanceStore
    @State private var add = false
    @State private var deleteRequested: Budget?
    private var current: [Budget] { let p = store.financialPeriod(); return store.budgets.filter { $0.periodStart < p.end && $0.periodEnd > p.start } }
    var body: some View { List { if current.isEmpty { EmptyState(icon: "gauge.with.dots.needle.33percent", title: "Plan with intention", message: "Set a monthly limit for a spending category.", actionTitle: "Create budget") { add = true } } else { Section("This financial month") { ForEach(current) { budget in NavigationLink { BudgetDetailView(budgetID: budget.id) } label: { budgetRow(budget) }.swipeActions { Button("Delete", role: .destructive) { deleteRequested = budget } } } }; Section { Button("Copy previous month") { copyPrevious() } } } }.scrollContentBackground(.hidden).vantaBackground().navigationTitle("Budgets").toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button { add = true } label: { Image(systemName: "plus") } } }.sheet(isPresented: $add) { BudgetEditorView() }.confirmationDialog("Delete this budget?", isPresented: Binding(get: { deleteRequested != nil }, set: { if !$0 { deleteRequested = nil } }), titleVisibility: .visible) { Button("Delete budget", role: .destructive) { if let deleteRequested { store.deleteBudget(deleteRequested.id) }; deleteRequested = nil } } message: { Text("Transactions are not changed. Only this monthly limit is removed.") } }
    private func budgetRow(_ budget: Budget) -> some View { let spent = store.spent(for: budget), fraction = min(decimalDouble(spent / max(budget.limitAmount, 1)), 1); return VStack(alignment: .leading, spacing: 8) { HStack { Label(store.categoryName(budget.categoryID), systemImage: "circle.fill"); Spacer(); Text("\(store.money(spent)) / \(store.money(budget.limitAmount))").font(.subheadline.weight(.semibold)) }; ProgressView(value: fraction).tint(spent > budget.limitAmount ? VantaTheme.terracotta : VantaTheme.cobalt); Text(spent > budget.limitAmount ? "Over by \(store.money(spent - budget.limitAmount))" : "\(store.money(budget.limitAmount - spent)) remaining").font(.caption).foregroundStyle(spent > budget.limitAmount ? VantaTheme.terracotta : .secondary) }.padding(.vertical, 5) }
    private func copyPrevious() { let p = store.financialPeriod(), cal = Calendar.current, previous = cal.date(byAdding: .month, value: -1, to: p.start) ?? p.start; let old = store.budgets.filter { Calendar.current.isDate($0.periodStart, equalTo: previous, toGranularity: .month) }; for item in old { store.addBudget(Budget(categoryID: item.categoryID, limitAmount: item.limitAmount, currencyCode: item.currencyCode, periodStart: p.start, periodEnd: p.end, rollover: item.rollover)) }; if old.isEmpty { store.toast = "No previous budgets found" } }
}

struct BudgetDetailView: View {
    @EnvironmentObject private var store: FinanceStore
    let budgetID: UUID
    @State private var edit = false
    @State private var deleteConfirm = false
    @Environment(\.dismiss) private var dismiss
    private var budget: Budget? { store.budgets.first { $0.id == budgetID } }
    var body: some View { Group { if let budget { let spent = store.spent(for: budget); List { Section { VStack(alignment: .leading, spacing: 12) { Text(store.categoryName(budget.categoryID)).font(.title2.bold()); HStack { MetricCard(title: "Spent", value: store.money(spent), detail: "Recorded", tint: VantaTheme.terracotta); MetricCard(title: "Remaining", value: store.money(budget.limitAmount - spent), detail: "Of \(store.money(budget.limitAmount))", tint: VantaTheme.cobalt) }; ProgressView(value: min(decimalDouble(spent / max(budget.limitAmount, 1)), 1)).tint(spent > budget.limitAmount ? VantaTheme.terracotta : VantaTheme.cobalt) }.padding(.vertical) }; Section("Forecast") { let days = max(Calendar.current.dateComponents([.day], from: budget.periodStart, to: Date()).day ?? 1, 1), totalDays = max(Calendar.current.dateComponents([.day], from: budget.periodStart, to: budget.periodEnd).day ?? 1, 1), forecast = spent / Decimal(days) * Decimal(totalDays); LabeledContent("Projected month end", value: store.money(forecast)); LabeledContent("Status", value: forecast > budget.limitAmount ? "Likely over budget" : "On track") }; Section("Transactions") { let txs = store.transactions.filter { $0.categoryID == budget.categoryID && $0.date >= budget.periodStart && $0.date < budget.periodEnd }; if txs.isEmpty { Text("No spending in this period").foregroundStyle(.secondary) } else { ForEach(txs) { tx in NavigationLink { TransactionDetailView(transactionID: tx.id) } label: { TransactionRow(transaction: tx) } } } }; Section { Button("Edit budget") { edit = true }; Button("Delete budget", role: .destructive) { deleteConfirm = true } } }.navigationTitle("Budget details").sheet(isPresented: $edit) { BudgetEditorView(existing: budget) }.confirmationDialog("Delete this budget?", isPresented: $deleteConfirm, titleVisibility: .visible) { Button("Delete budget", role: .destructive) { store.deleteBudget(budgetID); dismiss() } } message: { Text("Transactions remain intact. The monthly limit and forecast are removed.") } } } }
}

struct BudgetEditorView: View {
    @EnvironmentObject private var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
    let existing: Budget?
    @State private var categoryID: UUID?
    @State private var limit: String
    @State private var rollover: Bool
    init(existing: Budget? = nil) { self.existing = existing; _categoryID = State(initialValue: existing?.categoryID); _limit = State(initialValue: existing.map { NSDecimalNumber(decimal: $0.limitAmount).stringValue } ?? ""); _rollover = State(initialValue: existing?.rollover ?? false) }
    var body: some View { NavigationStack { Form { Section("Category") { Picker("Expense category", selection: $categoryID) { Text("Select category").tag(nil as UUID?); ForEach(store.categories.filter { $0.kind == .expense && $0.archivedAt == nil }) { Text($0.name).tag($0.id as UUID?) } } }; Section("Monthly limit") { TextField("Amount", text: $limit).keyboardType(.decimalPad); Toggle("Roll unused amount forward", isOn: $rollover) } }.navigationTitle(existing == nil ? "New budget" : "Edit budget").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(categoryID == nil || (Decimal.parse(limit) ?? 0) <= 0) } } } }
    private func save() { guard let categoryID, let value = Decimal.parse(limit) else { return }; let p = store.financialPeriod(); var item = existing ?? Budget(categoryID: categoryID, limitAmount: value, currencyCode: store.settings.baseCurrency, periodStart: p.start, periodEnd: p.end); item.categoryID = categoryID; item.limitAmount = value; item.rollover = rollover; store.addBudget(item); dismiss() }
}

struct GoalsView: View {
    @EnvironmentObject private var store: FinanceStore
    @State private var add = false
    @State private var showArchived = false
    var body: some View { List { if store.goals.isEmpty { EmptyState(icon: "target", title: "Give savings a purpose", message: "Create a goal and track every contribution.", actionTitle: "Create goal") { add = true } } else { ForEach(store.goals) { goal in NavigationLink { GoalDetailView(goalID: goal.id) } label: { goalRow(goal) } } }; Section { Button { showArchived = true } label: { Label("Archived goals", systemImage: "archivebox") } } }.scrollContentBackground(.hidden).vantaBackground().navigationTitle("Savings goals").toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button { add = true } label: { Image(systemName: "plus") } } }.sheet(isPresented: $add) { GoalEditorView() }.navigationDestination(isPresented: $showArchived) { ArchivedGoalsView() } }
    private func goalRow(_ goal: SavingsGoal) -> some View { VStack(alignment: .leading, spacing: 8) { HStack { Image(systemName: goal.iconName).foregroundStyle(Color(hex: goal.colorHex)); Text(goal.name).font(.headline); Spacer(); Text("\(Int(min(decimalDouble(goal.currentAmount / max(goal.targetAmount, 1)) * 100, 100)))%").font(.caption.bold()) }; ProgressView(value: min(decimalDouble(goal.currentAmount / max(goal.targetAmount, 1)), 1)).tint(Color(hex: goal.colorHex)); HStack { Text(store.money(goal.currentAmount, code: goal.currencyCode)); Spacer(); Text("of \(store.money(goal.targetAmount, code: goal.currencyCode))").foregroundStyle(.secondary) }.font(.caption) }.padding(.vertical, 6) }
}

struct GoalDetailView: View {
    @EnvironmentObject private var store: FinanceStore
    let goalID: UUID
    @State private var edit = false
    @State private var contribute = false
    @State private var archiveConfirm = false
    @State private var deleteConfirm = false
    @Environment(\.dismiss) private var dismiss
    private var goal: SavingsGoal? { store.goals.first { $0.id == goalID } }
    var body: some View {
        Group {
            if let goal {
                List {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: goal.iconName).font(.largeTitle).foregroundStyle(Color(hex: goal.colorHex))
                            Text(goal.name).font(.title.bold())
                            Text(store.money(goal.currentAmount, code: goal.currencyCode)).font(.title2.bold())
                            ProgressView(value: min(decimalDouble(goal.currentAmount / max(goal.targetAmount, 1)), 1)).tint(Color(hex: goal.colorHex))
                            Text("Goal: \(store.money(goal.targetAmount, code: goal.currencyCode))").font(.caption).foregroundStyle(.secondary)
                            if let targetDate = goal.targetDate {
                                Text("Target date: \(targetDate.formatted(date: .long, time: .omitted))").font(.caption).foregroundStyle(.secondary)
                                Text("Suggested monthly contribution: \(store.money(suggestedContribution(goal, targetDate: targetDate), code: goal.currencyCode))").font(.caption.weight(.semibold)).foregroundStyle(VantaTheme.forest)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical)
                    }
                    Section {
                        Button("Add or withdraw funds") { contribute = true }.buttonStyle(.borderedProminent)
                        Button("Edit goal") { edit = true }
                        Button("Archive goal") { archiveConfirm = true }
                        Button("Delete goal and history", role: .destructive) { deleteConfirm = true }
                    }
                    Section("Contribution history") {
                        let entries = store.snapshot.contributions.filter { $0.goalID == goalID }.sorted { $0.date > $1.date }
                        if entries.isEmpty {
                            Text("No contributions yet").foregroundStyle(.secondary)
                        } else {
                            ForEach(entries) { item in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(item.note.isEmpty ? "Contribution" : item.note)
                                        Text(item.date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(store.money(item.amount, code: goal.currencyCode, signed: true)).foregroundStyle(item.amount >= 0 ? VantaTheme.forest : VantaTheme.terracotta)
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Goal")
                .sheet(isPresented: $edit) { GoalEditorView(existing: goal) }
                .sheet(isPresented: $contribute) { GoalContributionView(goal: goal) }
                .confirmationDialog("Archive this goal?", isPresented: $archiveConfirm, titleVisibility: .visible) { Button("Archive") { store.archiveGoal(goalID); dismiss() } } message: { Text("The goal and contribution history remain stored and can be reviewed later.") }
                .alert("Delete goal permanently?", isPresented: $deleteConfirm) { Button("Delete", role: .destructive) { store.deleteGoal(goalID); dismiss() }; Button("Cancel", role: .cancel) {} } message: { Text("This deletes the goal and its contribution history. Account balances and transactions are not changed.") }
            }
        }
    }
    private func suggestedContribution(_ goal: SavingsGoal, targetDate: Date) -> Decimal { let months = max(Calendar.current.dateComponents([.month], from: Date(), to: targetDate).month ?? 1, 1); return max(goal.targetAmount - goal.currentAmount, 0) / Decimal(months) }
}

struct ArchivedGoalsView: View {
    @EnvironmentObject private var store: FinanceStore
    var body: some View { List { let items = store.snapshot.goals.filter { $0.archivedAt != nil }; if items.isEmpty { EmptyState(icon: "archivebox", title: "No archived goals", message: "Completed or paused goals can be kept here.") } else { ForEach(items) { goal in HStack { Label(goal.name, systemImage: goal.iconName); Spacer(); Button("Restore") { var value = goal; value.archivedAt = nil; store.updateGoal(value) } } } } }.navigationTitle("Archived goals") }
}

struct GoalEditorView: View {
    @EnvironmentObject private var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
    let existing: SavingsGoal?
    @State private var name: String
    @State private var target: String
    @State private var hasDeadline: Bool
    @State private var deadline: Date
    @State private var accountID: UUID?
    init(existing: SavingsGoal? = nil) { self.existing = existing; _name = State(initialValue: existing?.name ?? ""); _target = State(initialValue: existing.map { NSDecimalNumber(decimal: $0.targetAmount).stringValue } ?? ""); _hasDeadline = State(initialValue: existing?.targetDate != nil); _deadline = State(initialValue: existing?.targetDate ?? Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date().addingTimeInterval(15_552_000)); _accountID = State(initialValue: existing?.accountID) }
    var body: some View { NavigationStack { Form { Section("Goal") { TextField("Name", text: $name); TextField("Target amount", text: $target).keyboardType(.decimalPad); Picker("Linked account", selection: $accountID) { Text("None").tag(nil as UUID?); ForEach(store.activeAccounts) { Text($0.name).tag($0.id as UUID?) } } }; Section("Deadline") { Toggle("Set target date", isOn: $hasDeadline); if hasDeadline { DatePicker("Target date", selection: $deadline, in: Date()..., displayedComponents: .date) } } }.navigationTitle(existing == nil ? "New goal" : "Edit goal").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || (Decimal.parse(target) ?? 0) <= 0) } } } }
    private func save() { guard let amount = Decimal.parse(target) else { return }; var item = existing ?? SavingsGoal(name: name, targetAmount: amount, currentAmount: 0, currencyCode: store.settings.baseCurrency, iconName: "target", colorHex: "23856D"); item.name = name; item.targetAmount = amount; item.targetDate = hasDeadline ? deadline : nil; item.accountID = accountID; existing == nil ? store.addGoal(item) : store.updateGoal(item); dismiss() }
}

struct GoalContributionView: View {
    @EnvironmentObject private var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
    let goal: SavingsGoal
    @State private var amount = ""
    @State private var withdrawing = false
    @State private var accountID: UUID?
    @State private var note = ""
    var body: some View { NavigationStack { Form { Picker("Action", selection: $withdrawing) { Text("Add funds").tag(false); Text("Withdraw").tag(true) }.pickerStyle(.segmented); TextField("Amount", text: $amount).keyboardType(.decimalPad); if withdrawing && (Decimal.parse(amount) ?? 0) > goal.currentAmount { Text("You cannot withdraw more than the saved amount.").font(.footnote).foregroundStyle(VantaTheme.terracotta) }; Picker("Account reference", selection: $accountID) { Text("No account reference").tag(nil as UUID?); ForEach(store.activeAccounts) { Text($0.name).tag($0.id as UUID?) } }; Text("The account is stored as a reference for your history. This action does not create a bank transaction or change its balance.").font(.footnote).foregroundStyle(.secondary); TextField("Note", text: $note) }.navigationTitle("Update goal").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { if let value = Decimal.parse(amount), store.contribute(goalID: goal.id, amount: withdrawing ? -value : value, accountID: accountID, note: note) { dismiss() } }.disabled((Decimal.parse(amount) ?? 0) <= 0 || (withdrawing && (Decimal.parse(amount) ?? 0) > goal.currentAmount)) } } } }
}

struct RecurringListView: View {
    @EnvironmentObject private var store: FinanceStore
    @State private var add = false
    var body: some View { List { if store.recurringRules.isEmpty { EmptyState(icon: "repeat", title: "Make routine visible", message: "Schedule bills, subscriptions, and regular income. Vanta will always ask before posting them.", actionTitle: "Create recurring item") { add = true } } else { ForEach(store.recurringRules) { rule in NavigationLink { RecurringDetailView(ruleID: rule.id) } label: { HStack { Image(systemName: rule.kind.icon).foregroundStyle(rule.isActive ? (rule.kind == .income ? VantaTheme.forest : VantaTheme.terracotta) : .secondary); VStack(alignment: .leading) { HStack { Text(rule.name); if !rule.isActive { Text("PAUSED").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary) } }; Text(rule.isActive ? "\(rule.cadence.rawValue) · next \(rule.nextOccurrence.formatted(date: .abbreviated, time: .omitted))" : "Schedule paused").font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(store.money(rule.amount)).fontWeight(.semibold) } } } } }.navigationTitle("Recurring").toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button { add = true } label: { Image(systemName: "plus") } } }.sheet(isPresented: $add) { RecurringEditorView() } }
}

struct RecurringDetailView: View {
    @EnvironmentObject private var store: FinanceStore
    let ruleID: UUID
    @State private var edit = false
    @State private var deleteConfirm = false
    @Environment(\.dismiss) private var dismiss
    private var rule: RecurringRule? { store.recurringRules.first { $0.id == ruleID } }
    var body: some View { Group { if let rule { List { Section { LabeledContent("Status", value: rule.isActive ? "Active" : "Paused"); LabeledContent("Amount", value: store.money(rule.amount)); LabeledContent("Account", value: store.accountName(rule.accountID)); LabeledContent("Category", value: store.categoryName(rule.categoryID)); LabeledContent("Frequency", value: recurrenceText(rule)); if rule.isActive { LabeledContent("Next", value: rule.nextOccurrence.formatted(date: .long, time: .shortened)) }; if let endDate = rule.endDate { LabeledContent("Ends", value: endDate.formatted(date: .long, time: .omitted)) }; LabeledContent("Reminder", value: reminderText(rule.reminderOffset)) }; Section("Occurrences") { let items = store.occurrences.filter { $0.ruleID == ruleID }.sorted { $0.plannedDate < $1.plannedDate }; if items.isEmpty { Text("No occurrences yet").foregroundStyle(.secondary) } else { ForEach(items) { occurrence in VStack(alignment: .leading, spacing: 8) { HStack { Text(occurrence.plannedDate.formatted(date: .abbreviated, time: .shortened)); Spacer(); Text(occurrence.status.rawValue.capitalized).font(.caption).foregroundStyle(.secondary) }; if occurrence.status == .pending { HStack { Button("Post now") { store.resolveOccurrence(occurrence, complete: true) }.buttonStyle(.borderedProminent); Button("Skip") { store.resolveOccurrence(occurrence, complete: false) }.buttonStyle(.bordered) } } }.padding(.vertical, 4) } } }; Section { Button("Edit schedule") { edit = true }; Button(rule.isActive ? "Pause schedule" : "Resume schedule") { store.setRecurringActive(ruleID, active: !rule.isActive) }; Button("Delete schedule", role: .destructive) { deleteConfirm = true } } }.navigationTitle(rule.name).sheet(isPresented: $edit) { RecurringEditorView(existing: rule) }.confirmationDialog("Delete this recurring schedule?", isPresented: $deleteConfirm, titleVisibility: .visible) { Button("Delete schedule", role: .destructive) { store.deleteRecurring(ruleID); dismiss() } } message: { Text("Generated transactions stay in your journal. Pending occurrences are removed.") } } } }
    private func recurrenceText(_ rule: RecurringRule) -> String { rule.interval == 1 ? rule.cadence.rawValue : "Every \(rule.interval) \(rule.cadence.rawValue.lowercased()) periods" }
    private func reminderText(_ minutes: Int?) -> String { switch minutes { case 0: return "At due time"; case 60: return "1 hour before"; case 1_440: return "1 day before"; case 10_080: return "1 week before"; default: return "Off" } }
}

struct RecurringEditorView: View {
    @EnvironmentObject private var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
    let existing: RecurringRule?
    @State private var name: String
    @State private var kind: TransactionKind
    @State private var amount: String
    @State private var accountID: UUID?
    @State private var categoryID: UUID?
    @State private var cadence: RecurrenceCadence
    @State private var interval: Int
    @State private var start: Date
    @State private var hasEndDate: Bool
    @State private var endDate: Date
    @State private var reminderOffset: Int?
    init(existing: RecurringRule? = nil) { self.existing = existing; _name = State(initialValue: existing?.name ?? ""); _kind = State(initialValue: existing?.kind ?? .expense); _amount = State(initialValue: existing.map { NSDecimalNumber(decimal: $0.amount).stringValue } ?? ""); _accountID = State(initialValue: existing?.accountID); _categoryID = State(initialValue: existing?.categoryID); _cadence = State(initialValue: existing?.cadence ?? .monthly); _interval = State(initialValue: existing?.interval ?? 1); _start = State(initialValue: existing?.startDate ?? Date()); _hasEndDate = State(initialValue: existing?.endDate != nil); _endDate = State(initialValue: existing?.endDate ?? Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date().addingTimeInterval(31_536_000)); _reminderOffset = State(initialValue: existing?.reminderOffset) }
    var body: some View { NavigationStack { Form { Section("Template") { TextField("Name", text: $name); Picker("Type", selection: $kind) { Text("Expense").tag(TransactionKind.expense); Text("Income").tag(TransactionKind.income) }.pickerStyle(.segmented); TextField("Amount", text: $amount).keyboardType(.decimalPad); Picker("Account", selection: $accountID) { Text("Select account").tag(nil as UUID?); ForEach(store.activeAccounts) { Text($0.name).tag($0.id as UUID?) } }; Picker("Category", selection: $categoryID) { Text("Select category").tag(nil as UUID?); ForEach(store.categories.filter { $0.kind == (kind == .income ? .income : .expense) && $0.archivedAt == nil }) { Text($0.name).tag($0.id as UUID?) } } }; Section("Schedule") { Picker("Frequency", selection: $cadence) { ForEach(RecurrenceCadence.allCases) { Text($0.rawValue).tag($0) } }; Stepper("Every \(interval) \(cadence.rawValue.lowercased()) period\(interval == 1 ? "" : "s")", value: $interval, in: 1...12); DatePicker("Starts", selection: $start, displayedComponents: [.date, .hourAndMinute]); Toggle("Set end date", isOn: $hasEndDate); if hasEndDate { DatePicker("Ends", selection: $endDate, in: start..., displayedComponents: .date) } }; Section("Reminder") { Picker("Alert", selection: $reminderOffset) { Text("Off").tag(nil as Int?); Text("At due time").tag(0 as Int?); Text("1 hour before").tag(60 as Int?); Text("1 day before").tag(1_440 as Int?); Text("1 week before").tag(10_080 as Int?) }; if reminderOffset != nil && !store.settings.remindersEnabled { Text("Enable local reminders in More › Reminders to receive this alert.").font(.footnote).foregroundStyle(VantaTheme.amber) } }; Section { Text("Vanta creates a pending occurrence and never changes your balance until you confirm it.").font(.footnote).foregroundStyle(.secondary) } }.navigationTitle(existing == nil ? "New recurring item" : "Edit recurring item").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || accountID == nil || categoryID == nil || (Decimal.parse(amount) ?? 0) <= 0 || (hasEndDate && endDate < start)) } }.onChange(of: start) { value in if endDate < value { endDate = value } } } }
    private func save() { guard let accountID, let value = Decimal.parse(amount) else { return }; var item = existing ?? RecurringRule(name: name, kind: kind, amount: value, accountID: accountID, categoryID: categoryID, cadence: cadence, interval: interval, startDate: start, nextOccurrence: start); item.name = name.trimmingCharacters(in: .whitespacesAndNewlines); item.kind = kind; item.amount = value; item.accountID = accountID; item.categoryID = categoryID; item.cadence = cadence; item.interval = interval; item.startDate = start; item.endDate = hasEndDate ? endDate : nil; item.reminderOffset = reminderOffset; item.nextOccurrence = start; if existing == nil { store.addRecurring(item) } else { store.updateRecurring(item) }; dismiss() }
}
