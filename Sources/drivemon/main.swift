import Foundation
import SystemMonitorCore

// drivemon: prints read/write speed of each drive once a second.
// Usage: drivemon [--count N] [--internal]   (default: external only, until Ctrl-C)

let args = CommandLine.arguments
var limit = Int.max
if let i = args.firstIndex(of: "--count"), i + 1 < args.count, let n = Int(args[i + 1]) {
    limit = n
}
let includeInternal = args.contains("--internal")

let queue = DispatchQueue(label: "drivemon", qos: .utility)
let collector = DriveCollector(queue: queue)

var printed = 0
queue.async {
    _ = collector.rates(includeInternal: includeInternal)   // first call only records a baseline
}
let timer = DispatchSource.makeTimerSource(queue: queue)
timer.schedule(deadline: .now() + 1, repeating: 1)
timer.setEventHandler {
    let rates = collector.rates(includeInternal: includeInternal)
    if rates.isEmpty {
        print("no drive")
    } else {
        for r in rates {
            print(String(format: "%@ [%@ / %@]  read %7.1f MB/s   write %7.1f MB/s",
                         r.label, r.bsdName, r.model, r.readMBps, r.writeMBps))
        }
    }
    fflush(stdout)
    printed += 1
    if printed >= limit { exit(0) }
}
timer.activate()
dispatchMain()
