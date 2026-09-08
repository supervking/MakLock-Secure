import Darwin
import Foundation

enum SystemBootIdentity {
    static var current: String {
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.size
        if sysctlbyname("kern.boottime", &bootTime, &size, nil, 0) == 0 {
            return "\(bootTime.tv_sec).\(bootTime.tv_usec)"
        }

        let estimatedBootTime = Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime
        return "fallback-\(Int((estimatedBootTime / 60).rounded()))"
    }
}
