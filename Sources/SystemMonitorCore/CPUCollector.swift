import Foundation
import Darwin

/// Overall CPU usage (0...1) since the previous call. First call returns nil.
/// Uses `host_statistics(HOST_CPU_LOAD_INFO)`: one small struct, no per-core buffer to allocate.
public final class CPUCollector {
    private var previous: (busy: UInt64, total: UInt64)?

    public init() {}

    public func usage() -> Double? {
        var load = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride
                                           / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &load) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let user = UInt64(load.cpu_ticks.0), system = UInt64(load.cpu_ticks.1)
        let idle = UInt64(load.cpu_ticks.2), nice = UInt64(load.cpu_ticks.3)
        let busy = user + system + nice
        let total = busy + idle

        defer { previous = (busy, total) }
        guard let previous, total > previous.total else { return nil }
        return Double(busy &- previous.busy) / Double(total &- previous.total)
    }
}
