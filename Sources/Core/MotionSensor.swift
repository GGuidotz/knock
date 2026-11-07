// L'accelerometro e il giroscopio interni dei MacBook con Apple Silicon (M2 e successivi), letti come dispositivi HID
// del coprocessore dei sensori (AppleSPU, pagina 0xFF00: accelerometro uso 3, giroscopio uso 9). Non è un'API
// documentata: se non c'è o non risponde, Knock lavora con il solo microfono.
// Ogni rapporto è di 22 byte: x, y, z come interi a 32 bit little-endian agli scarti 6, 10, 14, in 1/65536 di g
// (o di grado/s per il giroscopio). Il flusso si accende impostando ReportInterval (microsecondi) sul driver.
// Misurato su MacBook Air M2: circa 800 campioni al secondo, senza permessi speciali.

import Foundation
import IOKit
import IOKit.hid

struct MotionSample {
    let t: Double
    let x: Double, y: Double, z: Double
}

final class MotionSensor {
    enum Kind: Int { case accel = 3, gyro = 9 }

    private let lock = NSLock()
    private var accel: [MotionSample] = []
    private var gyro: [MotionSample] = []
    private var managers: [IOHIDManager] = []
    private var contexts: [Context] = []
    private var thread: Thread?
    private var runLoop: CFRunLoop?
    private(set) var sampleCount = 0

    private final class Context {
        let kind: Kind
        weak var owner: MotionSensor?
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
        init(kind: Kind, owner: MotionSensor) { self.kind = kind; self.owner = owner }
        deinit { buffer.deallocate() }
    }

    /// Il Mac ha l'accelerometro (lo dice il registro di IOKit, senza aprirlo).
    static var isAvailable: Bool { !services(usage: Kind.accel.rawValue).isEmpty }

    var isRunning: Bool { thread != nil }

    func start() {
        guard thread == nil else { return }
        let t = Thread { [weak self] in
            guard let self else { return }
            self.runLoop = CFRunLoopGetCurrent()
            for kind in [Kind.accel, .gyro] { self.open(kind) }
            // Una sorgente vuota tiene vivo il ciclo anche se non si apre nessun dispositivo.
            var ctx = CFRunLoopSourceContext()
            let keepAlive = CFRunLoopSourceCreate(nil, 0, &ctx)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), keepAlive, .defaultMode)
            CFRunLoopRun()
        }
        t.name = "Knock motion"
        t.qualityOfService = .userInteractive
        thread = t
        t.start()
    }

    func stop() {
        guard let loop = runLoop else { thread = nil; return }
        CFRunLoopPerformBlock(loop, CFRunLoopMode.defaultMode.rawValue) { [self] in
            for m in managers { IOHIDManagerClose(m, IOOptionBits(kIOHIDOptionsTypeNone)) }
            managers.removeAll()
            contexts.removeAll()
            for kind in [Kind.accel, .gyro] { Self.setStreaming(kind, on: false) }
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
        CFRunLoopWakeUp(loop)
        runLoop = nil
        thread = nil
        lock.lock(); accel.removeAll(); gyro.removeAll(); lock.unlock()
    }

    /// I campioni tra `from` e `to` (secondi dell'orologio di sistema, come `MotionSensor.now`).
    func samples(_ kind: Kind, from: Double, to: Double) -> [MotionSample] {
        lock.lock(); defer { lock.unlock() }
        return (kind == .accel ? accel : gyro).filter { $0.t >= from && $0.t <= to }
    }

    // MARK: - Interno

    private func open(_ kind: Kind) {
        Self.setStreaming(kind, on: true)
        let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(m, [kIOHIDPrimaryUsagePageKey: 0xFF00, kIOHIDPrimaryUsageKey: kind.rawValue] as CFDictionary)
        IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone))
        managers.append(m)   // il gestore va tenuto vivo, altrimenti i dispositivi si chiudono
        guard let devices = IOHIDManagerCopyDevices(m) as? Set<IOHIDDevice> else { return }
        for d in devices {
            guard IOHIDDeviceOpen(d, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else { continue }
            let ctx = Context(kind: kind, owner: self)
            contexts.append(ctx)
            IOHIDDeviceRegisterInputReportCallback(d, ctx.buffer, 64, { context, _, _, _, _, r, length in
                guard length >= 18, let context else { return }
                let c = Unmanaged<Context>.fromOpaque(context).takeUnretainedValue()
                func value(_ o: Int) -> Double {
                    let bits = UInt32(r[o]) | UInt32(r[o + 1]) << 8 | UInt32(r[o + 2]) << 16 | UInt32(r[o + 3]) << 24
                    return Double(Int32(bitPattern: bits)) / 65536
                }
                c.owner?.add(c.kind, MotionSample(t: MotionSensor.now, x: value(6), y: value(10), z: value(14)))
            }, Unmanaged.passUnretained(ctx).toOpaque())
            IOHIDDeviceScheduleWithRunLoop(d, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        }
    }

    private func add(_ kind: Kind, _ s: MotionSample) {
        lock.lock(); defer { lock.unlock() }
        sampleCount &+= 1
        if kind == .accel {
            accel.append(s)
            if accel.count > 4000 { accel.removeFirst(2000) }   // circa 2,5 s
        } else {
            gyro.append(s)
            if gyro.count > 4000 { gyro.removeFirst(2000) }
        }
    }

    private static func services(usage: Int) -> [io_object_t] {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSPUHIDDriver"), &iter) == KERN_SUCCESS
        else { return [] }
        defer { IOObjectRelease(iter) }
        var out: [io_object_t] = []
        var svc = IOIteratorNext(iter)
        while svc != 0 {
            let page = IORegistryEntryCreateCFProperty(svc, "PrimaryUsagePage" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? Int
            let u = IORegistryEntryCreateCFProperty(svc, "PrimaryUsage" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? Int
            if page == 0xFF00 && u == usage { out.append(svc) } else { IOObjectRelease(svc) }
            svc = IOIteratorNext(iter)
        }
        return out
    }

    /// Accende (1 kHz) o spegne il flusso del sensore. Spento, torna come lo lascia macOS (ReportInterval 0).
    private static func setStreaming(_ kind: Kind, on: Bool) {
        for svc in services(usage: kind.rawValue) {
            if on {
                IORegistryEntrySetCFProperty(svc, "SensorPropertyReportingState" as CFString, 1 as CFNumber)
                IORegistryEntrySetCFProperty(svc, "SensorPropertyPowerState" as CFString, 1 as CFNumber)
                IORegistryEntrySetCFProperty(svc, "ReportInterval" as CFString, 1000 as CFNumber)
            } else {
                IORegistryEntrySetCFProperty(svc, "ReportInterval" as CFString, 0 as CFNumber)
            }
            IOObjectRelease(svc)
        }
    }

    /// Secondi dell'orologio di sistema (mach_absolute_time), lo stesso dei tempi audio.
    static var now: Double { hostSeconds(mach_absolute_time()) }

    static func hostSeconds(_ host: UInt64) -> Double {
        Double(host) * timebase / 1e9
    }

    private static let timebase: Double = {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        return Double(tb.numer) / Double(tb.denom)
    }()
}
