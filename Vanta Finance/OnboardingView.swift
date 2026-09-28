import SwiftUI
import LocalAuthentication

struct RootView: View {
    @EnvironmentObject private var store: FinanceStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if !store.isReady {
                BootstrapView()
            } else if store.settings.biometricLock && !store.isUnlocked {
                AppLockView()
            } else if store.settings.onboardingComplete {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .tint(VantaTheme.cobalt)
        .toastPresenter()
        .alert("Something went wrong", isPresented: errorBinding) {
            Button("OK", role: .cancel) { store.lastError = nil }
        } message: {
            Text(store.lastError ?? "")
        }
        .onChange(of: scenePhase) { phase in
            if phase == .background {
                store.flush()
                if store.settings.biometricLock { store.isUnlocked = false }
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { store.lastError != nil },
            set: { if !$0 { store.lastError = nil } }
        )
    }
}

struct BootstrapView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animate = false

    var body: some View {
        ZStack {
            VantaTheme.midnight.ignoresSafeArea()

            RadialGradient(
                colors: [VantaTheme.cobalt.opacity(0.24), .clear],
                center: .topLeading,
                startRadius: 20,
                endRadius: 380
            )
            .ignoresSafeArea()

            Circle()
                .fill(VantaTheme.gold.opacity(0.07))
                .frame(width: 330, height: 330)
                .blur(radius: 20)
                .offset(x: 150, y: -290)

            VStack(spacing: 0) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.025))
                        .frame(width: 148, height: 148)
                        .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))
                        .shadow(color: VantaTheme.gold.opacity(0.12), radius: 32)

                    Circle()
                        .trim(from: 0.08, to: 0.7)
                        .stroke(
                            AngularGradient(
                                colors: [.clear, VantaTheme.gold.opacity(0.35), VantaTheme.gold, .clear],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                        )
                        .frame(width: 126, height: 126)
                        .rotationEffect(.degrees(animate && !reduceMotion ? 360 : 0))

                    Circle()
                        .stroke(VantaTheme.gold.opacity(0.22), lineWidth: 1)
                        .frame(width: animate ? 94 : 86, height: animate ? 94 : 86)

                    Text("V")
                        .font(.system(size: 52, weight: .light, design: .serif))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.white, VantaTheme.gold],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .accessibilityHidden(true)

                Text("VANTA")
                    .font(.system(size: 20, weight: .semibold, design: .serif))
                    .tracking(7)
                    .foregroundStyle(.white)
                    .padding(.top, 28)

                Text("PRIVATE WEALTH JOURNAL")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2.4)
                    .foregroundStyle(VantaTheme.gold.opacity(0.85))
                    .padding(.top, 9)

                loadingTrack
                    .frame(width: 154, height: 2)
                    .padding(.top, 34)

                Text("Preparing your private workspace")
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.52))
                    .padding(.top, 15)

                Spacer()

                Label("Encrypted on this device", systemImage: "lock.fill")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.34))
                    .padding(.bottom, 34)
            }
            .padding(.horizontal, 28)
        }
        .onAppear {
            withAnimation(.linear(duration: 2.8).repeatForever(autoreverses: false)) {
                animate = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Opening Vanta Finance")
    }

    private var loadingTrack: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.09))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.clear, VantaTheme.gold, .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 62)
                    .offset(x: reduceMotion ? (proxy.size.width - 62) / 2 : (animate ? proxy.size.width : -62))
            }
            .clipShape(Capsule())
        }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 1.35).repeatForever(autoreverses: false),
            value: animate
        )
    }
}

struct AppLockView: View {
    @EnvironmentObject private var store: FinanceStore
    @State private var error: String?

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "lock.shield.fill").font(.system(size: 54)).foregroundStyle(VantaTheme.cobalt)
            Text("Vanta is locked").font(.largeTitle.bold())
            Text("Authenticate with Face ID, Touch ID, or your device passcode to open your journal.").foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            if let error { Text(error).font(.footnote).foregroundStyle(VantaTheme.terracotta).multilineTextAlignment(.center) }
            Button("Unlock") { authenticate() }.buttonStyle(.borderedProminent).controlSize(.large)
            Spacer()
        }
        .padding(32)
        .vantaBackground()
        .onAppear { authenticate() }
    }

    private func authenticate() {
        let context = LAContext()
        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
            error = authError?.localizedDescription ?? "Device authentication is unavailable."
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock your private financial journal") { success, evaluationError in
            DispatchQueue.main.async {
                if success { store.isUnlocked = true; error = nil }
                else { error = evaluationError?.localizedDescription ?? "Authentication failed." }
            }
        }
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var store: FinanceStore
    @State private var step = 0
    @State private var currency = "USD"
    @State private var search = ""
    @State private var monday = true
    @State private var monthDay = 1
    @State private var accountName = "Everyday account"
    @State private var accountKind = AccountKind.checking
    @State private var balanceText = "0"
    @State private var categories = OnboardingView.defaults

    static let defaults: [FinanceCategory] = [
        .init(name: "Housing", kind: .expense, iconName: "house", colorHex: "315CFF"), .init(name: "Groceries", kind: .expense, iconName: "basket", colorHex: "23856D"),
        .init(name: "Transport", kind: .expense, iconName: "car", colorHex: "C88A21"), .init(name: "Dining", kind: .expense, iconName: "fork.knife", colorHex: "D9684A"),
        .init(name: "Health", kind: .expense, iconName: "cross.case", colorHex: "A95566"), .init(name: "Entertainment", kind: .expense, iconName: "sparkles", colorHex: "6B68A9"),
        .init(name: "Salary", kind: .income, iconName: "briefcase", colorHex: "23856D"), .init(name: "Other income", kind: .income, iconName: "plus.circle", colorHex: "315CFF")
    ]

    var body: some View {
        ZStack {
            LinearGradient(colors: [VantaTheme.ivory, Color(hex: "E7ECFF")], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            VStack(spacing: 0) {
                HStack { if step > 0 { Button { withAnimation { step -= 1 } } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Back") }; Spacer(); Text("\(step + 1) of 7").font(.caption.weight(.medium)).foregroundStyle(.secondary) }.padding()
                ProgressView(value: Double(step + 1), total: 7).tint(VantaTheme.cobalt).padding(.horizontal)
                TabView(selection: $step) {
                    welcome.tag(0); privacy.tag(1); currencyStep.tag(2); regionStep.tag(3); categoriesStep.tag(4); accountStep.tag(5); summary.tag(6)
                }.tabViewStyle(.page(indexDisplayMode: .never)).animation(.easeInOut, value: step)
                Button(step == 6 ? "Start using Vanta" : "Continue") { advance() }
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 15).background(VantaTheme.cobalt, in: RoundedRectangle(cornerRadius: 15)).foregroundStyle(.white).padding()
                    .disabled(step == 5 && (accountName.trimmingCharacters(in: .whitespaces).isEmpty || Decimal.parse(balanceText) == nil))
            }
        }
    }

    private var welcome: some View { onboardingPage(icon: "circle.hexagongrid.fill", eyebrow: "VANTA FINANCE", title: "Money, made legible.", message: "A private financial journal for accounts, spending, plans, and the decisions ahead.") }
    private var privacy: some View { onboardingPage(icon: "lock.shield", eyebrow: "PRIVATE BY DESIGN", title: "Your finances stay yours.", message: "Everything is stored on this device. There are no accounts, ads, trackers, or hidden network calls.", footer: "You can export or back up your data whenever you choose.") }

    private var currencyStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Choose your base currency").font(.largeTitle.bold())
            Text("Reports and totals use this currency. You can still add accounts in other currencies.").foregroundStyle(.secondary)
            TextField("Search currencies", text: $search).textFieldStyle(.roundedBorder)
            ScrollView { LazyVStack(spacing: 8) { ForEach(filteredCurrencies, id: \.code) { item in Button { currency = item.code } label: { HStack { Text(item.symbol).font(.title3).frame(width: 34); VStack(alignment: .leading) { Text(item.code).font(.headline); Text(item.name).font(.caption).foregroundStyle(.secondary) }; Spacer(); if currency == item.code { Image(systemName: "checkmark.circle.fill") } }.padding(12).background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 14)) }.buttonStyle(.plain) } } }
        }.padding(24)
    }
    private var filteredCurrencies: [(code: String, name: String, symbol: String)] { search.isEmpty ? CurrencyCatalog.common : CurrencyCatalog.common.filter { $0.code.localizedCaseInsensitiveContains(search) || $0.name.localizedCaseInsensitiveContains(search) } }

    private var regionStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Set your rhythm").font(.largeTitle.bold())
            Text("Vanta uses these choices for calendars, budgets, and monthly reports.").foregroundStyle(.secondary)
            VStack(spacing: 0) {
                Picker("Week begins", selection: $monday) { Text("Monday").tag(true); Text("Sunday").tag(false) }.padding()
                Divider().padding(.leading)
                Stepper("Financial month starts on day \(monthDay)", value: $monthDay, in: 1...28).padding()
            }.background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 18))
            Spacer()
        }.padding(24)
    }

    private var categoriesStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your categories").font(.largeTitle.bold())
            Text("Start with a useful set. You can change it anytime.").foregroundStyle(.secondary)
            ScrollView { LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 10) { ForEach(Self.defaults) { item in let selected = categories.contains(where: { $0.id == item.id }); Button { if selected { categories.removeAll { $0.id == item.id } } else { categories.append(item) } } label: { VStack(alignment: .leading, spacing: 8) { Image(systemName: item.iconName).foregroundStyle(Color(hex: item.colorHex)); Text(item.name).font(.subheadline.weight(.medium)).foregroundStyle(.primary); Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? VantaTheme.cobalt : .secondary) }.frame(maxWidth: .infinity, alignment: .leading).padding().background(Color.white.opacity(selected ? 0.9 : 0.45), in: RoundedRectangle(cornerRadius: 16)) }.buttonStyle(.plain) } } }
        }.padding(24)
    }

    private var accountStep: some View {
        ScrollView { VStack(alignment: .leading, spacing: 20) {
            Text("Create your first account").font(.largeTitle.bold())
            Text("This can be a bank account, card, or the cash in your wallet.").foregroundStyle(.secondary)
            VStack(spacing: 16) {
                TextField("Account name", text: $accountName).textFieldStyle(.roundedBorder)
                Picker("Account type", selection: $accountKind) { ForEach(AccountKind.allCases) { Label($0.rawValue, systemImage: $0.icon).tag($0) } }
                HStack { Text(currency).font(.headline); TextField("Opening balance", text: $balanceText).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }.padding(12).background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            }.padding().background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 18))
        }.padding(24) }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Ready when you are.").font(.largeTitle.bold())
            Text("Your journal starts clean—no sample transactions, no invented insights.").foregroundStyle(.secondary)
            VStack(spacing: 0) {
                summaryRow("Base currency", currency); Divider().padding(.leading); summaryRow("Financial month", "Day \(monthDay)"); Divider().padding(.leading); summaryRow("Categories", "\(categories.count) selected"); Divider().padding(.leading); summaryRow("First account", accountName)
            }.background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 18))
            Spacer()
        }.padding(24)
    }

    private func onboardingPage(icon: String, eyebrow: String, title: String, message: String, footer: String? = nil) -> some View {
        ScrollView {
            VStack(spacing: 22) {
                Image(systemName: icon).font(.system(size: 58, weight: .light)).foregroundStyle(VantaTheme.cobalt).padding(.top, 70)
                Text(eyebrow).font(.caption.weight(.bold)).tracking(2).foregroundStyle(VantaTheme.cobalt)
                Text(title).font(.system(size: 42, weight: .bold, design: .rounded)).multilineTextAlignment(.center).lineLimit(3).minimumScaleFactor(0.72).fixedSize(horizontal: false, vertical: true)
                Text(message).font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                if let footer { Text(footer).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.top).fixedSize(horizontal: false, vertical: true) }
            }
            .frame(maxWidth: .infinity)
            .padding(30)
        }
    }
    private func summaryRow(_ title: String, _ value: String) -> some View { HStack { Text(title).foregroundStyle(.secondary); Spacer(); Text(value).fontWeight(.medium) }.padding() }
    private func advance() { if step < 6 { withAnimation { step += 1 } } else { store.completeOnboarding(currency: currency, monday: monday, monthDay: monthDay, accountName: accountName.trimmingCharacters(in: .whitespaces), kind: accountKind, balance: Decimal.parse(balanceText) ?? 0, selectedCategories: categories) } }
}
