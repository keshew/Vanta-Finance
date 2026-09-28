import SwiftUI
import Charts

enum AnalyticsPeriod: String, CaseIterable, Identifiable { case week = "7D", month = "Month", quarter = "3M", year = "Year", all = "All"; var id: String { rawValue } }

struct AnalyticsView: View {
    @EnvironmentObject private var store: FinanceStore
    @State private var period = AnalyticsPeriod.month
    private var interval: DateInterval {
        let end = Date(), cal = Calendar.current
        switch period { case .week: return .init(start: cal.date(byAdding: .day, value: -6, to: end) ?? end, end: end.addingTimeInterval(1)); case .month: return store.financialPeriod(); case .quarter: return .init(start: cal.date(byAdding: .month, value: -3, to: end) ?? end, end: end.addingTimeInterval(1)); case .year: return .init(start: cal.date(byAdding: .year, value: -1, to: end) ?? end, end: end.addingTimeInterval(1)); case .all: return .init(start: store.transactions.last?.date ?? end, end: end.addingTimeInterval(1)) }
    }
    private var items: [FinanceTransaction] { store.transactions.filter { interval.contains($0.date) && ($0.kind == .income || $0.kind == .expense) } }
    private var income: Decimal { items.filter { $0.kind == .income }.reduce(0) { $0 + store.converted($1.amount, from: $1.currencyCode) } }
    private var expense: Decimal { items.filter { $0.kind == .expense }.reduce(0) { $0 + store.converted($1.amount, from: $1.currencyCode) } }
    private var previousInterval: DateInterval { let duration = interval.duration; return DateInterval(start: interval.start.addingTimeInterval(-duration), end: interval.start) }
    private var previousItems: [FinanceTransaction] { store.transactions.filter { previousInterval.contains($0.date) && ($0.kind == .income || $0.kind == .expense) } }
    private var previousIncome: Decimal { previousItems.filter { $0.kind == .income }.reduce(0) { $0 + store.converted($1.amount, from: $1.currencyCode) } }
    private var previousExpense: Decimal { previousItems.filter { $0.kind == .expense }.reduce(0) { $0 + store.converted($1.amount, from: $1.currencyCode) } }
    private var categories: [(String, Decimal)] { Dictionary(grouping: items.filter { $0.kind == .expense }, by: { store.categoryName($0.categoryID) }).map { name, txs in (name, txs.reduce(0) { $0 + store.converted($1.amount, from: $1.currencyCode) }) }.sorted { $0.1 > $1.1 } }
    private var daily: [(Date, Decimal, Decimal)] { Dictionary(grouping: items, by: { Calendar.current.startOfDay(for: $0.date) }).map { date, txs in (date, txs.filter { $0.kind == .income }.reduce(0) { $0 + decimalDouble(store.converted($1.amount, from: $1.currencyCode)) }.decimal, txs.filter { $0.kind == .expense }.reduce(0) { $0 + decimalDouble(store.converted($1.amount, from: $1.currencyCode)) }.decimal) }.sorted { $0.0 < $1.0 } }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26) {
                HStack { MonogramMark(); VStack(alignment: .leading, spacing: 2) { Text("INTELLIGENCE").font(.caption2.bold()).tracking(2); Text("Portfolio analytics").font(.system(.title2, design: .serif).weight(.medium)) }; Spacer() }
                periodPicker
                analyticsHero
                if items.isEmpty {
                    EmptyState(icon: "chart.bar.xaxis", title: "No activity to analyze", message: "Add transactions or choose a wider period. Transfers are intentionally excluded.")
                } else {
                    cashFlowChart
                    categoryChart
                    periodComparison
                    trends
                    NavigationLink { AccountAnalyticsView(interval: interval) } label: {
                        HStack(spacing: 14) { Image(systemName: "building.columns.fill").foregroundStyle(VantaTheme.gold).frame(width: 40, height: 40).background(VantaTheme.gold.opacity(0.1), in: Circle()); VStack(alignment: .leading, spacing: 3) { Text("Account intelligence").font(.subheadline.weight(.semibold)); Text("Compare performance across your portfolio").font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }.padding(16).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 20)).overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.primary.opacity(0.05), lineWidth: 0.7))
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 18).padding(.bottom, 34)
        }.vantaBackground().navigationBarTitleDisplayMode(.inline)
    }

    private var periodPicker: some View {
        HStack(spacing: 5) {
            ForEach(AnalyticsPeriod.allCases) { option in
                Button { withAnimation(.easeOut(duration: 0.18)) { period = option } } label: {
                    Text(option.rawValue).font(.caption.weight(.semibold)).foregroundStyle(period == option ? Color.white : Color.secondary).frame(maxWidth: .infinity).padding(.vertical, 9).background(period == option ? VantaTheme.ink : Color.clear, in: Capsule())
                }.buttonStyle(.plain)
            }
        }.padding(4).background(Color.primary.opacity(0.055), in: Capsule())
    }

    private var analyticsHero: some View {
        PremiumHeroCard {
            VStack(alignment: .leading, spacing: 17) {
                HStack { Text("NET CASH FLOW").font(.caption2.bold()).tracking(1.5).foregroundStyle(.white.opacity(0.55)); Spacer(); PremiumPill(text: period.rawValue, icon: "calendar", tint: VantaTheme.gold) }
                Text(store.money(income - expense, signed: true)).font(.system(size: 38, weight: .medium, design: .serif)).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                PremiumDivider()
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) { Text("INFLOW").font(.system(size: 9, weight: .bold)).tracking(1).foregroundStyle(.white.opacity(0.48)); Text(store.money(income)).font(.subheadline.weight(.medium)).foregroundStyle(Color(hex: "9AC8B2")) }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) { Text("OUTFLOW").font(.system(size: 9, weight: .bold)).tracking(1).foregroundStyle(.white.opacity(0.48)); Text(store.money(expense)).font(.subheadline.weight(.medium)).foregroundStyle(Color(hex: "E5A38F")) }
                }
            }
        }
    }
    private var cashFlowChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { SectionHeader(title: "Cash flow signature"); Spacer(); HStack(spacing: 12) { legend("Income", VantaTheme.forest); legend("Spend", VantaTheme.terracotta) } }
            cashFlowGraphic
        }
        .padding(18)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.primary.opacity(0.05), lineWidth: 0.7))
    }

    @ViewBuilder private var cashFlowGraphic: some View {
        if daily.count < 2 {
            VStack(spacing: 22) {
                flowBar(title: "Income", amount: income, maximum: max(max(income, expense), 1), tint: VantaTheme.forest)
                flowBar(title: "Spend", amount: expense, maximum: max(max(income, expense), 1), tint: VantaTheme.terracotta)
                HStack {
                    Image(systemName: "sparkles").foregroundStyle(VantaTheme.gold)
                    Text("The signature becomes a trend line as your journal grows.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.top, 3)
            }
            .frame(height: 190)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Cash flow snapshot. Income \(store.money(income)); expenses \(store.money(expense)).")
        } else {
            Chart {
                ForEach(daily, id: \.0) { point in
                    AreaMark(x: .value("Date", point.0, unit: .day), y: .value("Income", decimalDouble(point.1))).interpolationMethod(.catmullRom).foregroundStyle(LinearGradient(colors: [VantaTheme.forest.opacity(0.28), VantaTheme.forest.opacity(0.01)], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Date", point.0, unit: .day), y: .value("Income", decimalDouble(point.1))).interpolationMethod(.catmullRom).lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round)).foregroundStyle(VantaTheme.forest)
                    PointMark(x: .value("Date", point.0, unit: .day), y: .value("Income", decimalDouble(point.1))).symbolSize(18).foregroundStyle(VantaTheme.forest)
                    LineMark(x: .value("Date", point.0, unit: .day), y: .value("Expenses", decimalDouble(point.2))).interpolationMethod(.catmullRom).lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 4])).foregroundStyle(VantaTheme.terracotta)
                    PointMark(x: .value("Date", point.0, unit: .day), y: .value("Expenses", decimalDouble(point.2))).symbolSize(15).foregroundStyle(VantaTheme.terracotta)
                }
            }
            .chartYAxis { AxisMarks(position: .leading) { value in AxisGridLine().foregroundStyle(Color.primary.opacity(0.06)); AxisValueLabel().font(.caption2).foregroundStyle(.secondary) } }
            .chartXAxis { AxisMarks { value in AxisGridLine().foregroundStyle(.clear); AxisValueLabel(format: .dateTime.day().month(.abbreviated)).font(.caption2).foregroundStyle(.secondary) } }
            .chartPlotStyle { plot in plot.background(Color.primary.opacity(0.015)).cornerRadius(12) }
            .frame(height: 230)
            .accessibilityLabel("Cash flow chart. Income \(store.money(income)); expenses \(store.money(expense)).")
        }
    }

    private func flowBar(title: String, amount: Decimal, maximum: Decimal, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(title.uppercased()).font(.caption2.bold()).tracking(1).foregroundStyle(.secondary)
                Spacer()
                Text(store.money(amount)).font(.subheadline.weight(.semibold)).monospacedDigit()
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.055))
                    Capsule()
                        .fill(LinearGradient(colors: [tint.opacity(0.65), tint], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(0, geometry.size.width * CGFloat(decimalDouble(amount / maximum))))
                }
            }
            .frame(height: 13)
        }
    }
    private func legend(_ title: String, _ color: Color) -> some View { HStack(spacing: 5) { Circle().fill(color).frame(width: 6, height: 6); Text(title).font(.caption2).foregroundStyle(.secondary) } }
    private var periodComparison: some View {
        VStack(alignment: .leading, spacing: 15) {
            SectionHeader(title: "Period comparison")
            comparisonRow("Income", current: income, previous: previousIncome, tint: VantaTheme.forest)
            PremiumDivider()
            comparisonRow("Spending", current: expense, previous: previousExpense, tint: VantaTheme.terracotta)
            PremiumDivider()
            comparisonRow("Net flow", current: income - expense, previous: previousIncome - previousExpense, tint: VantaTheme.gold)
        }
        .padding(18)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.primary.opacity(0.05), lineWidth: 0.7))
    }
    private func comparisonRow(_ title: String, current: Decimal, previous: Decimal, tint: Color) -> some View {
        let change = previous == 0 ? nil : decimalDouble((current - previous) / absDecimal(previous) * 100)
        return HStack(spacing: 14) {
            Circle().fill(tint).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 3) { Text(title).font(.subheadline.weight(.semibold)); Text("Previous \(store.money(previous))").font(.caption).foregroundStyle(.secondary) }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) { Text(store.money(current)).font(.subheadline.weight(.semibold)).monospacedDigit(); Text(change.map { String(format: "%+.0f%%", $0) } ?? "New activity").font(.caption2.weight(.semibold)).foregroundStyle(tint) }
        }
    }
    private var categoryChart: some View { VStack(alignment: .leading, spacing: 15) { SectionHeader(title: "Capital allocation"); Chart(categories.prefix(6), id: \.0) { item in BarMark(x: .value("Amount", decimalDouble(item.1)), y: .value("Category", item.0)).foregroundStyle(LinearGradient(colors: [VantaTheme.gold, VantaTheme.cobalt], startPoint: .leading, endPoint: .trailing)).cornerRadius(6) }.chartXAxis(.hidden).chartYAxis { AxisMarks { value in AxisValueLabel().font(.caption.weight(.medium)); AxisGridLine().foregroundStyle(.clear) } }.frame(height: CGFloat(max(categories.prefix(6).count, 1)) * 45); PremiumDivider(); ForEach(Array(categories.prefix(4).enumerated()), id: \.element.0) { index, item in NavigationLink { CategoryTransactionsView(categoryName: item.0, interval: interval) } label: { HStack { Text(String(format: "%02d", index + 1)).font(.caption2.monospacedDigit()).foregroundStyle(VantaTheme.gold); Text(item.0).font(.subheadline.weight(.medium)); Spacer(); VStack(alignment: .trailing, spacing: 2) { Text(store.money(item.1)).font(.subheadline.weight(.semibold)); Text(expense == 0 ? "0%" : "\(Int(decimalDouble(item.1 / expense) * 100))% of spend").font(.caption2).foregroundStyle(.secondary) }; Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary) }.padding(.vertical, 4) }.buttonStyle(.plain) } }.padding(18).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 22)).overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.primary.opacity(0.05), lineWidth: 0.7)) }
    private var trends: some View { let days = max(Calendar.current.dateComponents([.day], from: interval.start, to: min(interval.end, Date())).day ?? 1, 1), average = expense / Decimal(days), savings = income == 0 ? 0 : (income - expense) / income * 100, spendingDays = Set(items.filter { $0.kind == .expense }.map { Calendar.current.startOfDay(for: $0.date) }).count; return VStack(alignment: .leading, spacing: 14) { SectionHeader(title: "Private brief"); HStack(spacing: 10) { MetricCard(title: "Daily pace", value: store.money(average), detail: "Average outflow", tint: VantaTheme.terracotta); MetricCard(title: "Retained", value: "\(NSDecimalNumber(decimal: savings).intValue)%", detail: "Savings rate", tint: VantaTheme.forest) }; HStack(spacing: 10) { MetricCard(title: "Top allocation", value: categories.first?.0 ?? "—", detail: categories.first.map { store.money($0.1) } ?? "No spend", tint: VantaTheme.gold); MetricCard(title: "No-spend days", value: "\(max(days - spendingDays, 0))", detail: "In selected period", tint: VantaTheme.cobalt) } } }
}

private extension Double { var decimal: Decimal { Decimal(self) } }

struct CategoryTransactionsView: View {
    @EnvironmentObject private var store: FinanceStore
    let categoryName: String
    let interval: DateInterval
    private var items: [FinanceTransaction] { store.transactions.filter { interval.contains($0.date) && store.categoryName($0.categoryID) == categoryName } }
    var body: some View { List(items) { tx in NavigationLink { TransactionDetailView(transactionID: tx.id) } label: { TransactionRow(transaction: tx) } }.navigationTitle(categoryName) }
}

struct AccountAnalyticsView: View {
    @EnvironmentObject private var store: FinanceStore
    let interval: DateInterval
    var body: some View { List { ForEach(store.activeAccounts) { account in let txs = store.transactions(forAccount: account.id).filter { interval.contains($0.date) }, income = txs.filter { $0.kind == .income }.reduce(Decimal.zero) { $0 + $1.amount }, expense = txs.filter { $0.kind == .expense }.reduce(Decimal.zero) { $0 + $1.amount }; Section(account.name) { LabeledContent("Current balance", value: store.money(store.balance(for: account), code: account.currencyCode)); LabeledContent("Income", value: store.money(income, code: account.currencyCode)); LabeledContent("Expenses", value: store.money(expense, code: account.currencyCode)); LabeledContent("Net", value: store.money(income - expense, code: account.currencyCode, signed: true)) } } }.navigationTitle("Accounts") }
}
