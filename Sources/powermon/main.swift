import Foundation
import CPower

// powermon: prototype that prints every power reading this Mac exposes without root.
// Usage: powermon [--count N]

let args = CommandLine.arguments
var limit = 3
if let i = args.firstIndex(of: "--count"), i + 1 < args.count, let n = Int(args[i + 1]) { limit = n }

if args.contains("--smc-test") {
    _ = lanes_smc_open()
    for key in ["PSTR", "PDTR", "PHPC", "PMVC"] {
        var line = key + ":"
        for _ in 0..<8 {
            var v = 0.0
            line += lanes_smc_read_float(key, &v) == 1 ? String(format: " %.3f", v) : " -"
            Thread.sleep(forTimeInterval: 0.25)
        }
        print(line)
    }
    exit(0)
}

print("IOReport init:", lanes_power_init() == 1 ? "ok" : "FAILED")
print("SMC open:     ", lanes_smc_open() == 1 ? "ok" : "FAILED")
print()

let smcKeys = ["PSTR", "PDTR", "PPBR", "PCPC", "PCPG", "PC0C", "PCTR", "PHPC", "PDCR", "PMVC", "PZ0E"]

for round in 1...limit {
    Thread.sleep(forTimeInterval: 1.0)
    print("--- sample \(round)")

    var channels = [lanes_power_channel](repeating: lanes_power_channel(), count: 128)
    let n = Int(lanes_power_read(&channels, 128))
    if n < 0 { print("IOReport: no data") }
    for i in 0..<max(n, 0) {
        let name = withUnsafePointer(to: &channels[i].name) {
            $0.withMemoryRebound(to: CChar.self, capacity: 64) { String(cString: $0) }
        }
        print(String(format: "  IOReport  %-28@ %8.3f W", name as NSString, channels[i].watts))
    }

    for key in smcKeys {
        var v = 0.0
        if lanes_smc_read_float(key, &v) == 1 {
            print(String(format: "  SMC       %-28@ %8.3f", key as NSString, v))
        }
    }
    fflush(stdout)
}
