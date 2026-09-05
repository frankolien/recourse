import Foundation

/// What the chain does not remember about a position: what was put in, and what the
/// share price has been. The vault knows shares and a price; it has no idea what
/// someone paid for the shares or what the price was last week. This phone keeps
/// both, per account, so the Earn screen can say what has been earned rather than
/// only what is there.
struct EarnLedger: Codable, Equatable {
    struct PricePoint: Codable, Equatable {
        let at: Date
        let price: Double
    }

    /// Net USDC put in from this phone, in base units, signed. Withdrawals reduce it.
    var basisBaseUnits: Int64 = 0
    /// False until a deposit or withdrawal has been made from this phone. A position
    /// that arrived some other way has no basis, and earnings against a guessed one
    /// would be a made-up number.
    var basisKnown = false
    var prices: [PricePoint] = []

    private static let key = "earn-ledger"
    private static let pointSpacing: TimeInterval = 6 * 3600
    private static let maxPoints = 120

    static func load(cache: SnapshotCache = .shared) -> EarnLedger {
        cache.load(EarnLedger.self, key: key, scope: ActiveAccount.scope) ?? EarnLedger()
    }

    func save(cache: SnapshotCache = .shared) {
        cache.save(self, key: Self.key, scope: ActiveAccount.scope)
    }

    /// One reading every few hours is plenty for a rate that moves by the day, and
    /// it keeps a phone that polls every visit from filling the file.
    mutating func record(price: Double, at date: Date = .now) {
        if let last = prices.last, date.timeIntervalSince(last.at) < Self.pointSpacing { return }
        prices.append(PricePoint(at: date, price: price))
        if prices.count > Self.maxPoints {
            prices.removeFirst(prices.count - Self.maxPoints)
        }
    }

    mutating func noteDeposit(_ amount: USDCAmount) {
        basisBaseUnits += Int64(amount.baseUnits)
        basisKnown = true
    }

    mutating func noteWithdrawal(_ amount: USDCAmount) {
        basisBaseUnits -= Int64(amount.baseUnits)
        basisKnown = true
    }

    /// The position less what went in, floored at zero: a position below its basis
    /// is a loss, and the card says "earned".
    func earnedSoFar(position: USDCAmount) -> USDCAmount? {
        guard basisKnown else { return nil }
        let earned = Int64(position.baseUnits) - basisBaseUnits
        return USDCAmount(baseUnits: UInt64(max(0, earned)))
    }

    /// What the shares gained over the last week, from the reading nearest to a week
    /// ago. Nil until the phone has a reading that old.
    func earnedLastWeek(shares: UInt64, priceNow: Double, now: Date = .now) -> USDCAmount? {
        guard shares > 0,
              let then = prices.last(where: { now.timeIntervalSince($0.at) >= 7 * 86_400 }) else { return nil }
        let gained = Double(shares) * (priceNow - then.price)
        return USDCAmount(baseUnits: UInt64(max(0, gained).rounded()))
    }

    /// The share price's growth over the readings, annualised. Nil until there is a
    /// reading at least a day old; shorter spans produce a rate that is mostly noise.
    func estimatedAPY(priceNow: Double, now: Date = .now) -> Double? {
        guard let first = prices.first, first.price > 0 else { return nil }
        let age = now.timeIntervalSince(first.at)
        guard age >= 86_400 else { return nil }
        let rate = pow(priceNow / first.price, 365 * 86_400 / age) - 1
        guard rate.isFinite, rate >= 0, rate < 10 else { return nil }
        return rate
    }
}
