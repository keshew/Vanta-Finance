import Foundation

enum AccountKind: String, Codable, CaseIterable, Identifiable {
    case checking = "Checking"
    case savings = "Savings"
    case cash = "Cash"
    case credit = "Credit"
    case investment = "Investment"
    var id: String { rawValue }
    var icon: String {
        switch self { case .checking: return "building.columns"; case .savings: return "leaf"; case .cash: return "banknote"; case .credit: return "creditcard"; case .investment: return "chart.line.uptrend.xyaxis" }
    }
}

enum TransactionKind: String, Codable, CaseIterable, Identifiable {
    case expense = "Expense"
    case income = "Income"
    case transfer = "Transfer"
    case adjustment = "Adjustment"
    var id: String { rawValue }
    var icon: String {
        switch self { case .expense: return "arrow.up.right"; case .income: return "arrow.down.left"; case .transfer: return "arrow.left.arrow.right"; case .adjustment: return "equal.circle" }
    }
}

enum CategoryKind: String, Codable, CaseIterable, Identifiable {
    case expense = "Expenses"
    case income = "Income"
    var id: String { rawValue }
}

enum RecurrenceCadence: String, Codable, CaseIterable, Identifiable {
    case daily = "Daily"
    case weekly = "Weekly"
    case monthly = "Monthly"
    case yearly = "Yearly"
    var id: String { rawValue }
}

enum AppearanceMode: String, Codable, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
    var id: String { rawValue }
}

struct Account: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var kind: AccountKind
    var currencyCode: String
    var openingBalance: Decimal
    var iconName: String
    var colorHex: String
    var createdAt = Date()
    var archivedAt: Date?
    var sortOrder = 0
}

struct FinanceCategory: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var kind: CategoryKind
    var iconName: String
    var colorHex: String
    var archivedAt: Date?
    var sortOrder = 0
}

struct FinanceTransaction: Identifiable, Codable, Hashable {
    var id = UUID()
    var kind: TransactionKind
    var amount: Decimal
    var currencyCode: String
    var convertedAmount: Decimal
    var exchangeRate: Decimal
    var date: Date
    var note: String
    var createdAt = Date()
    var updatedAt = Date()
    var accountID: UUID
    var destinationAccountID: UUID?
    var categoryID: UUID?
    var tagIDs: [UUID] = []
    var recurringRuleID: UUID?
    var reconciliationMarker = false
}

struct FinanceTag: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var colorHex: String
}

struct Budget: Identifiable, Codable, Hashable {
    var id = UUID()
    var categoryID: UUID
    var limitAmount: Decimal
    var currencyCode: String
    var periodStart: Date
    var periodEnd: Date
    var rollover = false
}

struct SavingsGoal: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var targetAmount: Decimal
    var currentAmount: Decimal
    var currencyCode: String
    var targetDate: Date?
    var accountID: UUID?
    var iconName: String
    var colorHex: String
    var archivedAt: Date?
}

struct GoalContribution: Identifiable, Codable, Hashable {
    var id = UUID()
    var goalID: UUID
    var amount: Decimal
    var date = Date()
    var accountID: UUID?
    var note: String
}

struct RecurringRule: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var kind: TransactionKind
    var amount: Decimal
    var accountID: UUID
    var categoryID: UUID?
    var cadence: RecurrenceCadence
    var interval: Int
    var startDate: Date
    var endDate: Date?
    var nextOccurrence: Date
    var reminderOffset: Int?
    var isActive = true
}

struct RecurringOccurrence: Identifiable, Codable, Hashable {
    enum Status: String, Codable { case pending, completed, skipped }
    var id = UUID()
    var ruleID: UUID
    var plannedDate: Date
    var status: Status
    var generatedTransactionID: UUID?
}

struct ManualExchangeRate: Identifiable, Codable, Hashable {
    var id = UUID()
    var fromCurrency: String
    var toCurrency: String
    var rate: Decimal
    var effectiveDate = Date()
}

struct AppSettings: Codable, Hashable {
    var baseCurrency = "USD"
    var appearance = AppearanceMode.system
    var weekStartsMonday = true
    var financialMonthStartDay = 1
    var amountVisibility = true
    var biometricLock = false
    var remindersEnabled = false
    var onboardingComplete = false
}

struct AppSnapshot: Codable {
    var schemaVersion = 1
    var settings = AppSettings()
    var accounts: [Account] = []
    var categories: [FinanceCategory] = []
    var transactions: [FinanceTransaction] = []
    var tags: [FinanceTag] = []
    var budgets: [Budget] = []
    var goals: [SavingsGoal] = []
    var contributions: [GoalContribution] = []
    var recurringRules: [RecurringRule] = []
    var occurrences: [RecurringOccurrence] = []
    var exchangeRates: [ManualExchangeRate] = []
}

enum CurrencyCatalog {
    static let common: [(code: String, name: String, symbol: String)] = [
        ("USD", "US Dollar", "$"), ("EUR", "Euro", "€"), ("GBP", "British Pound", "£"),
        ("CAD", "Canadian Dollar", "$"), ("AUD", "Australian Dollar", "$"), ("JPY", "Japanese Yen", "¥"),
        ("CHF", "Swiss Franc", "CHF"), ("CNY", "Chinese Yuan", "¥"), ("INR", "Indian Rupee", "₹"),
        ("RUB", "Russian Ruble", "₽"), ("AED", "UAE Dirham", "AED"), ("TRY", "Turkish Lira", "₺")
    ]
}

