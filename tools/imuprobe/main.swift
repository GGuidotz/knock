// imuprobe: legge l'accelerometro interno (AppleSPU, Product "accel") e stampa
// frequenza e campioni. Fase 0 di Knock. Uso: ./imuprobe [secondi]
import Foundation
import IOKit
import IOKit.hid

let seconds = Double(CommandLine.arguments.dropFirst().first ?? "5") ?? 5
let usagePage = 0xFF00, usageAccel = 3

// 1. Attiva lo streaming impostando le proprietà sul driver (ReportInterval in microsecondi).
func enableStreaming() {
    var iter: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSPUHIDDriver"), &iter) == KERN_SUCCESS else {
        print("driver AppleSPUHIDDriver non trovato"); return
    }
    defer { IOObjectRelease(iter) }
    var svc = IOIteratorNext(iter)
    while svc != 0 {
        let up = IORegistryEntryCreateCFProperty(svc, "PrimaryUsagePage" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int
        let u = IORegistryEntryCreateCFProperty(svc, "PrimaryUsage" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int
        if up == usagePage && u == usageAccel {
            for (k, v) in [("SensorPropertyReportingState", 1), ("SensorPropertyPowerState", 1), ("ReportInterval", 1000)] {
                let r = IORegistryEntrySetCFProperty(svc, k as CFString, v as CFNumber)
                print("set \(k)=\(v): \(r == KERN_SUCCESS ? "ok" : String(format: "errore 0x%x", r))")
            }
        }
        IOObjectRelease(svc)
        svc = IOIteratorNext(iter)
    }
}

final class State {
    var count = 0
    var first: Double = 0
    var last: Double = 0
    var lengths = Set<Int>()
    var printed = 0
}
let state = State()

enableStreaming()

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(manager, [kIOHIDPrimaryUsagePageKey: usagePage, kIOHIDPrimaryUsageKey: usageAccel] as CFDictionary)
let openRes = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
print("IOHIDManagerOpen: \(openRes == kIOReturnSuccess ? "ok" : String(format: "errore 0x%x", openRes))")

guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, !devices.isEmpty else {
    print("nessun device accel visibile"); exit(1)
}
print("device accel trovati: \(devices.count)")

let bufSize = 64
for dev in devices {
    let r = IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone))
    print("IOHIDDeviceOpen: \(r == kIOReturnSuccess ? "ok" : String(format: "errore 0x%x", r))")
    let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
    IOHIDDeviceRegisterInputReportCallback(dev, buf, bufSize, { _, _, _, _, _, report, length in
        let now = CFAbsoluteTimeGetCurrent()
        if state.count == 0 { state.first = now }
        state.count += 1
        state.last = now
        state.lengths.insert(length)
        if state.printed < 5 || state.count % 200 == 0 {
            state.printed += 1
            var s = "len \(length): "
            for i in 0..<min(length, 24) { s += String(format: "%02x ", report[i]) }
            if length >= 18 {
                func i32(_ o: Int) -> Int32 {
                    Int32(bitPattern: UInt32(report[o]) | UInt32(report[o+1]) << 8 | UInt32(report[o+2]) << 16 | UInt32(report[o+3]) << 24)
                }
                s += String(format: " | x %.4f y %.4f z %.4f g", Double(i32(6)) / 65536, Double(i32(10)) / 65536, Double(i32(14)) / 65536)
            }
            print(s)
        }
    }, nil)
    IOHIDDeviceScheduleWithRunLoop(dev, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
}

CFRunLoopRunInMode(.defaultMode, seconds, false)
let dur = state.last - state.first
print("report ricevuti: \(state.count) in \(String(format: "%.2f", dur)) s, frequenza ~\(dur > 0 ? Int(Double(state.count - 1) / dur) : 0) Hz, lunghezze \(state.lengths.sorted())")
if state.count == 0 { print("nessun dato: probabilmente serve sudo (prova: sudo ./imuprobe)") }
