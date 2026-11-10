import AVFoundation
import SwiftUI
import UIKit
import Vision

/// Reads barcodes and QR codes from a still image (photo library or screenshot).
enum BarcodeReader {
    struct Found: Sendable {
        let payload: String
        let isUPCE: Bool
    }

    static func firstCode(in image: UIImage) async -> Found? {
        guard let cg = image.normalizedOrientation().cgImage else { return nil }
        return await Task.detached(priority: .userInitiated) {
            let request = VNDetectBarcodesRequest()
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            try? handler.perform([request])
            let results = (request.results ?? []).filter { $0.payloadStringValue?.isEmpty == false }
            // Prefer retail barcodes over QR codes when both are present.
            let retail: Set<VNBarcodeSymbology> = [.ean13, .ean8, .upce, .itf14, .gs1DataBar, .gs1DataBarExpanded]
            if let best = results.first(where: { retail.contains($0.symbology) }) ?? results.first,
               let payload = best.payloadStringValue {
                return Found(payload: payload, isUPCE: best.symbology == .upce)
            }
            // Fallback QR reader (Vision's detector can be unavailable, e.g. in the Simulator).
            let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                      options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
            let features = detector?.features(in: CIImage(cgImage: cg)) ?? []
            return features.compactMap { ($0 as? CIQRCodeFeature)?.messageString }.first
                .map { Found(payload: $0, isUPCE: false) }
        }.value
    }
}

final class CameraController: NSObject, ObservableObject {
    enum State: Equatable {
        case idle, running
        case unavailable(String)
    }

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let metadataOutput = AVCaptureMetadataOutput()
    private let queue = DispatchQueue(label: "gibbon.camera")
    private var device: AVCaptureDevice?
    /// The code most recently handled and when it was last in view. The same code is ignored until it has been
    /// out of view for `repeatCooldown`, so a barcode held in frame isn't looked up again and again.
    private var lastBarcode: String?
    private var lastSeen = Date.distantPast
    private let repeatCooldown: TimeInterval = 4
    private var isCapturing = false

    @Published var state: State = .idle
    @Published var torchOn = false

    var onPhoto: ((UIImage) -> Void)?
    var onBarcode: ((_ code: String, _ isUPCE: Bool) -> Void)?
    var detectBarcodes = false

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted { self.configureAndRun() } else { self.set(.unavailable("Camera access was denied. You can enable it in Settings.")) }
            }
        default:
            set(.unavailable("Camera access is off. Enable it in Settings → White Cheeked Gibbon → Camera."))
        }
    }

    private func configureAndRun() {
        queue.async {
            if self.session.inputs.isEmpty {
                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                      let input = try? AVCaptureDeviceInput(device: device) else {
                    self.set(.unavailable("No camera is available on this device. Use the photo library instead."))
                    return
                }
                self.session.beginConfiguration()
                self.session.sessionPreset = .photo
                if self.session.canAddInput(input) { self.session.addInput(input) }
                if self.session.canAddOutput(self.photoOutput) { self.session.addOutput(self.photoOutput) }
                if self.session.canAddOutput(self.metadataOutput) {
                    self.session.addOutput(self.metadataOutput)
                    self.metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
                    let wanted: [AVMetadataObject.ObjectType] = [.ean13, .ean8, .upce, .code128, .code39, .itf14, .qr, .dataMatrix]
                    self.metadataOutput.metadataObjectTypes = wanted.filter { self.metadataOutput.availableMetadataObjectTypes.contains($0) }
                }
                self.session.commitConfiguration()
                self.device = device
                if device.isFocusModeSupported(.continuousAutoFocus), (try? device.lockForConfiguration()) != nil {
                    device.focusMode = .continuousAutoFocus
                    device.unlockForConfiguration()
                }
            }
            if !self.session.isRunning { self.session.startRunning() }
            self.set(.running)
        }
    }

    func stop() {
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    func capture() {
        guard state == .running, !isCapturing else { return }
        isCapturing = true
        let settings = AVCapturePhotoSettings()
        if let device, device.hasFlash, torchOn { settings.flashMode = .on }
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func toggleTorch() {
        torchOn.toggle()
        guard let device, device.hasTorch, (try? device.lockForConfiguration()) != nil else { return }
        device.torchMode = torchOn ? .on : .off
        device.unlockForConfiguration()
    }

    func resetBarcode() {
        lastBarcode = nil
        lastSeen = .distantPast
    }

    private func set(_ s: State) {
        DispatchQueue.main.async { self.state = s }
    }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let image = photo.fileDataRepresentation().flatMap(UIImage.init(data:))
        DispatchQueue.main.async {
            self.isCapturing = false
            if let image { self.onPhoto?(image) }
        }
    }
}

extension CameraController: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard detectBarcodes,
              let object = objects.first as? AVMetadataMachineReadableCodeObject,
              let code = object.stringValue else { return }
        let now = Date()
        if code == lastBarcode && now.timeIntervalSince(lastSeen) < repeatCooldown {
            lastSeen = now   // still in view: keep ignoring it
            return
        }
        lastBarcode = code
        lastSeen = now
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onBarcode?(code, object.type == .upce)
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.previewLayer.session = session
        v.previewLayer.videoGravity = .resizeAspectFill
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
