import StoreKit
import SwiftUI

/// Optional tips. Ma stays free and nothing unlocks with a tip; it only
/// helps pay for the developer account and the server. The products are
/// consumables created in App Store Connect with these ids. Until they
/// exist there, the section simply does not show.
@MainActor
@Observable
final class TipJar {
    static let productIDs = ["com.sensei.ma.tip.small", "com.sensei.ma.tip.medium", "com.sensei.ma.tip.large"]

    private(set) var products: [Product] = []
    private(set) var thanked = false
    private(set) var busy = false

    func load() async {
        guard products.isEmpty else { return }
        let loaded = (try? await Product.products(for: Self.productIDs)) ?? []
        products = loaded.sorted { $0.price < $1.price }
    }

    func buy(_ product: Product) async {
        busy = true
        defer { busy = false }
        guard let result = try? await product.purchase() else { return }
        if case .success(let verification) = result, case .verified(let transaction) = verification {
            await transaction.finish()
            thanked = true
            Haptics.success()
        }
    }
}

struct TipJarSection: View {
    @State private var jar = TipJar()

    var body: some View {
        Group {
            if !jar.products.isEmpty {
                Section {
                    Text(tr("Ma is free and stays free. If it helps you, a tip keeps the developer account and the server running.",
                            "Ma ist kostenlos und bleibt es. Wenn es dir hilft, hält ein Trinkgeld Entwicklerkonto und Server am Laufen."))
                        .font(.system(size: 14))
                        .foregroundStyle(Zen.inkSoft)
                    HStack(spacing: 10) {
                        ForEach(jar.products, id: \.id) { product in
                            Button {
                                Task { await jar.buy(product) }
                            } label: {
                                Text(product.displayPrice)
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Zen.sand, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .disabled(jar.busy)
                        }
                    }
                    if jar.thanked {
                        Label(tr("Thank you, that means a lot.", "Danke, das bedeutet mir viel."), systemImage: "heart.fill")
                            .foregroundStyle(Zen.kin)
                    }
                } header: {
                    Label(tr("Support Ma", "Ma unterstützen"), systemImage: "heart.circle.fill")
                }
            }
        }
        .task { await jar.load() }
    }
}
