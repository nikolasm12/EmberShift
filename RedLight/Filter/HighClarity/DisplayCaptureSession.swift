@preconcurrency import ScreenCaptureKit
import AVFoundation
import CoreVideo
import Foundation

final class DisplayCaptureSession: NSObject,
    SCStreamOutput,
    SCStreamDelegate,
    @unchecked Sendable
{
    private let frameRenderer: MetalFrameRenderer
    private let outputQueue: DispatchQueue
    private let firstFrameLock = NSLock()
    private var deliveredFirstFrame = false
    private var stream: SCStream!
    private let onFirstFrame: @Sendable () -> Void
    private let onFailure: @Sendable (String) -> Void

    init(
        display: SCDisplay,
        excludingApplications: [SCRunningApplication],
        captureWidth: Int,
        captureHeight: Int,
        frameRate: Int,
        frameRenderer: MetalFrameRenderer,
        onFirstFrame: @escaping @Sendable () -> Void,
        onFailure: @escaping @Sendable (String) -> Void
    ) {
        self.frameRenderer = frameRenderer
        self.onFirstFrame = onFirstFrame
        self.onFailure = onFailure
        outputQueue = DispatchQueue(
            label: "com.nick.RedLight.capture.\(display.displayID)",
            qos: .userInteractive
        )
        super.init()

        let filter = SCContentFilter(
            display: display,
            excludingApplications: excludingApplications,
            exceptingWindows: []
        )
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, captureWidth)
        configuration.height = max(1, captureHeight)
        configuration.minimumFrameInterval = CMTime(
            value: 1,
            timescale: CMTimeScale(max(1, frameRate))
        )
        configuration.queueDepth = 3
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = false
        configuration.capturesAudio = false
        stream = SCStream(
            filter: filter,
            configuration: configuration,
            delegate: self
        )
    }

    func start() async throws {
        try stream.addStreamOutput(
            self,
            type: .screen,
            sampleHandlerQueue: outputQueue
        )
        try await stream.startCapture()
    }

    func stop() async {
        try? await stream.stopCapture()
        try? stream.removeStreamOutput(self, type: .screen)
    }

    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .screen,
              sampleBuffer.isValid,
              let pixelBuffer = sampleBuffer.imageBuffer,
              frameRenderer.render(pixelBuffer: pixelBuffer)
        else { return }

        firstFrameLock.lock()
        let isFirstFrame = !deliveredFirstFrame
        deliveredFirstFrame = true
        firstFrameLock.unlock()
        if isFirstFrame {
            onFirstFrame()
        }
    }

    nonisolated func stream(
        _ stream: SCStream,
        didStopWithError error: Error
    ) {
        onFailure(error.localizedDescription)
    }
}
