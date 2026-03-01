import Foundation

final class FreeSaveCounter {
    let freeLimit = 10

    private let defaults: UserDefaults
    private let slidesSavedCountKey = "slidesSavedCount"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var slidesSavedCount: Int {
        get {
            max(0, defaults.integer(forKey: slidesSavedCountKey))
        }
        set {
            defaults.set(max(0, newValue), forKey: slidesSavedCountKey)
        }
    }

    var remainingFreeSaves: Int {
        max(0, freeLimit - slidesSavedCount)
    }

    func consumeSaves(_ n: Int) {
        guard n > 0 else { return }
        slidesSavedCount += n
    }
}
