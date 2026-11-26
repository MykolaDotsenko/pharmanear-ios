import Foundation

#if canImport(Combine)
    import Combine
#endif

public enum SearchPhase: Equatable, Sendable {
    case idle
    case locating
    case loading
    case found
    case empty
    case denied
    case failed
    case cancelled

    public var isBusy: Bool { self == .locating || self == .loading }
}

public enum SearchOrigin: Equatable, Sendable {
    case device
    case city(City)
}

/// Everything the interface shows about the current search, published as one value.
public struct SearchSnapshot: Equatable, Sendable {
    public let phase: SearchPhase
    public let origin: SearchOrigin?
    public let result: SearchResult?

    public static let idle = SearchSnapshot(phase: .idle, origin: nil, result: nil)
}

/// The device position could not be obtained: permission denied or restricted, or no fix in time.
public struct LocationUnavailable: Error, Equatable {
    public init() {}
}

/// One position on request. Implementations ask for permission when needed and honour task cancellation.
@MainActor
public protocol LocationProviding: AnyObject {
    func currentLocation() async throws -> Point
}

/// Owns the lifecycle of one search at a time.
///
/// Starting, retrying or cancelling a search cancels the one before it, and a superseded search can never
/// publish: each search carries a generation number that must still be current when it finishes.
@MainActor
public final class SearchSession {
    #if canImport(Combine)
        @Published public private(set) var snapshot = SearchSnapshot.idle
    #else
        public private(set) var snapshot = SearchSnapshot.idle
    #endif

    private let lookup: @Sendable (Point) async throws -> SearchResult
    private let location: any LocationProviding
    private var task: Task<Void, Never>?
    private var generation = 0
    private var lastOrigin: SearchOrigin?

    public init(
        location: any LocationProviding,
        lookup: @escaping @Sendable (Point) async throws -> SearchResult = { origin in
            try await PharmacyCatalog.shared.lookup(origin: origin)
        }
    ) {
        self.location = location
        self.lookup = lookup
    }

    public func locate() { start(.device) }

    public func search(from city: City) { start(.city(city)) }

    public func retry() {
        if let lastOrigin { start(lastOrigin) }
    }

    public func cancel() {
        invalidate()
        snapshot = SearchSnapshot(phase: .cancelled, origin: nil, result: nil)
    }

    private func start(_ origin: SearchOrigin) {
        invalidate()
        lastOrigin = origin
        snapshot = SearchSnapshot(phase: origin == .device ? .locating : .loading, origin: origin, result: nil)
        let generation = generation
        task = Task { [weak self] in
            await self?.run(from: origin, generation: generation)
        }
    }

    private func run(from origin: SearchOrigin, generation: Int) async {
        do {
            let point: Point
            switch origin {
            case .device:
                point = try await location.currentLocation()
                guard isCurrent(generation) else { return }
                snapshot = SearchSnapshot(phase: .loading, origin: origin, result: nil)
            case .city(let city):
                point = city.centre
            }
            let result = try await lookup(point)
            guard isCurrent(generation) else { return }
            snapshot = SearchSnapshot(
                phase: result.pharmacies.isEmpty ? .empty : .found, origin: origin, result: result)
        } catch {
            guard isCurrent(generation) else { return }
            snapshot = SearchSnapshot(
                phase: error is LocationUnavailable ? .denied : .failed, origin: origin, result: nil)
        }
    }

    private func isCurrent(_ generation: Int) -> Bool {
        !Task.isCancelled && generation == self.generation
    }

    private func invalidate() {
        generation += 1
        task?.cancel()
        task = nil
    }
}

#if canImport(Combine)
    /// SwiftUI observes the session directly through its published snapshot.
    extension SearchSession: ObservableObject {}
#endif
