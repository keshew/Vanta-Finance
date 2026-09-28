import SwiftUI
import UniformTypeIdentifiers

enum VantaTheme {
    static let cobalt = Color(hex: "4057D6")
    static let terracotta = Color(hex: "C7694F")
    static let forest = Color(hex: "267765")
    static let amber = Color(hex: "B68A42")
    static let gold = Color(hex: "C8A96A")
    static let ink = Color(hex: "161D25")
    static let midnight = Color(hex: "111820")
    static let slate = Color(hex: "26313B")
    static let ivory = Color(hex: "F3F0E9")
    static let paper = Color(hex: "FBFAF6")
    static let mist = Color(hex: "E7E9E7")
}

extension Color {
    init(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0; Scanner(string: clean).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255, g = Double((value >> 8) & 0xFF) / 255, b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

extension Decimal {
    static func parse(_ text: String) -> Decimal? {
        let normalized = text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }
}

extension FinanceStore {
    func money(_ amount: Decimal, code: String? = nil, signed: Bool = false) -> String {
        let formatter = NumberFormatter(); formatter.numberStyle = .currency; formatter.currencyCode = code ?? settings.baseCurrency; formatter.locale = .autoupdatingCurrent
        formatter.maximumFractionDigits = (formatter.currencyCode == "JPY") ? 0 : 2
        let value = formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "—"
        if !settings.amountVisibility { return "••••" }
        return signed && amount > 0 ? "+\(value)" : value
    }
}

struct VantaBackground: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content.background {
            ZStack {
                (scheme == .dark ? VantaTheme.midnight : VantaTheme.ivory).ignoresSafeArea()
                LinearGradient(
                    colors: scheme == .dark
                        ? [Color.white.opacity(0.025), Color.clear, VantaTheme.cobalt.opacity(0.035)]
                        : [Color.white.opacity(0.58), Color.clear, VantaTheme.cobalt.opacity(0.025)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ).ignoresSafeArea()
            }
        }
    }
}

extension View { func vantaBackground() -> some View { modifier(VantaBackground()) } }

struct SectionHeader: View {
    let title: String
    var action: String?
    var onAction: (() -> Void)?
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased()).font(.caption2.weight(.bold)).tracking(1.75).foregroundStyle(.secondary)
            Spacer()
            if let action, let onAction { Button(action, action: onAction).font(.subheadline.weight(.semibold)) }
        }
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let detail: String
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) { Circle().fill(tint).frame(width: 6, height: 6); Text(title.uppercased()).font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(.secondary) }
            Text(value).font(.title3.weight(.medium)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.62)
            Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
        .background(Color.primary.opacity(0.042), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.primary.opacity(0.055), lineWidth: 0.7))
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 32, weight: .light)).foregroundStyle(VantaTheme.cobalt).accessibilityHidden(true)
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let actionTitle, let action { Button(actionTitle, action: action).buttonStyle(.borderedProminent).padding(.top, 4) }
        }.frame(maxWidth: .infinity).padding(28)
    }
}

struct TransactionRow: View {
    @EnvironmentObject private var store: FinanceStore
    let transaction: FinanceTransaction
    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous).fill(color.opacity(0.105)).frame(width: 46, height: 46)
                Image(systemName: transaction.kind.icon).font(.subheadline.weight(.semibold)).foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(transaction.note.isEmpty ? store.categoryName(transaction.categoryID) : transaction.note).font(.body.weight(.medium)).lineLimit(1)
                Text("\(store.accountName(transaction.accountID)) · \(transaction.date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(amount).font(.subheadline.weight(.semibold)).foregroundStyle(transaction.kind == .transfer ? .primary : color).monospacedDigit()
        }.padding(.vertical, 4).contentShape(Rectangle())
    }
    private var color: Color { transaction.kind == .income ? VantaTheme.forest : transaction.kind == .expense ? VantaTheme.terracotta : VantaTheme.cobalt }
    private var amount: String {
        let sign = transaction.kind == .income ? "+" : transaction.kind == .expense ? "−" : ""
        return sign + store.money(transaction.amount, code: transaction.currencyCode)
    }
}

struct PremiumHeroCard<Content: View>: View {
    @ViewBuilder let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .padding(22)
            .foregroundStyle(.white)
            .background {
                ZStack(alignment: .topTrailing) {
                    LinearGradient(colors: [VantaTheme.midnight, Color(hex: "24303A")], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Circle().fill(VantaTheme.gold.opacity(0.12)).frame(width: 180, height: 180).offset(x: 62, y: -74)
                    Circle().stroke(VantaTheme.gold.opacity(0.16), lineWidth: 1).frame(width: 120, height: 120).offset(x: 38, y: -42)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 0.8))
            .shadow(color: VantaTheme.midnight.opacity(0.18), radius: 24, y: 13)
    }
}

struct MonogramMark: View {
    var compact = false
    var body: some View {
        ZStack {
            Circle().stroke(VantaTheme.gold.opacity(0.7), lineWidth: 1)
            Text("V").font(.system(size: compact ? 11 : 15, weight: .medium, design: .serif)).foregroundStyle(VantaTheme.gold)
        }.frame(width: compact ? 26 : 34, height: compact ? 26 : 34)
    }
}

struct PremiumPill: View {
    let text: String
    let icon: String
    var tint = VantaTheme.gold
    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(tint.opacity(0.11), in: Capsule())
    }
}

struct RingProgress: View {
    let progress: Double
    let lineWidth: CGFloat
    let tint: Color
    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.075), lineWidth: lineWidth)
            Circle().trim(from: 0, to: max(0, min(progress, 1))).stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)).rotationEffect(.degrees(-90))
        }
    }
}

struct PremiumDivider: View {
    var body: some View {
        Rectangle().fill(LinearGradient(colors: [Color.clear, VantaTheme.gold.opacity(0.38), Color.clear], startPoint: .leading, endPoint: .trailing)).frame(height: 0.7)
    }
}

struct ToastView: View {
    let text: String
    var body: some View { Label(text, systemImage: "checkmark.circle.fill").font(.subheadline.weight(.medium)).padding(.horizontal, 16).padding(.vertical, 11).background(.thinMaterial, in: Capsule()).shadow(color: .black.opacity(0.14), radius: 12, y: 4) }
}

struct ToastPresenter: ViewModifier {
    @EnvironmentObject var store: FinanceStore
    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let toast = store.toast {
                HStack(spacing: 14) {
                    Label(toast, systemImage: "checkmark.circle.fill")
                    if let transaction = store.pendingTransactionUndo {
                        Button("Undo") { store.restoreTransaction(transaction); store.toast = nil }
                            .fontWeight(.bold)
                    }
                }
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 16).padding(.vertical, 11)
                .background(.thinMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.14), radius: 12, y: 4)
                .padding(.bottom, 70)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + (store.pendingTransactionUndo == nil ? 2 : 5)) {
                        withAnimation { store.toast = nil; store.clearTransactionUndo() }
                    }
                }
            }
        }.animation(.easeOut(duration: 0.2), value: store.toast)
    }
}

extension View { func toastPresenter() -> some View { modifier(ToastPresenter()) } }

struct DataFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
