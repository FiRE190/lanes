import Foundation
import IOKit
import DiskArbitration

/// Read/write speed for one drive, in bytes per second.
public struct DriveRate: Equatable {
    public let bsdName: String      // e.g. "disk6"
    public let label: String        // volume name(s), e.g. "Work SSD"
    public let model: String        // hardware model, e.g. "M.2 P320 512GB"
    public let isInternal: Bool
    public let readBytesPerSec: Double
    public let writeBytesPerSec: Double

    public init(bsdName: String, label: String, model: String, isInternal: Bool, readBytesPerSec: Double, writeBytesPerSec: Double) {
        self.bsdName = bsdName
        self.label = label
        self.model = model
        self.isInternal = isInternal
        self.readBytesPerSec = readBytesPerSec
        self.writeBytesPerSec = writeBytesPerSec
    }

    public var readMBps: Double { readBytesPerSec / 1_000_000 }
    public var writeMBps: Double { writeBytesPerSec / 1_000_000 }
}

/// Per-drive byte counters from IOKit, no sudo needed.
///
/// Drives are discovered once, and again only when DiskArbitration reports a disk or volume
/// appearing or disappearing. Between those events each tick does one thing per drive: read
/// the driver's `Statistics` property. Must be used from the queue given to `init`.
public final class DriveCollector {
    private struct Drive {
        let bsdName: String
        let label: String
        let model: String
        let isInternal: Bool
        let driver: io_object_t          // retained IOBlockStorageDriver
    }

    private let session: DASession?
    private var drives: [Drive] = []
    private var needsDiscovery = true
    private var previous: [String: (read: UInt64, write: UInt64, time: TimeInterval)] = [:]

    public init(queue: DispatchQueue) {
        session = DASessionCreate(kCFAllocatorDefault)
        guard let session else { return }
        DASessionSetDispatchQueue(session, queue)
        let context = Unmanaged.passUnretained(self).toOpaque()
        DARegisterDiskAppearedCallback(session, nil, { _, context in
            guard let context else { return }
            Unmanaged<DriveCollector>.fromOpaque(context).takeUnretainedValue().needsDiscovery = true
        }, context)
        DARegisterDiskDisappearedCallback(session, nil, { _, context in
            guard let context else { return }
            Unmanaged<DriveCollector>.fromOpaque(context).takeUnretainedValue().needsDiscovery = true
        }, context)
    }

    deinit {
        if let session { DASessionSetDispatchQueue(session, nil) }
        releaseDrives()
    }

    /// Speed since the previous call. The first call for a drive returns nothing for it.
    public func rates(includeInternal: Bool) -> [DriveRate] {
        if needsDiscovery { discover() }

        let now = ProcessInfo.processInfo.systemUptime
        var out: [DriveRate] = []
        var next: [String: (read: UInt64, write: UInt64, time: TimeInterval)] = [:]

        for drive in drives where includeInternal || !drive.isInternal {
            guard let stats = IORegistryEntryCreateCFProperty(
                    drive.driver, "Statistics" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? [String: Any] else { continue }
            let read = (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
            let write = (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
            next[drive.bsdName] = (read, write, now)

            guard let prev = previous[drive.bsdName], now > prev.time else { continue }
            let dt = now - prev.time
            // Counters can reset if a drive is replugged. Never report negative speed.
            let dRead = read >= prev.read ? read - prev.read : 0
            let dWrite = write >= prev.write ? write - prev.write : 0
            out.append(DriveRate(bsdName: drive.bsdName, label: drive.label, model: drive.model,
                                 isInternal: drive.isInternal,
                                 readBytesPerSec: Double(dRead) / dt,
                                 writeBytesPerSec: Double(dWrite) / dt))
        }
        previous = next
        return out
    }

    // MARK: - Discovery (runs only at start and after a disk/volume change)

    private func releaseDrives() {
        drives.forEach { IOObjectRelease($0.driver) }
        drives = []
    }

    private func discover() {
        needsDiscovery = false
        releaseDrives()

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOBlockStorageDriver"),
                                           &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }

        let mounted = mountedVolumes()

        while case let driver = IOIteratorNext(iterator), driver != 0 {
            guard let media = wholeDiskMedia(under: driver) else { IOObjectRelease(driver); continue }
            defer { IOObjectRelease(media.entry) }
            guard let info = diskInfo(bsdName: media.bsd) else { IOObjectRelease(driver); continue }

            let label = info.isInternal
                ? "Internal SSD"
                : volumeLabel(media: media.entry, bsd: media.bsd, mounted: mounted, fallback: info.model)
            drives.append(Drive(bsdName: media.bsd, label: label, model: info.model,
                                isInternal: info.isInternal, driver: driver))   // keeps `driver` retained
        }
        drives.sort { $0.bsdName < $1.bsdName }
    }

    /// The driver's child IOMedia that is the whole disk, e.g. "disk6". Caller releases `entry`.
    private func wholeDiskMedia(under driver: io_object_t) -> (bsd: String, entry: io_object_t)? {
        var children: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(driver, kIOServicePlane, &children) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(children) }

        while case let child = IOIteratorNext(children), child != 0 {
            if IOObjectConformsTo(child, "IOMedia") != 0,
               IORegistryEntryCreateCFProperty(child, "Whole" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? Bool == true,
               let name = IORegistryEntryCreateCFProperty(child, "BSD Name" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? String {
                return (name, child)
            }
            IOObjectRelease(child)
        }
        return nil
    }

    /// Whether the disk is internal, plus its hardware model. Disk images and virtual disks are nil.
    private func diskInfo(bsdName: String) -> (isInternal: Bool, model: String)? {
        guard let session,
              let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, bsdName),
              let desc = DADiskCopyDescription(disk) as? [String: Any] else { return nil }

        let proto = desc[kDADiskDescriptionDeviceProtocolKey as String] as? String
        if proto == "Disk Image" || proto == "Virtual Interface" { return nil }

        let isInternal = desc[kDADiskDescriptionDeviceInternalKey as String] as? Bool ?? true
        let model = (desc[kDADiskDescriptionDeviceModelKey as String] as? String)?
            .trimmingCharacters(in: .whitespaces)
        let media = (desc[kDADiskDescriptionMediaNameKey as String] as? String)?
            .trimmingCharacters(in: .whitespaces)
        return (isInternal, model?.isEmpty == false ? model! : (media ?? bsdName))
    }

    /// Mounted volumes as (volume BSD name, volume name), looked up once per discovery.
    private func mountedVolumes() -> [(bsd: String, name: String)] {
        guard let session else { return [] }
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil,
                                                         options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            guard let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, url as CFURL),
                  let desc = DADiskCopyDescription(disk) as? [String: Any],
                  let bsd = desc[kDADiskDescriptionMediaBSDNameKey as String] as? String,
                  let name = desc[kDADiskDescriptionVolumeNameKey as String] as? String
            else { return nil }
            return (bsd, name)
        }
    }

    /// Volume name(s) mounted from this physical disk, e.g. "Work SSD". Walks the registry
    /// under the disk (partitions, APFS container, volumes) and matches against mounted volumes.
    private func volumeLabel(media: io_object_t, bsd: String,
                             mounted: [(bsd: String, name: String)], fallback: String) -> String {
        var bsdNames: Set<String> = [bsd]
        var iterator: io_iterator_t = 0
        if IORegistryEntryCreateIterator(media, kIOServicePlane,
                                         IOOptionBits(kIORegistryIterateRecursively),
                                         &iterator) == KERN_SUCCESS {
            while case let entry = IOIteratorNext(iterator), entry != 0 {
                if let name = IORegistryEntryCreateCFProperty(
                        entry, "BSD Name" as CFString, kCFAllocatorDefault, 0)?
                        .takeRetainedValue() as? String {
                    bsdNames.insert(name)
                }
                IOObjectRelease(entry)
            }
            IOObjectRelease(iterator)
        }

        var names: [String] = []
        for volume in mounted where bsdNames.contains(volume.bsd) && !names.contains(volume.name) {
            names.append(volume.name)
        }
        return names.isEmpty ? fallback : names.joined(separator: ", ")
    }
}
