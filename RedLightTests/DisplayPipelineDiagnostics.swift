import Darwin
import XCTest

/// Environment-only diagnostic for future gamma retesting.
///
/// Do not automate a visible gamma-table assertion here: affected M5 Pro/Max
/// systems return success and read back the submitted table without changing
/// the display. A future retest must include a human-visible reference image.
final class DisplayPipelineDiagnostics: XCTestCase {
    func testRecordDisplayPipelineEnvironment() {
        let process = ProcessInfo.processInfo
        let cpu = sysctlString("machdep.cpu.brand_string") ?? "Unknown CPU"
        let summary = [
            "CPU: \(cpu)",
            "OS: \(process.operatingSystemVersionString)",
            "Gamma status: visually ineffective on M5 Pro/Max through tested macOS 26.5.1",
            "Feedback: FB22273730"
        ].joined(separator: "\n")

        print(summary)
        XCTAssertFalse(cpu.isEmpty)
    }

    private func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else {
            return nil
        }
        let bytes = buffer
            .prefix { $0 != 0 }
            .map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
