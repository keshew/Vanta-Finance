import Foundation
import CoreData
import SwiftUI
import UserNotifications

@MainActor
final class FinanceStore: ObservableObject {
    @Published private(set) var snapshot = AppSnapshot()
    @Published var lastError: String?
    @Published var toast: String?
    @Published var isUnlocked = false
    @Published private(set) var isReady = false
    @Published private(set) var pendingTransactionUndo: FinanceTransaction?

    private let container: NSPersistentContainer
    private var saveTask: Task<Void, Never>?

    init(inMemory: Bool = false) {
        let model = NSManagedObjectModel()
        let state = NSEntityDescription()
        state.name = "AppState"
        state.managedObjectClassName = "NSManagedObject"
        let key = NSAttributeDescription(); key.name = "key"; key.attributeType = .stringAttributeType; key.isOptional = false
        let payload = NSAttributeDescription(); payload.name = "payload"; payload.attributeType = .binaryDataAttributeType; payload.isOptional = false
        let updatedAt = NSAttributeDescription(); updatedAt.name = "updatedAt"; updatedAt.attributeType = .dateAttributeType; updatedAt.isOptional = false
        state.properties = [key, payload, updatedAt]
        state.uniquenessConstraints = [["key"]]
        model.entities = [state]

        container = NSPersistentContainer(name: "VantaFinance", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        description.type = inMemory ? NSInMemoryStoreType : NSSQLiteStoreType
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        if !inMemory {
            let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            description.url = folder.appendingPathComponent("VantaFinance.sqlite")
        }
        container.persistentStoreDescriptions = [description]
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.loadPersistentStores { [weak self] _, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.lastError = "Local storage could not be opened. \(error.localizedDescription)"
                } else {
                    self.load()
                    self.generatePendingOccurrences()
                    self.persistNow()
                    self.rescheduleNotifications()
                }
                self.isReady = true
            }
        }
    }

    var settings: AppSettings { snapshot.settings }
    var accounts: [Account] { snapshot.accounts.sorted { $0.sortOrder < $1.sortOrder } }
    var activeAccounts: [Account] { accounts.filter { $0.archivedAt == nil } }
    var categories: [FinanceCategory] { snapshot.categories.sorted { $0.sortOrder < $1.sortOrder } }
    var transactions: [FinanceTransaction] { snapshot.transactions.sorted { $0.date > $1.date } }
    var tags: [FinanceTag] { snapshot.tags.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } }
    var budgets: [Budget] { snapshot.budgets }
    var goals: [SavingsGoal] { snapshot.goals.filter { $0.archivedAt == nil } }
    var recurringRules: [RecurringRule] { snapshot.recurringRules }
    var occurrences: [RecurringOccurrence] { snapshot.occurrences }
    var exchangeRates: [ManualExchangeRate] { snapshot.exchangeRates.sorted { $0.effectiveDate > $1.effectiveDate } }
    var databaseSize: Int64 {
        guard let url = container.persistentStoreDescriptions.first?.url else { return 0 }
        return [url.path, url.path + "-wal", url.path + "-shm"].reduce(0) { total, path in
            total + ((try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value ?? 0)
        }
    }

    func integrityIssues() -> [String] {
        let accountIDs = Set(snapshot.accounts.map(\.id)), categoryIDs = Set(snapshot.categories.map(\.id)), goalIDs = Set(snapshot.goals.map(\.id)), ruleIDs = Set(snapshot.recurringRules.map(\.id))
        var issues: [String] = []
        for transaction in snapshot.transactions {
            if !accountIDs.contains(transaction.accountID) { issues.append("A transaction references a missing source account.") }
            if transaction.destinationAccountID.map(accountIDs.contains) == false { issues.append("A transfer references a missing destination account.") }
            if transaction.categoryID.map(categoryIDs.contains) == false { issues.append("A transaction references a missing category.") }
        }
        if snapshot.budgets.contains(where: { !categoryIDs.contains($0.categoryID) }) { issues.append("A budget references a missing category.") }
        if snapshot.contributions.contains(where: { !goalIDs.contains($0.goalID) }) { issues.append("A contribution references a missing goal.") }
        if snapshot.occurrences.contains(where: { !ruleIDs.contains($0.ruleID) }) { issues.append("An occurrence references a missing schedule.") }
        return Array(Set(issues)).sorted()
    }

    func completeOnboarding(currency: String, monday: Bool, monthDay: Int, accountName: String, kind: AccountKind, balance: Decimal, selectedCategories: [FinanceCategory]) {
        snapshot.settings.baseCurrency = currency
        snapshot.settings.weekStartsMonday = monday
        snapshot.settings.financialMonthStartDay = monthDay
        snapshot.settings.onboardingComplete = true
        snapshot.categories = selectedCategories
        snapshot.accounts = [Account(name: accountName, kind: kind, currencyCode: currency, openingBalance: balance, iconName: kind.icon, colorHex: "315CFF")]
        changed("Welcome to Vanta")
    }

    func updateSettings(_ block: (inout AppSettings) -> Void) { block(&snapshot.settings); changed(); rescheduleNotifications() }

    func addAccount(_ account: Account) { var value = account; value.sortOrder = snapshot.accounts.count; snapshot.accounts.append(value); changed("Account saved") }
    func updateAccount(_ account: Account) { replace(&snapshot.accounts, account); changed("Account updated") }
    func archiveAccount(_ id: UUID) { guard let i = snapshot.accounts.firstIndex(where: { $0.id == id }) else { return }; snapshot.accounts[i].archivedAt = Date(); changed("Account archived") }
    func restoreAccount(_ id: UUID) { guard let i = snapshot.accounts.firstIndex(where: { $0.id == id }) else { return }; snapshot.accounts[i].archivedAt = nil; changed("Account restored") }

    func balance(for account: Account) -> Decimal {
        snapshot.transactions.reduce(account.openingBalance) { total, tx in
            if tx.kind == .transfer {
                if tx.accountID == account.id { return total - tx.amount }
                if tx.destinationAccountID == account.id { return total + tx.convertedAmount }
            } else if tx.accountID == account.id {
                if tx.kind == .income { return total + tx.amount }
                return total - tx.amount
            }
            return total
        }
    }

    func totalBalance() -> Decimal { activeAccounts.reduce(0) { $0 + converted(balance(for: $1), from: $1.currencyCode) } }

    func addTransaction(_ tx: FinanceTransaction) { snapshot.transactions.append(tx); changed("Transaction saved") }
    func updateTransaction(_ tx: FinanceTransaction) { var value = tx; value.updatedAt = Date(); replace(&snapshot.transactions, value); changed("Transaction updated") }
    @discardableResult func deleteTransaction(_ id: UUID) -> FinanceTransaction? {
        guard let index = snapshot.transactions.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = snapshot.transactions.remove(at: index)
        pendingTransactionUndo = removed
        changed("Transaction deleted")
        return removed
    }
    func restoreTransaction(_ transaction: FinanceTransaction) {
        guard !snapshot.transactions.contains(where: { $0.id == transaction.id }) else { return }
        snapshot.transactions.append(transaction)
        pendingTransactionUndo = nil
        changed("Transaction restored")
    }
    func clearTransactionUndo() { pendingTransactionUndo = nil }

    func addCategory(_ category: FinanceCategory) { var value = category; value.sortOrder = snapshot.categories.count; snapshot.categories.append(value); changed("Category saved") }
    func updateCategory(_ category: FinanceCategory) { replace(&snapshot.categories, category); changed("Category updated") }
    func archiveCategory(_ id: UUID) { guard let i = snapshot.categories.firstIndex(where: { $0.id == id }) else { return }; snapshot.categories[i].archivedAt = Date(); changed("Category archived") }
    func restoreCategory(_ id: UUID) { guard let i = snapshot.categories.firstIndex(where: { $0.id == id }) else { return }; snapshot.categories[i].archivedAt = nil; changed("Category restored") }
    func addTag(_ tag: FinanceTag) { snapshot.tags.append(tag); changed("Tag saved") }
    func updateTag(_ tag: FinanceTag) { replace(&snapshot.tags, tag); changed("Tag updated") }
    func deleteTag(_ id: UUID) { snapshot.tags.removeAll { $0.id == id }; snapshot.transactions.indices.forEach { snapshot.transactions[$0].tagIDs.removeAll { $0 == id } }; changed("Tag deleted") }

    func addBudget(_ budget: Budget) {
        snapshot.budgets.removeAll { $0.id != budget.id && $0.categoryID == budget.categoryID && $0.periodStart < budget.periodEnd && $0.periodEnd > budget.periodStart }
        snapshot.budgets.removeAll { $0.id == budget.id }
        snapshot.budgets.append(budget); changed("Budget saved")
    }
    func deleteBudget(_ id: UUID) { snapshot.budgets.removeAll { $0.id == id }; changed("Budget removed") }
    func spent(for budget: Budget) -> Decimal { snapshot.transactions.filter { $0.kind == .expense && $0.categoryID == budget.categoryID && $0.date >= budget.periodStart && $0.date < budget.periodEnd }.reduce(0) { $0 + converted($1.amount, from: $1.currencyCode) } }

    func addGoal(_ goal: SavingsGoal) { snapshot.goals.append(goal); changed("Goal saved") }
    func updateGoal(_ goal: SavingsGoal) { replace(&snapshot.goals, goal); changed("Goal updated") }
    func archiveGoal(_ id: UUID) { guard let index = snapshot.goals.firstIndex(where: { $0.id == id }) else { return }; snapshot.goals[index].archivedAt = Date(); changed("Goal archived") }
    func deleteGoal(_ id: UUID) { snapshot.goals.removeAll { $0.id == id }; snapshot.contributions.removeAll { $0.goalID == id }; changed("Goal deleted") }
    @discardableResult func contribute(goalID: UUID, amount: Decimal, accountID: UUID?, note: String) -> Bool {
        guard let index = snapshot.goals.firstIndex(where: { $0.id == goalID }), snapshot.goals[index].currentAmount + amount >= 0 else { return false }
        snapshot.goals[index].currentAmount += amount
        snapshot.contributions.append(GoalContribution(goalID: goalID, amount: amount, accountID: accountID, note: note))
        changed("Goal updated")
        return true
    }

    func addRecurring(_ rule: RecurringRule) { snapshot.recurringRules.append(rule); generatePendingOccurrences(); changed("Recurring item saved"); rescheduleNotifications() }
    func updateRecurring(_ rule: RecurringRule) {
        snapshot.occurrences.removeAll { $0.ruleID == rule.id && $0.status == .pending }
        replace(&snapshot.recurringRules, rule)
        generatePendingOccurrences()
        changed("Recurring item updated")
        rescheduleNotifications()
    }
    func setRecurringActive(_ id: UUID, active: Bool) {
        guard let index = snapshot.recurringRules.firstIndex(where: { $0.id == id }) else { return }
        snapshot.recurringRules[index].isActive = active
        if active { snapshot.recurringRules[index].nextOccurrence = max(snapshot.recurringRules[index].startDate, Date()) }
        else { snapshot.occurrences.removeAll { $0.ruleID == id && $0.status == .pending } }
        generatePendingOccurrences(); changed(active ? "Schedule resumed" : "Schedule paused"); rescheduleNotifications()
    }
    func deleteRecurring(_ id: UUID) {
        snapshot.recurringRules.removeAll { $0.id == id }
        snapshot.occurrences.removeAll { $0.ruleID == id }
        changed("Recurring schedule deleted")
        rescheduleNotifications()
    }
    func resolveOccurrence(_ occurrence: RecurringOccurrence, complete: Bool) {
        guard let oi = snapshot.occurrences.firstIndex(where: { $0.id == occurrence.id }), let rule = snapshot.recurringRules.first(where: { $0.id == occurrence.ruleID }) else { return }
        if complete {
            let account = snapshot.accounts.first(where: { $0.id == rule.accountID })
            let tx = FinanceTransaction(kind: rule.kind, amount: rule.amount, currencyCode: account?.currencyCode ?? settings.baseCurrency, convertedAmount: rule.amount, exchangeRate: 1, date: occurrence.plannedDate, note: rule.name, accountID: rule.accountID, categoryID: rule.categoryID, recurringRuleID: rule.id)
            snapshot.transactions.append(tx); snapshot.occurrences[oi].generatedTransactionID = tx.id; snapshot.occurrences[oi].status = .completed
        } else { snapshot.occurrences[oi].status = .skipped }
        changed(complete ? "Transaction created" : "Occurrence skipped")
        rescheduleNotifications()
    }

    func addRate(_ rate: ManualExchangeRate) { snapshot.exchangeRates.append(rate); changed("Rate saved") }
    func deleteRate(_ id: UUID) { snapshot.exchangeRates.removeAll { $0.id == id }; changed("Rate deleted") }
    func converted(_ amount: Decimal, from code: String) -> Decimal {
        guard code != settings.baseCurrency else { return amount }
        if let direct = exchangeRates.first(where: { $0.fromCurrency == code && $0.toCurrency == settings.baseCurrency }) { return amount * direct.rate }
        if let inverse = exchangeRates.first(where: { $0.fromCurrency == settings.baseCurrency && $0.toCurrency == code }), inverse.rate != 0 { return amount / inverse.rate }
        return amount
    }
    func rounded(_ amount: Decimal, currencyCode: String) -> Decimal {
        var input = amount, output = Decimal()
        NSDecimalRound(&output, &input, currencyCode == "JPY" ? 0 : 2, .bankers)
        return output
    }

    func categoryName(_ id: UUID?) -> String { categories.first(where: { $0.id == id })?.name ?? "Uncategorized" }
    func accountName(_ id: UUID?) -> String { accounts.first(where: { $0.id == id })?.name ?? "Unknown account" }
    func transactions(forAccount accountID: UUID) -> [FinanceTransaction] { transactions.filter { $0.accountID == accountID || $0.destinationAccountID == accountID } }
    func transactions(forCategory categoryID: UUID) -> [FinanceTransaction] { transactions.filter { $0.categoryID == categoryID } }

    func financialPeriod(containing date: Date = Date()) -> DateInterval {
        let calendar = Calendar.autoupdatingCurrent
        let day = min(max(settings.financialMonthStartDay, 1), 28)
        var components = calendar.dateComponents([.year, .month], from: date); components.day = day; components.hour = 0
        var start = calendar.date(from: components) ?? date
        if start > date { start = calendar.date(byAdding: .month, value: -1, to: start) ?? start }
        return DateInterval(start: start, end: calendar.date(byAdding: .month, value: 1, to: start) ?? date)
    }

    func monthIncomeExpense() -> (income: Decimal, expense: Decimal) {
        let period = financialPeriod()
        return snapshot.transactions.filter { period.contains($0.date) }.reduce((0, 0)) { result, tx in
            if tx.kind == .income { return (result.0 + converted(tx.amount, from: tx.currencyCode), result.1) }
            if tx.kind == .expense { return (result.0, result.1 + converted(tx.amount, from: tx.currencyCode)) }
            return result
        }
    }

    func exportJSON() throws -> Data { try encoder().encode(snapshot) }
    func importJSON(_ data: Data) throws {
        let incoming = try decoder().decode(AppSnapshot.self, from: data)
        guard incoming.schemaVersion <= 1 else { throw ImportError.unsupportedVersion }
        try validate(incoming)
        snapshot = incoming
        generatePendingOccurrences()
        changed("Backup restored")
        rescheduleNotifications()
    }
    func importTransactions(_ transactions: [FinanceTransaction]) throws {
        let accountIDs = Set(snapshot.accounts.map(\.id))
        let categoryIDs = Set(snapshot.categories.map(\.id))
        guard transactions.allSatisfy({ transaction in
            accountIDs.contains(transaction.accountID)
                && transaction.destinationAccountID.map(accountIDs.contains) != false
                && transaction.categoryID.map(categoryIDs.contains) != false
                && transaction.amount >= 0
        }) else { throw ImportError.invalidReferences }
        var known = Set(snapshot.transactions.map(\.id))
        let unique = transactions.filter { known.insert($0.id).inserted }
        snapshot.transactions.append(contentsOf: unique)
        changed("Transactions imported")
    }
    func csvData() -> Data {
        var rows = ["id,date,type,amount,currency,account,destination,category,note"]
        for tx in transactions {
            let values = [tx.id.uuidString, ISO8601DateFormatter().string(from: tx.date), tx.kind.rawValue, NSDecimalNumber(decimal: tx.amount).stringValue, tx.currencyCode, accountName(tx.accountID), accountName(tx.destinationAccountID), categoryName(tx.categoryID), tx.note].map(csvEscape)
            rows.append(values.joined(separator: ","))
        }
        return rows.joined(separator: "\n").data(using: .utf8) ?? Data()
    }

    func reset() { snapshot = AppSnapshot(); persistNow(); toast = "All local data was deleted" }

    func flush() { saveTask?.cancel(); persistNow() }

    private func generatePendingOccurrences() {
        let calendar = Calendar.autoupdatingCurrent
        let horizon = calendar.date(byAdding: .day, value: 30, to: Date()) ?? Date()
        for i in snapshot.recurringRules.indices where snapshot.recurringRules[i].isActive {
            var date = snapshot.recurringRules[i].nextOccurrence
            while date <= horizon && snapshot.recurringRules[i].endDate.map({ date <= $0 }) != false {
                let ruleID = snapshot.recurringRules[i].id
                if !snapshot.occurrences.contains(where: { $0.ruleID == ruleID && calendar.isDate($0.plannedDate, inSameDayAs: date) }) {
                    snapshot.occurrences.append(RecurringOccurrence(ruleID: ruleID, plannedDate: date, status: .pending))
                }
                let value = max(snapshot.recurringRules[i].interval, 1)
                switch snapshot.recurringRules[i].cadence {
                case .daily: date = calendar.date(byAdding: .day, value: value, to: date) ?? horizon.addingTimeInterval(1)
                case .weekly: date = calendar.date(byAdding: .weekOfYear, value: value, to: date) ?? horizon.addingTimeInterval(1)
                case .monthly: date = calendar.date(byAdding: .month, value: value, to: date) ?? horizon.addingTimeInterval(1)
                case .yearly: date = calendar.date(byAdding: .year, value: value, to: date) ?? horizon.addingTimeInterval(1)
                }
            }
            snapshot.recurringRules[i].nextOccurrence = date
        }
    }

    func rescheduleNotifications() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let identifiers = requests.map(\.identifier).filter { $0.hasPrefix("vanta-occurrence-") }
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
        guard settings.remindersEnabled else { return }
        let calendar = Calendar.autoupdatingCurrent
        for occurrence in occurrences where occurrence.status == .pending && occurrence.plannedDate > Date() {
            guard let rule = recurringRules.first(where: { $0.id == occurrence.ruleID }), let minutes = rule.reminderOffset else { continue }
            let fireDate = calendar.date(byAdding: .minute, value: -minutes, to: occurrence.plannedDate) ?? occurrence.plannedDate
            guard fireDate > Date() else { continue }
            let content = UNMutableNotificationContent()
            content.title = rule.kind == .income ? "Income due" : "Payment due"
            content.body = "\(rule.name) · \(money(rule.amount))"
            content.sound = .default
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let request = UNNotificationRequest(identifier: "vanta-occurrence-\(occurrence.id.uuidString)", content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
            center.add(request)
        }
    }

    private func changed(_ message: String? = nil) {
        objectWillChange.send()
        if let message { toast = message }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            self?.persistNow()
        }
    }

    private func load() {
        let request = NSFetchRequest<NSManagedObject>(entityName: "AppState")
        request.predicate = NSPredicate(format: "key == %@", "main")
        do {
            if let object = try container.viewContext.fetch(request).first, let data = object.value(forKey: "payload") as? Data {
                snapshot = try decoder().decode(AppSnapshot.self, from: data)
            }
        } catch { lastError = "Your data could not be loaded. \(error.localizedDescription)" }
    }

    private func persistNow() {
        do {
            let context = container.viewContext
            let request = NSFetchRequest<NSManagedObject>(entityName: "AppState")
            request.predicate = NSPredicate(format: "key == %@", "main")
            let object = try context.fetch(request).first ?? NSEntityDescription.insertNewObject(forEntityName: "AppState", into: context)
            object.setValue("main", forKey: "key"); object.setValue(try encoder().encode(snapshot), forKey: "payload"); object.setValue(Date(), forKey: "updatedAt")
            try context.save()
        } catch { lastError = "Changes could not be saved. \(error.localizedDescription)" }
    }

    private func validate(_ value: AppSnapshot) throws {
        guard Set(value.accounts.map(\.id)).count == value.accounts.count,
              Set(value.transactions.map(\.id)).count == value.transactions.count,
              Set(value.categories.map(\.id)).count == value.categories.count else { throw ImportError.duplicateIdentifiers }
        let accountIDs = Set(value.accounts.map(\.id))
        let categoryIDs = Set(value.categories.map(\.id))
        guard value.transactions.allSatisfy({ transaction in
            accountIDs.contains(transaction.accountID)
                && transaction.destinationAccountID.map(accountIDs.contains) != false
                && transaction.categoryID.map(categoryIDs.contains) != false
                && transaction.amount >= 0
        }) else { throw ImportError.invalidReferences }
    }

    private func replace<T: Identifiable>(_ array: inout [T], _ value: T) where T.ID == UUID { if let i = array.firstIndex(where: { $0.id == value.id }) { array[i] = value } }
    private func csvEscape(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
    private func encoder() -> JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e }
    private func decoder() -> JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
    enum ImportError: LocalizedError {
        case unsupportedVersion, duplicateIdentifiers, invalidReferences
        var errorDescription: String? {
            switch self {
            case .unsupportedVersion: return "This backup was created by a newer version of Vanta."
            case .duplicateIdentifiers: return "The backup contains duplicate record identifiers."
            case .invalidReferences: return "The backup contains invalid account, category, or amount references."
            }
        }
    }
}
