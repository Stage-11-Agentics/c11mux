import Foundation
import Combine
import Darwin

/// Per-surface CPU/RSS sampler. C11-25 commit 6.
///
/// Runs on a background `DispatchSourceTimer` at a fixed cadence (default
/// 2 Hz, tunable to 1 Hz via `UserDefaults` key
/// `c11.surfaceMetrics.sampleHz`). On each tick it walks every registered
/// surface, resolves the surface's process identifier via the registered
/// closure, and samples `proc_pid_rusage(pid, RUSAGE_INFO_V4)` to read
/// cumulative CPU time + resident-size bytes. CPU% is derived from the
/// inter-tick CPU-time delta against the inter-tick wall-clock delta.
///
/// Threading: the sampler is not `@MainActor` — its state is protected
/// by an `os_unfair_lock`, and the timer fires off-main. The `@Published
/// revision` counter is bumped on the main queue after each tick so
/// SwiftUI re-evaluates the sidebar at the cadence —
/// `TabItemView.==` catches unchanged metric values and short-circuits
/// body re-eval, preserving the typing-latency invariant.
///
/// PID resolution differs by surface kind:
///
/// - Browsers: `webView.c11_webProcessIdentifier` (the
///   `_webProcessIdentifier` SPI). Cheap, in-process.
/// - Terminals: NOT YET IMPLEMENTED in C11-25. The TTY → child PID
///   resolver requires either a libghostty surface accessor patch or a
///   `lsof`-style process-listing helper. Plan §2 row 5 acknowledges
///   this is a follow-up; for C11-25 commit 6 the terminal panel
///   registers a provider that returns `nil`, the sidebar renders `—`
///   for terminal CPU/RSS.
final class SurfaceMetricsSampler: ObservableObject, @unchecked Sendable {
    static let shared = SurfaceMetricsSampler()

    /// Per-surface sample. Stored briefly between ticks; consumers read
    /// via `sample(forSurfaceId:)`.
    struct Sample: Equatable {
        let cpuPct: Double  // percent, may exceed 100 on multi-core spikes
        let rssMb: Double
        let sampledAt: Date
    }

    /// SwiftUI observation hook. Bumped on the main queue after each
    /// sampling tick. Sidebar reads via `@ObservedObject` to receive
    /// objectWillChange notifications.
    @Published private(set) var revision: UInt64 = 0

    private let lock: UnsafeMutablePointer<os_unfair_lock_s>
    private var samples: [UUID: Sample] = [:]
    private var pidProviders: [UUID: () -> pid_t?] = [:]
    private var lastCpuTimes: [pid_t: UInt64] = [:]
    private var lastSampleAt: Date?

    private let queue = DispatchQueue(
        label: "com.stage11.c11.surface-metrics",
        qos: .utility
    )
    private var timer: DispatchSourceTimer?

    private init() {
        lock = .allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock_s())
    }

    /// Begin sampling. Idempotent.
    func start() {
        // Construct timer off-main; idempotency check is locked.
        let intervalMs: Int = {
            let hz = max(1.0, min(10.0, Self.configuredHz()))
            return Int(1000.0 / hz)
        }()
        os_unfair_lock_lock(lock)
        guard timer == nil else {
            os_unfair_lock_unlock(lock)
            return
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now() + .milliseconds(intervalMs),
            repeating: .milliseconds(intervalMs)
        )
        self.timer = timer
        os_unfair_lock_unlock(lock)
        timer.setEventHandler { [weak self] in
            self?.tick()
        }
        timer.resume()
    }

    /// Stop sampling. Used in tests.
    func stop() {
        os_unfair_lock_lock(lock)
        let t = timer
        timer = nil
        os_unfair_lock_unlock(lock)
        t?.cancel()
    }

    /// Register a surface + PID provider. The provider is invoked off-main
    /// during sampling; it must be thread-safe (or read state that is).
    /// Browser panels pass a closure that reads
    /// `webView.c11_webProcessIdentifier` (KVC, safe off-main); terminal
    /// panels pass `{ nil }` for C11-25.
    func register(surfaceId: UUID, pidProvider: @escaping () -> pid_t?) {
        os_unfair_lock_lock(lock)
        pidProviders[surfaceId] = pidProvider
        os_unfair_lock_unlock(lock)
    }

    /// Drop a surface's registration and any cached sample.
    func unregister(surfaceId: UUID) {
        os_unfair_lock_lock(lock)
        pidProviders.removeValue(forKey: surfaceId)
        samples.removeValue(forKey: surfaceId)
        os_unfair_lock_unlock(lock)
    }

    /// Read the most recent sample for a surface (or nil if none yet /
    /// PID provider returned nil). Cheap dictionary lookup; safe to call
    /// from SwiftUI body.
    func sample(forSurfaceId id: UUID) -> Sample? {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return samples[id]
    }

    deinit {
        timer?.cancel()
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    // MARK: - Configuration

    private static func configuredHz() -> Double {
        let raw = UserDefaults.standard.double(forKey: "c11.surfaceMetrics.sampleHz")
        return raw > 0 ? raw : 2.0
    }

    // MARK: - Sampling tick

    private func tick() {
        let now = Date()
        os_unfair_lock_lock(lock)
        let providers = pidProviders
        let priorTimes = lastCpuTimes
        let prior = lastSampleAt
        os_unfair_lock_unlock(lock)

        let dt: Double = prior.map { now.timeIntervalSince($0) } ?? 0
        var newSamples: [UUID: Sample] = [:]
        var newTimes: [pid_t: UInt64] = [:]

        for (surfaceId, provider) in providers {
            guard let pid = provider() else { continue }
            guard let cumulative = Self.proc_pid_cumulative_cpu_ns(pid) else { continue }
            let rssBytes = Self.proc_pid_rss_bytes(pid) ?? 0

            let cpuPct: Double
            if dt > 0, let last = priorTimes[pid], cumulative >= last {
                let deltaNs = Double(cumulative - last)
                cpuPct = min(800.0, deltaNs / 1e9 / dt * 100.0)
            } else {
                cpuPct = 0
            }
            newTimes[pid] = cumulative
            newSamples[surfaceId] = Sample(
                cpuPct: cpuPct,
                rssMb: Double(rssBytes) / 1024.0 / 1024.0,
                sampledAt: now
            )
        }

        os_unfair_lock_lock(lock)
        samples = newSamples
        lastCpuTimes = newTimes
        lastSampleAt = now
        os_unfair_lock_unlock(lock)

        // Bump revision on main so SwiftUI re-evaluates the sidebar.
        DispatchQueue.main.async { [weak self] in
            self?.revision &+= 1
        }
    }

    // MARK: - proc_pid_rusage helpers

    /// Cumulative user+system CPU time in nanoseconds for `pid`, via
    /// `proc_pid_rusage(RUSAGE_INFO_V4)`. Returns nil if the call fails
    /// (e.g. the process exited).
    private static func proc_pid_cumulative_cpu_ns(_ pid: pid_t) -> UInt64? {
        var ri = rusage_info_v4()
        let rc = withUnsafeMutablePointer(to: &ri) { ptr -> Int32 in
            ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { boxPtr in
                proc_pid_rusage(pid, RUSAGE_INFO_V4, boxPtr)
            }
        }
        guard rc == 0 else { return nil }
        return ri.ri_user_time &+ ri.ri_system_time
    }

    /// Resident set size in bytes for `pid`, via the same call. Returns
    /// nil on failure.
    private static func proc_pid_rss_bytes(_ pid: pid_t) -> UInt64? {
        var ri = rusage_info_v4()
        let rc = withUnsafeMutablePointer(to: &ri) { ptr -> Int32 in
            ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { boxPtr in
                proc_pid_rusage(pid, RUSAGE_INFO_V4, boxPtr)
            }
        }
        guard rc == 0 else { return nil }
        return ri.ri_resident_size
    }
}
