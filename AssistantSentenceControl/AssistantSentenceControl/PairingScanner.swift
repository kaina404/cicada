import SwiftUI
import Vision
import VisionKit

struct PairingScanner: UIViewControllerRepresentable {
    let onCode: (URL) -> Void
    let onUnavailable: () -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced, recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false, isPinchToZoomEnabled: false,
            isGuidanceEnabled: true, isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        guard !scanner.isScanning else { return }
        do { try scanner.startScanning() }
        catch { Task { onUnavailable() } }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode, onUnavailable: onUnavailable) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (URL) -> Void
        let onUnavailable: () -> Void

        init(onCode: @escaping (URL) -> Void, onUnavailable: @escaping () -> Void) {
            self.onCode = onCode
            self.onUnavailable = onUnavailable
        }

        func dataScanner(_ scanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            for case .barcode(let barcode) in addedItems {
                guard let string = barcode.payloadStringValue, let url = URL(string: string),
                      FloatingAnswerPairing(link: url) != nil else { continue }
                scanner.stopScanning()
                onCode(url)
                break
            }
        }

        func dataScanner(_ scanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            onUnavailable()
        }
    }
}
