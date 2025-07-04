/**
 Copyright (c) 2018 Wolt Enterprises

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.
 */

import SwiftUI

public extension CGSize {
    /// The size of blur hash used by VirtualBuddy.
    ///
    /// - warning: This can't be changed without updating the server-side catalog groups with updated blur hashes matching this size!
    static let vbBlurHashSize = CGSize(width: Int.vbBlurHashSize, height: Int.vbBlurHashSize)
}

public extension Float {
    /// Default `punch` value used for blur hashes in VirtualBuddy.
    static let vbBlurHashPunch: Float = 1
}

public extension Image {
    init(blurHash: String, size: CGSize = .vbBlurHashSize, punch: Float = .vbBlurHashPunch) {
        if let decodedImage = NSImage(blurHash: blurHash, size: size, punch: punch) {
            self.init(nsImage: decodedImage)
        } else {
            self.init(nsImage: .blurHashPlaceholder(size: size))
        }
    }

    init(blurHash: BlurHashToken, punch: Float = .vbBlurHashPunch) {
        self.init(
            blurHash: blurHash.value,
            size: CGSize(width: blurHash.size, height: blurHash.size),
            punch: punch
        )
    }
}

private extension NSImage {
    static func blurHashPlaceholder(size: CGSize) -> NSImage {
        NSImage(size: size, flipped: true) { rect in
            NSColor.quaternaryLabelColor.setFill()
            rect.fill()
            return true
        }
    }
}

public extension NSImage {
    static func blurHash(_ token: BlurHashToken) -> NSImage {
        if let image = NSImage(blurHash: token.value, size: CGSize(width: token.size, height: token.size)) {
            image
        } else {
            .blurHashPlaceholder(size: CGSize(width: token.size, height: token.size))
        }
    }

    convenience init?(blurHash: String, size: CGSize, punch: Float = 1) {
        guard blurHash.count >= 6 else { return nil }

        let sizeFlag = String(blurHash[0]).decode83()
        let numY = (sizeFlag / 9) + 1
        let numX = (sizeFlag % 9) + 1

        let quantisedMaximumValue = String(blurHash[1]).decode83()
        let maximumValue = Float(quantisedMaximumValue + 1) / 166

        guard blurHash.count == 4 + 2 * numX * numY else { return nil }

        let colours: [(Float, Float, Float)] = (0 ..< numX * numY).map { i in
            if i == 0 {
                let value = String(blurHash[2 ..< 6]).decode83()
                return decodeDC(value)
            } else {
                let value = String(blurHash[4 + i * 2 ..< 4 + i * 2 + 2]).decode83()
                return decodeAC(value, maximumValue: maximumValue * punch)
            }
        }

        let width = Int(size.width)
        let height = Int(size.height)
        let bytesPerRow = width * 3
        guard let data = CFDataCreateMutable(kCFAllocatorDefault, bytesPerRow * height) else { return nil }
        CFDataSetLength(data, bytesPerRow * height)
        guard let pixels = CFDataGetMutableBytePtr(data) else { return nil }

        for y in 0 ..< height {
            for x in 0 ..< width {
                var r: Float = 0
                var g: Float = 0
                var b: Float = 0

                for j in 0 ..< numY {
                    for i in 0 ..< numX {
                        let basis = cos(Float.pi * Float(x) * Float(i) / Float(width)) * cos(Float.pi * Float(y) * Float(j) / Float(height))
                        let colour = colours[i + j * numX]
                        r += colour.0 * basis
                        g += colour.1 * basis
                        b += colour.2 * basis
                    }
                }

                let intR = UInt8(linearTosRGB(r))
                let intG = UInt8(linearTosRGB(g))
                let intB = UInt8(linearTosRGB(b))

                pixels[3 * x + 0 + y * bytesPerRow] = intR
                pixels[3 * x + 1 + y * bytesPerRow] = intG
                pixels[3 * x + 2 + y * bytesPerRow] = intB
            }
        }

        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)

        guard let provider = CGDataProvider(data: data) else { return nil }
        guard let cgImage = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 24, bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo, provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }

        self.init(cgImage: cgImage, size: size)
    }
}

private func decodeDC(_ value: Int) -> (Float, Float, Float) {
    let intR = value >> 16
    let intG = (value >> 8) & 255
    let intB = value & 255
    return (sRGBToLinear(intR), sRGBToLinear(intG), sRGBToLinear(intB))
}

private func decodeAC(_ value: Int, maximumValue: Float) -> (Float, Float, Float) {
    let quantR = value / (19 * 19)
    let quantG = (value / 19) % 19
    let quantB = value % 19

    let rgb = (
        signPow((Float(quantR) - 9) / 9, 2) * maximumValue,
        signPow((Float(quantG) - 9) / 9, 2) * maximumValue,
        signPow((Float(quantB) - 9) / 9, 2) * maximumValue
    )

    return rgb
}

private func signPow(_ value: Float, _ exp: Float) -> Float {
    return copysign(pow(abs(value), exp), value)
}

private func linearTosRGB(_ value: Float) -> Int {
    let v = max(0, min(1, value))
    if v <= 0.0031308 { return Int(v * 12.92 * 255 + 0.5) }
    else { return Int((1.055 * pow(v, 1 / 2.4) - 0.055) * 255 + 0.5) }
}

private func sRGBToLinear<Type: BinaryInteger>(_ value: Type) -> Float {
    let v = Float(Int64(value)) / 255
    if v <= 0.04045 { return v / 12.92 }
    else { return pow((v + 0.055) / 1.055, 2.4) }
}

private let encodeCharacters: [String] = {
    return "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#$%*+,-.:;=?@[]^_{|}~".map { String($0) }
}()

private let decodeCharacters: [String: Int] = {
    var dict: [String: Int] = [:]
    for (index, character) in encodeCharacters.enumerated() {
        dict[character] = index
    }
    return dict
}()

private extension String {
    func decode83() -> Int {
        var value: Int = 0
        for character in self {
            if let digit = decodeCharacters[String(character)] {
                value = value * 83 + digit
            }
        }
        return value
    }
}

private extension String {
    subscript (offset: Int) -> Character {
        return self[index(startIndex, offsetBy: offset)]
    }

    subscript (bounds: CountableClosedRange<Int>) -> Substring {
        let start = index(startIndex, offsetBy: bounds.lowerBound)
        let end = index(startIndex, offsetBy: bounds.upperBound)
        return self[start...end]
    }

    subscript (bounds: CountableRange<Int>) -> Substring {
        let start = index(startIndex, offsetBy: bounds.lowerBound)
        let end = index(startIndex, offsetBy: bounds.upperBound)
        return self[start..<end]
    }
}
