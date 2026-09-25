// SystemStats.swift — what a widget extension can legitimately read about the device.
// No toggles: iOS gives third-party code no API to switch Wi-Fi / Bluetooth / Airplane mode.

import Foundation
import Network
import UIKit

struct SystemSnapshot: Codable, Equatable {
    var cpuPercent: Double          // 0…100, all cores averaged over the sample window
    var memoryUsedBytes: UInt64
    var memoryTotalBytes: UInt64
    var diskFreeBytes: UInt64
    var diskTotalBytes: UInt64
    var network: String             // "wifi" | "cellular" | "wired" | "none"
    var batteryLevel: Double?       // 0…1, nil when the extension cannot read it
    var lowPower: Bool = false
    var thermal: String = "nominal" // nominal | fair | serious | critical
    var uptime: TimeInterval = 0
    var ip: String? = nil
    var sampled: Date

    /// One cell of the system row: (value, label key, tile, fallback symbol).
    func cell(for id: String) -> (value: String, label: String, tile: String, symbol: String) {
        let m = SystemMetric.byID(id) ?? SystemMetric.all[0]
        switch id {
        case "cpu":      return ("\(Int(cpuPercent.rounded()))%", m.name, m.tile, m.symbol)
        case "ram":      return (SystemSnapshot.gb(memoryUsedBytes), m.name, m.tile, m.symbol)
        case "memfree":  return (SystemSnapshot.gb(memoryTotalBytes > memoryUsedBytes ? memoryTotalBytes - memoryUsedBytes : 0), m.name, m.tile, m.symbol)
        case "storage":  return (SystemSnapshot.gb(diskFreeBytes), m.name, m.tile, m.symbol)
        case "used":     return (SystemSnapshot.gb(diskTotalBytes > diskFreeBytes ? diskTotalBytes - diskFreeBytes : 0), m.name, m.tile, m.symbol)
        case "network":  return (networkLabel, m.name, networkTile, networkSymbol)
        case "battery":  return (batteryLevel.map { "\(Int($0 * 100))%" } ?? "—", m.name, m.tile, m.symbol)
        case "lowpower": return (lowPower ? String(localized: "開") : String(localized: "關"), m.name, m.tile, m.symbol)
        case "thermal":  return (SystemSnapshot.thermalLabel(thermal), m.name, m.tile, m.symbol)
        case "ip":       return (ip ?? "—", m.name, m.tile, m.symbol)
        default:         return ("—", m.name, m.tile, m.symbol)
        }
    }
    static func thermalLabel(_ t: String) -> String {
        switch t { case "fair": return String(localized: "偏熱"); case "serious": return String(localized: "過熱"); case "critical": return String(localized: "危險"); default: return String(localized: "正常") }
    }
    static func uptimeLabel(_ s: TimeInterval) -> String {
        let h = Int(s) / 3600, d = h / 24
        return d > 0 ? "\(d)d \(h % 24)h" : "\(h)h \((Int(s) % 3600) / 60)m"
    }

    /// Compact size with its own unit: 3.1G / 118G / 10.5T.
    static func gb(_ bytes: UInt64) -> String {
        let g = Double(bytes) / 1_000_000_000
        if g >= 1000 { return String(format: "%.1fT", g / 1000) }
        return g >= 100 ? String(format: "%.0fG", g) : String(format: "%.1fG", g)
    }
    var networkLabel: String {
        switch network {
        case "wifi": return "Wi-Fi"
        case "cellular": return String(localized: "行動")
        case "wired": return String(localized: "有線")
        default: return String(localized: "離線")
        }
    }
    var networkTile: String {
        switch network { case "wifi": return "tile-wifi"; case "cellular": return "tile-cellular"; case "wired": return "tile-wifi"; default: return "tile-offline" }
    }
    var networkSymbol: String {
        switch network { case "wifi": return "wifi"; case "cellular": return "antenna.radiowaves.left.and.right"; case "wired": return "cable.connector"; default: return "wifi.slash" }
    }
}

enum SystemStats {
    /// CPU busy fraction between two host_processor_info samples, `window` seconds apart.
    static func sample(window: TimeInterval = 0.25) async -> SystemSnapshot {
        let t0 = cpuTicks()
        try? await Task.sleep(nanoseconds: UInt64(window * 1_000_000_000))
        let t1 = cpuTicks()
        var cpu = 0.0
        if let a = t0, let b = t1 {
            let busy = Double((b.user - a.user) + (b.system - a.system) + (b.nice - a.nice))
            let total = busy + Double(b.idle - a.idle)
            cpu = total > 0 ? min(max(busy / total * 100, 0), 100) : 0
        }
        let (memUsed, memTotal) = memory()
        let (diskFree, diskTotal) = disk()
        let net = await networkKind()
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        let pi = ProcessInfo.processInfo
        let thermal: String
        switch pi.thermalState { case .fair: thermal = "fair"; case .serious: thermal = "serious"; case .critical: thermal = "critical"; default: thermal = "nominal" }
        return SystemSnapshot(cpuPercent: cpu, memoryUsedBytes: memUsed, memoryTotalBytes: memTotal,
                              diskFreeBytes: diskFree, diskTotalBytes: diskTotal, network: net,
                              batteryLevel: level >= 0 ? Double(level) : nil,
                              lowPower: pi.isLowPowerModeEnabled, thermal: thermal, uptime: 0,
                              ip: ipv4Address(), sampled: Date())
    }

    /// First non-loopback IPv4 (Wi-Fi en0 preferred).
    private static func ipv4Address() -> String? {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return nil }
        defer { freeifaddrs(addrs) }
        var found: [String: String] = [:]
        var p: UnsafeMutablePointer<ifaddrs>? = first
        while let a = p {
            let flags = Int32(a.pointee.ifa_flags)
            if let sa = a.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET), (flags & IFF_LOOPBACK) == 0, (flags & IFF_UP) != 0 {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    found[String(cString: a.pointee.ifa_name)] = String(cString: host)
                }
            }
            p = a.pointee.ifa_next
        }
        return found["en0"] ?? found["pdp_ip0"] ?? found.values.first
    }

    private struct Ticks { var user, system, nice, idle: UInt64 }

    private static func cpuTicks() -> Ticks? {
        var count = mach_msg_type_number_t(0)
        var info: processor_info_array_t?
        var n: natural_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &n, &info, &count) == KERN_SUCCESS, let info else { return nil }
        defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(count) * vm_size_t(MemoryLayout<integer_t>.size)) }
        var t = Ticks(user: 0, system: 0, nice: 0, idle: 0)
        let stride = Int(CPU_STATE_MAX)
        for i in 0..<Int(n) {
            t.user += UInt64(info[i * stride + Int(CPU_STATE_USER)])
            t.system += UInt64(info[i * stride + Int(CPU_STATE_SYSTEM)])
            t.nice += UInt64(info[i * stride + Int(CPU_STATE_NICE)])
            t.idle += UInt64(info[i * stride + Int(CPU_STATE_IDLE)])
        }
        return t
    }

    private static func memory() -> (UInt64, UInt64) {
        let total = ProcessInfo.processInfo.physicalMemory
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        guard kr == KERN_SUCCESS else { return (0, total) }
        let page = UInt64(vm_kernel_page_size)
        // "used" the way Activity Monitor counts it: active + wired + compressed
        let used = (UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
        return (min(used, total), total)
    }

    private static func disk() -> (UInt64, UInt64) {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let v = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
        return (UInt64(max(v?.volumeAvailableCapacityForImportantUsage ?? 0, 0)), UInt64(max(v?.volumeTotalCapacity ?? 0, 0)))
    }

    private static func networkKind() async -> String {
        await withCheckedContinuation { cont in
            // Handler and timeout run on different queues; OnceResume makes sure only one of
            // them resumes (a second resume of a checked continuation crashes — ticket 0011).
            let once = OnceResume(cont)
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                let kind: String
                if path.status != .satisfied { kind = "none" }
                else if path.usesInterfaceType(.wifi) { kind = "wifi" }
                else if path.usesInterfaceType(.cellular) { kind = "cellular" }
                else if path.usesInterfaceType(.wiredEthernet) { kind = "wired" }
                else { kind = "wifi" }
                if once.resume(kind) { monitor.cancel() }
            }
            monitor.start(queue: DispatchQueue.global(qos: .utility))
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                if once.resume("none") { monitor.cancel() }
            }
        }
    }
}
