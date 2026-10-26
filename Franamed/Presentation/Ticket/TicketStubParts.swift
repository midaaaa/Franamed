//
//  TicketStubParts.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 26.10.2026.
//

import CoreImage
import SwiftUI

struct TicketStubLayout: ViewModifier {
    var serial: String?

    @Environment(\.ticketEdgeStyle) private var edgeStyle

    func body(content: Content) -> some View {
        content
            .frame(height: TicketStyle.stubBodyHeight, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, TicketStyle.stubSideInset - TicketStyle.stubPadding)
            .frame(height: TicketStubMetrics.contentHeight, alignment: .top)
            .overlay(alignment: .bottom) {
                if let serial {
                    Text(serial)
                        .font(TicketStyle.serial)
                        .tracking(TicketStyle.serialTracking)
                        .lineLimit(1)
                        .frame(height: TicketStyle.serialBand)
                        .offset(y: TicketStubMetrics.serialOffset(edgeStyle: edgeStyle))
                }
            }
            .foregroundStyle(Color.black)
    }
}

struct TicketRule: View {
    var body: some View {
        Rectangle().frame(height: TicketStyle.ruleWidth)
    }
}

struct TicketStubHeader<Accessory: View>: View {
    let title: String
    let media: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(TicketStyle.name)
                    .lineLimit(1)
                    .minimumScaleFactor(TicketStyle.minimumScale)
                Spacer(minLength: TicketStyle.headerSpacing)
                HStack(spacing: TicketStyle.headerSpacing) {
                    Text(media.uppercased())
                        .font(TicketStyle.media)
                        .tracking(TicketStyle.mediaTracking)
                        .lineLimit(1)
                    accessory
                }
            }
            TicketRule()
        }
    }
}

extension TicketStubHeader where Accessory == EmptyView {
    init(title: String, media: String) {
        self.init(title: title, media: media) { EmptyView() }
    }
}

struct TicketFieldCell<Value: View>: View {
    let label: String
    @ViewBuilder var value: Value

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(TicketStyle.fieldLabel)
                .tracking(TicketStyle.fieldLabelTracking)
                .lineLimit(1)
                .minimumScaleFactor(TicketStyle.minimumScale)
            value
        }
    }
}

struct TicketNameList: View {
    let names: [String]
    var separator = ", "

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(Array(stride(from: names.count, through: 1, by: -1)), id: \.self) { shown in
                Text(label(showing: shown))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            HStack(spacing: 4) {
                Text(names.first ?? "")
                    .lineLimit(1)
                    .truncationMode(.tail)
                if names.count > 1 {
                    Text("+\(names.count - 1)").fixedSize()
                }
            }
        }
    }

    private func label(showing count: Int) -> String {
        let shown = names.prefix(count).joined(separator: separator)
        let remaining = names.count - count
        return remaining > 0 ? "\(shown) +\(remaining)" : shown
    }
}

struct TicketPlayCode: View {
    let caption: String
    let serial: String

    var body: some View {
        ZStack {
            TicketCodeImage(image: TicketCode.linear(serial.replacingOccurrences(of: " ", with: "")))
                .frame(height: TicketStyle.codeHeight)
            Text(caption)
                .font(TicketStyle.codeCaption)
                .tracking(TicketStyle.codeCaptionTracking)
                .padding(.leading, TicketStyle.codeCaptionTracking)
                .lineLimit(1)
                .frame(height: 12)
                .padding(.horizontal, 9)
                .background(TicketStyle.paper)
        }
        .frame(maxWidth: .infinity)
    }
}

struct TicketCodeImage: View {
    let image: CGImage?

    var body: some View {
        if let image {
            Image(decorative: image, scale: 1)
                .renderingMode(.template)
                .interpolation(.none)
                .resizable()
        }
    }
}

// MARK: - Code images

@MainActor
enum TicketCode {
    private static let context = CIContext()
    private static var cache: [String: CGImage] = [:]

    static func linear(_ message: String) -> CGImage? {
        image(filter: "CICode128BarcodeGenerator", message: message, parameters: ["inputQuietSpace": 0], trims: false)
    }

    static func qr(_ message: String) -> CGImage? {
        image(filter: "CIQRCodeGenerator", message: message, parameters: ["inputCorrectionLevel": "L"], trims: true)
    }

    private static func image(filter name: String, message: String, parameters: [String: Any], trims: Bool) -> CGImage? {
        let key = name + message
        if let cached = cache[key] { return cached }
        guard let filter = CIFilter(name: name) else { return nil }
        filter.setValue(Data(message.utf8), forKey: "inputMessage")
        for (key, value) in parameters { filter.setValue(value, forKey: key) }
        guard let output = filter.outputImage,
              var printed = context.createCGImage(output, from: output.extent) else { return nil }
        if trims, let cropped = cropToInk(printed) { printed = cropped }
        let mask = CIImage(cgImage: printed).applyingFilter("CIColorInvert").applyingFilter("CIMaskToAlpha")
        guard let result = context.createCGImage(mask, from: mask.extent) else { return nil }
        cache[key] = result
        return result
    }

    private static func cropToInk(_ image: CGImage) -> CGImage? {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 255, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where pixels[y * width + x] < 128 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return image.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
    }
}
