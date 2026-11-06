import Foundation
import SystemMonitorCore

// lanes-verify: samples Lanes' own collectors for N seconds and, over the same window,
// asks macOS's reference tools (vm_stat, top, iostat) for the same numbers. Prints each
// metric with its reference and the error, and exits 1 if anything is off by more than 1%.
//
// Usage: lanes-verify [seconds]   (default 10). Run with the Lanes panel closed.

let seconds = CommandLine.arguments.count > 1 ? Int(CommandLine.arguments[1]) ?? 10 : 10
let queue = DispatchQueue(label: "verify")
let ram = RAMCollector(queue: queue)
let cpu = CPUCollector()
let drives = DriveCollector(queue: queue)

func run(_ cmd: String, _ args: [String]) -> String {
    let p = Process(); p.executableURL = URL(fileURLWithPath: cmd); p.arguments = args
    let pipe = Pipe(); p.standardOutput = pipe
    try? p.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(decoding: data, as: UTF8.self)
}

// Reference tools run concurrently so their window matches ours.
var topOut = "", iostatOut = ""
let group = DispatchGroup()
group.enter(); DispatchQueue.global().async { topOut = run("/usr/bin/top", ["-l", "2", "-s", "\(seconds)", "-n", "0"]); group.leave() }
group.enter(); DispatchQueue.global().async { iostatOut = run("/usr/sbin/iostat", ["-d", "-w", "\(seconds)", "-c", "2"]); group.leave() }

// Our own sampling over the same window.
queue.sync { _ = cpu.usage(); _ = drives.rates(includeInternal: true) }
var cpuSamples: [Double] = []
var driveTotals: [String: (read: Double, write: Double, n: Int)] = [:]
for _ in 0..<seconds {
    Thread.sleep(forTimeInterval: 1)
    queue.sync {
        if let c = cpu.usage() { cpuSamples.append(c) }
        for r in drives.rates(includeInternal: true) {
            var t = driveTotals[r.bsdName] ?? (0, 0, 0)
            t.read += r.readBytesPerSec; t.write += r.writeBytesPerSec; t.n += 1
            driveTotals[r.bsdName] = t
        }
    }
}
// Memory: Lanes vs vm_stat at the same instant (checks the formula implementation).
let vmOut = run("/usr/bin/vm_stat", [])
let snap = queue.sync { ram.snapshot() }
group.wait()

var failures = 0
func report(_ name: String, lanes: Double, ref: Double, unit: String, tolerance: Double, relative: Bool) {
    let err = relative ? abs(lanes - ref) / max(ref, 1e-9) * 100 : abs(lanes - ref)
    let ok = err <= tolerance
    if !ok { failures += 1 }
    let errText = relative ? String(format: "%.2f%%", err) : String(format: "%.2f pt", err)
    print(String(format: "%@  %-22@ lanes %10.2f %@   reference %10.2f %@   error %@",
                 ok ? "OK  " : "FAIL", name as NSString, lanes, unit as NSString, ref, unit as NSString, errText as NSString))
}

// --- Memory
func vmPages(_ key: String) -> Double {
    for line in vmOut.split(separator: "\n") where line.hasPrefix(key) {
        let digits = line.split(separator: ":").last?.trimmingCharacters(in: CharacterSet(charactersIn: " .")) ?? ""
        return Double(digits) ?? 0
    }
    return 0
}
let page = 16384.0, gb = 1_073_741_824.0
let total = Double(ProcessInfo.processInfo.physicalMemory)
let refUsed = (total - vmPages("Pages free") * page - vmPages("File-backed pages") * page) / gb
if let snap {
    report("Memory used (GB)", lanes: Double(snap.usedBytes) / gb, ref: refUsed, unit: "GB", tolerance: 1, relative: true)
    let refApp = (vmPages("Anonymous pages") - vmPages("Pages purgeable")) * page / gb
    report("App memory (GB)", lanes: Double(snap.appBytes) / gb, ref: refApp, unit: "GB", tolerance: 1, relative: true)
    report("Wired (GB)", lanes: Double(snap.wiredBytes) / gb, ref: vmPages("Pages wired down") * page / gb, unit: "GB", tolerance: 1, relative: true)
    report("Compressed (GB)", lanes: Double(snap.compressedBytes) / gb, ref: vmPages("Pages occupied by compressor") * page / gb, unit: "GB", tolerance: 1, relative: true)
}

// --- CPU: top's second sample covers the same window. "CPU usage: 3.78% user, 1.83% sys, 94.38% idle"
if let line = topOut.split(separator: "\n").filter({ $0.contains("CPU usage") }).last {
    let nums = line.split(whereSeparator: { !"0123456789.".contains($0) }).compactMap { Double($0) }
    if nums.count >= 2, !cpuSamples.isEmpty {
        let refBusy = nums[0] + nums[1]
        let lanesBusy = cpuSamples.reduce(0, +) / Double(cpuSamples.count) * 100
        report("CPU busy (%)", lanes: lanesBusy, ref: refBusy, unit: "%", tolerance: 1, relative: false)
    }
}

// --- Disks: iostat's second line is the average over the window, in MiB/s (read+write combined).
let ioLines = iostatOut.split(separator: "\n").map(String.init)
if ioLines.count >= 4 {
    let names = ioLines[0].split(separator: " ").map(String.init)
    let values = ioLines[3].split(separator: " ").compactMap { Double($0) }
    for (i, name) in names.enumerated() where values.count >= (i + 1) * 3 {
        let refMiB = values[i * 3 + 2]
        guard let t = driveTotals[name], t.n > 0 else { continue }
        let lanesMiB = (t.read + t.write) / Double(t.n) / 1_048_576
        // Under 1 MiB/s the kernel's rounding dominates, so only judge busy disks.
        if refMiB >= 1 {
            report("Disk \(name) (MiB/s)", lanes: lanesMiB, ref: refMiB, unit: "MiB/s", tolerance: 1, relative: true)
        } else {
            print(String(format: "skip  Disk %@ idle (%.2f MiB/s): copy a file to test it", name as NSString, refMiB))
        }
    }
}

print(failures == 0 ? "\nAll within 1%." : "\n\(failures) metric(s) outside 1%.")
exit(failures == 0 ? 0 : 1)
