import Darwin
import Foundation

struct MemorySnapshot: Equatable, Sendable {
    let totalBytes: UInt64
    let availableBytes: UInt64

    var totalDescription: String { MemoryAdvisor.formatBytes(totalBytes) }
    var availableDescription: String { MemoryAdvisor.formatBytes(availableBytes) }
}

enum MemoryAdvisor {
    static let gibibyte: UInt64 = 1_073_741_824
    static let automaticPolishMinimumTotalBytes: UInt64 = 16 * gibibyte
    static let automaticPolishMinimumAvailableBytes: UInt64 = 4 * gibibyte
    static let explicitPolishMinimumAvailableBytes: UInt64 = 3 * gibibyte
    static let asrPrewarmMinimumAvailableBytes: UInt64 = 3 * gibibyte

    static func currentSnapshot() -> MemorySnapshot {
        MemorySnapshot(
            totalBytes: ProcessInfo.processInfo.physicalMemory,
            availableBytes: currentAvailableBytes() ?? 0
        )
    }

    static func shouldUsePolishAutomatically(snapshot: MemorySnapshot) -> Bool {
        snapshot.totalBytes >= automaticPolishMinimumTotalBytes
            && snapshot.availableBytes >= automaticPolishMinimumAvailableBytes
    }

    static func canUsePolishWhenExplicitlyEnabled(snapshot: MemorySnapshot) -> Bool {
        snapshot.availableBytes >= explicitPolishMinimumAvailableBytes
    }

    static func canPrewarmASR(snapshot: MemorySnapshot) -> Bool {
        snapshot.availableBytes >= asrPrewarmMinimumAvailableBytes
    }

    static func formatBytes(_ bytes: UInt64) -> String {
        let gib = Double(bytes) / Double(gibibyte)
        return String(format: "%.1f GB", gib)
    }

    private static func currentAvailableBytes() -> UInt64? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )

        let result = withUnsafeMutablePointer(to: &stats) { statsPointer in
            statsPointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { pointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, pointer, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        var rawPageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &rawPageSize) == KERN_SUCCESS else { return nil }
        let pageSize = UInt64(rawPageSize)
        let availablePages = UInt64(stats.free_count)
            + UInt64(stats.inactive_count)
            + UInt64(stats.speculative_count)
        return availablePages * pageSize
    }
}
