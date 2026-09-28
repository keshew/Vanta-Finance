import XCTest
@testable import Vanta_Finance

@MainActor
final class FinanceStoreTests: XCTestCase {
    private func makeStore() async throws -> FinanceStore {
        let store = FinanceStore(inMemory: true)
        while !store.isReady { try await Task.sleep(nanoseconds: 10_000_000) }
        let expense = FinanceCategory(name: "Food", kind: .expense, iconName: "basket", colorHex: "C7694F")
        let income = FinanceCategory(name: "Salary", kind: .income, iconName: "briefcase", colorHex: "267765")
        store.completeOnboarding(currency: "USD", monday: true, monthDay: 1, accountName: "Primary", kind: .checking, balance: 100, selectedCategories: [expense, income])
        return store
    }

    func testIncomeExpenseAndDeletionRecalculateBalance() async throws {
        let store = try await makeStore()
        let account = try XCTUnwrap(store.activeAccounts.first)
        let expenseCategory = try XCTUnwrap(store.categories.first { $0.kind == .expense })
        let incomeCategory = try XCTUnwrap(store.categories.first { $0.kind == .income })
        let income = FinanceTransaction(kind: .income, amount: 50, currencyCode: "USD", convertedAmount: 50, exchangeRate: 1, date: Date(), note: "Pay", accountID: account.id, categoryID: incomeCategory.id)
        let expense = FinanceTransaction(kind: .expense, amount: 20, currencyCode: "USD", convertedAmount: 20, exchangeRate: 1, date: Date(), note: "Lunch", accountID: account.id, categoryID: expenseCategory.id)
        store.addTransaction(income); store.addTransaction(expense)
        XCTAssertEqual(store.balance(for: account), 130)
        store.deleteTransaction(expense.id)
        XCTAssertEqual(store.balance(for: account), 150)
        store.restoreTransaction(expense)
        XCTAssertEqual(store.balance(for: account), 130)
    }

    func testTransferAffectsBothAccountsAndNotCashFlow() async throws {
        let store = try await makeStore()
        let source = try XCTUnwrap(store.activeAccounts.first)
        let destination = Account(name: "Savings", kind: .savings, currencyCode: "USD", openingBalance: 10, iconName: "leaf", colorHex: "267765")
        store.addAccount(destination)
        store.addTransaction(FinanceTransaction(kind: .transfer, amount: 25, currencyCode: "USD", convertedAmount: 25, exchangeRate: 1, date: Date(), note: "Move", accountID: source.id, destinationAccountID: destination.id))
        XCTAssertEqual(store.balance(for: source), 75)
        XCTAssertEqual(store.balance(for: destination), 35)
        XCTAssertEqual(store.monthIncomeExpense().income, 0)
        XCTAssertEqual(store.monthIncomeExpense().expense, 0)
    }

    func testEditingTransactionReplacesOldEffect() async throws {
        let store = try await makeStore()
        let account = try XCTUnwrap(store.activeAccounts.first)
        let category = try XCTUnwrap(store.categories.first { $0.kind == .expense })
        var transaction = FinanceTransaction(kind: .expense, amount: 10, currencyCode: "USD", convertedAmount: 10, exchangeRate: 1, date: Date(), note: "Original", accountID: account.id, categoryID: category.id)
        store.addTransaction(transaction)
        transaction.amount = 35; transaction.convertedAmount = 35
        store.updateTransaction(transaction)
        XCTAssertEqual(store.balance(for: account), 65)
        XCTAssertEqual(store.transactions.filter { $0.id == transaction.id }.count, 1)
    }

    func testMultiCurrencyTransferAndBankersRounding() async throws {
        let store = try await makeStore()
        let source = try XCTUnwrap(store.activeAccounts.first)
        let yen = Account(name: "Tokyo", kind: .cash, currencyCode: "JPY", openingBalance: 0, iconName: "banknote", colorHex: "B68A42")
        store.addAccount(yen)
        let received = store.rounded(1500.6, currencyCode: "JPY")
        store.addTransaction(FinanceTransaction(kind: .transfer, amount: 10, currencyCode: "USD", convertedAmount: received, exchangeRate: 150.06, date: Date(), note: "FX", accountID: source.id, destinationAccountID: yen.id))
        XCTAssertEqual(received, 1501)
        XCTAssertEqual(store.balance(for: source), 90)
        XCTAssertEqual(store.balance(for: yen), 1501)
    }

    func testCustomFinancialMonth() async throws {
        let store = try await makeStore()
        store.updateSettings { $0.financialMonthStartDay = 15 }
        let date = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 10)))
        let period = store.financialPeriod(containing: date)
        XCTAssertEqual(Calendar.current.component(.day, from: period.start), 15)
        XCTAssertEqual(Calendar.current.component(.month, from: period.start), 8)
    }

    func testBudgetUniquenessAndSpending() async throws {
        let store = try await makeStore()
        let account = try XCTUnwrap(store.activeAccounts.first)
        let category = try XCTUnwrap(store.categories.first { $0.kind == .expense })
        let period = store.financialPeriod()
        store.addBudget(Budget(categoryID: category.id, limitAmount: 100, currencyCode: "USD", periodStart: period.start, periodEnd: period.end))
        store.addBudget(Budget(categoryID: category.id, limitAmount: 150, currencyCode: "USD", periodStart: period.start, periodEnd: period.end))
        store.addTransaction(FinanceTransaction(kind: .expense, amount: 30, currencyCode: "USD", convertedAmount: 30, exchangeRate: 1, date: Date(), note: "Food", accountID: account.id, categoryID: category.id))
        XCTAssertEqual(store.budgets.count, 1)
        XCTAssertEqual(store.spent(for: try XCTUnwrap(store.budgets.first)), 30)
    }

    func testRecurringGenerationIsDeduplicatedAfterEdit() async throws {
        let store = try await makeStore()
        let account = try XCTUnwrap(store.activeAccounts.first)
        let category = try XCTUnwrap(store.categories.first { $0.kind == .expense })
        var rule = RecurringRule(name: "Rent", kind: .expense, amount: 10, accountID: account.id, categoryID: category.id, cadence: .weekly, interval: 1, startDate: Date(), nextOccurrence: Date())
        store.addRecurring(rule)
        rule.amount = 12
        store.updateRecurring(rule)
        let dates = store.occurrences.filter { $0.ruleID == rule.id }.map { Calendar.current.startOfDay(for: $0.plannedDate) }
        XCTAssertEqual(Set(dates).count, dates.count)
    }

    func testJSONRoundTripAndCSVEscaping() async throws {
        let store = try await makeStore()
        let account = try XCTUnwrap(store.activeAccounts.first)
        let category = try XCTUnwrap(store.categories.first { $0.kind == .expense })
        store.addTransaction(FinanceTransaction(kind: .expense, amount: 12.34, currencyCode: "USD", convertedAmount: 12.34, exchangeRate: 1, date: Date(), note: "Coffee, \"large\"", accountID: account.id, categoryID: category.id))
        let backup = try store.exportJSON()
        let restored = FinanceStore(inMemory: true)
        while !restored.isReady { try await Task.sleep(nanoseconds: 10_000_000) }
        try restored.importJSON(backup)
        XCTAssertEqual(restored.transactions.count, 1)
        XCTAssertEqual(restored.transactions.first?.note, "Coffee, \"large\"")
        let rows = CSVParser.rows(in: try XCTUnwrap(String(data: store.csvData(), encoding: .utf8)))
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[1][8], "Coffee, \"large\"")
    }

    func testImportDeduplicatesTransactions() async throws {
        let store = try await makeStore()
        let account = try XCTUnwrap(store.activeAccounts.first)
        let category = try XCTUnwrap(store.categories.first { $0.kind == .expense })
        let transaction = FinanceTransaction(kind: .expense, amount: 1, currencyCode: "USD", convertedAmount: 1, exchangeRate: 1, date: Date(), note: "One", accountID: account.id, categoryID: category.id)
        try store.importTransactions([transaction, transaction])
        XCTAssertEqual(store.transactions.filter { $0.id == transaction.id }.count, 1)
    }

    func testNewerBackupSchemaIsRejectedAtomically() async throws {
        let store = try await makeStore()
        var snapshot = AppSnapshot()
        snapshot.schemaVersion = 99
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        XCTAssertThrowsError(try store.importJSON(data))
        XCTAssertEqual(store.accounts.count, 1)
        XCTAssertTrue(store.settings.onboardingComplete)
    }
}
