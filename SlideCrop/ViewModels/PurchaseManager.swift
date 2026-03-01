import Foundation
import StoreKit

@MainActor
final class PurchaseManager: ObservableObject {
    static let unlimitedProductID = "com.newsira.slidecrop.unlimited"

    @Published var isUnlocked: Bool
    @Published var product: Product?

    private let defaults: UserDefaults
    private let cachedUnlockKey = "isUnlimitedUnlockedCached"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isUnlocked = defaults.bool(forKey: cachedUnlockKey)

        Task {
            await refreshEntitlements()
            await loadProduct()
        }
    }

    func loadProduct() async {
        do {
            let products = try await Product.products(for: [Self.unlimitedProductID])
            product = products.first
        } catch {
            product = nil
        }
    }

    func purchase() async throws {
        if product == nil {
            await loadProduct()
        }

        guard let product else {
            throw PurchaseError.productUnavailable
        }

        let result = try await product.purchase()
        switch result {
        case let .success(verification):
            let transaction = try verifiedTransaction(verification)
            isUnlocked = transaction.productID == Self.unlimitedProductID
            defaults.set(isUnlocked, forKey: cachedUnlockKey)
            await transaction.finish()
            await refreshEntitlements()
        case .userCancelled:
            throw PurchaseError.userCancelled
        case .pending:
            throw PurchaseError.pending
        @unknown default:
            throw PurchaseError.unknown
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
        } catch {
            // Keep restore action resilient and rely on entitlement refresh.
        }

        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        var unlocked = false

        for await result in Transaction.currentEntitlements {
            guard case let .verified(transaction) = result else {
                continue
            }

            if transaction.productID == Self.unlimitedProductID,
               transaction.revocationDate == nil {
                unlocked = true
                break
            }
        }

        isUnlocked = unlocked
        defaults.set(unlocked, forKey: cachedUnlockKey)
    }

    private func verifiedTransaction<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case let .verified(transaction):
            return transaction
        case .unverified:
            throw PurchaseError.unverified
        }
    }
}

enum PurchaseError: LocalizedError, Equatable {
    case productUnavailable
    case userCancelled
    case pending
    case unverified
    case unknown

    var errorDescription: String? {
        switch self {
        case .productUnavailable:
            return "Purchase is currently unavailable. Please try again shortly."
        case .userCancelled:
            return "Purchase was canceled."
        case .pending:
            return "Purchase is pending approval."
        case .unverified:
            return "Unable to verify this purchase."
        case .unknown:
            return "Purchase failed. Please try again."
        }
    }
}
