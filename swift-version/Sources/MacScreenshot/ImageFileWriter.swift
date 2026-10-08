import Clibwebp
import Cocoa
import Compression
import ImageIO
import UniformTypeIdentifiers

/// 把截图编码成文件数据。PNG 默认走减色索引图；剪贴板不走这里的有损路径。
enum ImageFileWriter {

    static func losslessPNG(_ image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    static func data(for image: CGImage, format: ImageFileFormat, quality: Int) -> Data? {
        switch format {
        case .losslessPng:
            return losslessPNG(image)
        case .png:
            guard let lossless = losslessPNG(image) else { return nil }
            guard let quantized = quantizedPNG(image) else { return lossless }
            // 减色后更大时保留无损文件，避免照片类画面越压越大。
            return quantized.count < lossless.count ? quantized : lossless
        case .jpeg:
            return imageIOData(image, type: UTType.jpeg.identifier as CFString, quality: quality)
        case .webp:
            return webpData(image, quality: quality)
        }
    }

    /// 系统 ImageIO 不能写 WebP，用 libwebp 编码。
    private static func webpData(_ image: CGImage, quality: Int) -> Data? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0, width <= 20_000, height <= 20_000,
              let pixels = straightRGBA(image, width: width, height: height) else { return nil }
        var output: UnsafeMutablePointer<UInt8>?
        let qualityFactor = Float(min(100, max(1, quality)))
        let size = pixels.withUnsafeBufferPointer { buffer -> Int in
            guard let base = buffer.baseAddress else { return 0 }
            return WebPEncodeRGBA(base, Int32(width), Int32(height), Int32(width * 4), qualityFactor, &output)
        }
        guard size > 0, let output else { return nil }
        let data = Data(bytes: output, count: size)
        WebPFree(output)
        return data
    }

    private static func imageIOData(_ image: CGImage, type: CFString, quality: Int) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, type, 1, nil) else { return nil }
        let fraction = CGFloat(min(100, max(1, quality))) / 100
        let props = [kCGImageDestinationLossyCompressionQuality: fraction] as CFDictionary
        CGImageDestinationAddImage(dest, image, props)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    /// 合并相近颜色，写成带透明通道的 8 位索引 PNG。颜色不超过 256 时结果仍是无损的。
    private static func quantizedPNG(_ image: CGImage) -> Data? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0, width <= 20_000, height <= 20_000 else { return nil }
        guard var pixels = straightRGBA(image, width: width, height: height) else { return nil }

        var histogram: [UInt32: Int] = [:]
        histogram.reserveCapacity(min(pixels.count / 4, 65_536))
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let key = pack(pixels[index], pixels[index + 1], pixels[index + 2], pixels[index + 3])
            histogram[key, default: 0] += 1
        }

        let coarsened = histogram.count > 65_536
        if coarsened {
            var folded: [UInt32: Int] = [:]
            folded.reserveCapacity(65_536)
            for (key, count) in histogram {
                folded[coarsen(key), default: 0] += count
            }
            histogram = folded
        }

        var entries = histogram.map { key, count in
            CountedColor(key: key, count: count)
        }
        let palette: [CountedColor]
        var indexOf: [UInt32: UInt8] = [:]
        indexOf.reserveCapacity(entries.count)
        if entries.count <= 256 {
            palette = entries
            for (offset, entry) in entries.enumerated() {
                indexOf[entry.key] = UInt8(offset)
            }
        } else {
            palette = medianCut(&entries)
            for key in histogram.keys {
                indexOf[key] = nearestIndex(key, palette: palette)
            }
        }
        guard !palette.isEmpty, palette.count <= 256 else { return nil }

        let indexes = indexBytes(
            pixels: pixels,
            width: width,
            height: height,
            coarsened: coarsened,
            indexOf: indexOf
        )
        pixels.removeAll(keepingCapacity: false)
        return encodeIndexedPNG(width: width, height: height, palette: palette, indexes: indexes)
    }

    /// 画进 RGBA 缓冲再还原预乘，得到从上到下的直线 Alpha。
    private static func straightRGBA(_ image: CGImage, width: Int, height: Int) -> [UInt8]? {
        let rowBytes = width * 4
        var data = [UInt8](repeating: 0, count: height * rowBytes)
        let ok = data.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: rowBytes,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard ok else { return nil }
        // 位图第 0 行就是图像顶部，和 PNG 扫描线顺序一致。
        for index in stride(from: 0, to: data.count, by: 4) {
            let alpha = data[index + 3]
            data[index] = unpremultiply(data[index], alpha)
            data[index + 1] = unpremultiply(data[index + 1], alpha)
            data[index + 2] = unpremultiply(data[index + 2], alpha)
        }
        return data
    }

    private static func indexBytes(
        pixels: [UInt8],
        width: Int,
        height: Int,
        coarsened: Bool,
        indexOf: [UInt32: UInt8]
    ) -> [UInt8] {
        var indexes = [UInt8](repeating: 0, count: width * height)
        for i in 0..<(width * height) {
            let o = i * 4
            var key = pack(pixels[o], pixels[o + 1], pixels[o + 2], pixels[o + 3])
            if coarsened { key = coarsen(key) }
            indexes[i] = indexOf[key] ?? 0
        }
        return indexes
    }

    private static func encodeIndexedPNG(width: Int, height: Int, palette: [CountedColor], indexes: [UInt8]) -> Data? {
        var file = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        var ihdr = Data()
        ihdr.append(be32(UInt32(width)))
        ihdr.append(be32(UInt32(height)))
        ihdr.append(contentsOf: [8, 3, 0, 0, 0])
        file.append(chunk("IHDR", ihdr))

        var plte = Data()
        plte.reserveCapacity(palette.count * 3)
        var trns = Data()
        var hasPartialAlpha = false
        for entry in palette {
            let (r, g, b, a) = unpack(entry.key)
            plte.append(contentsOf: [r, g, b])
            trns.append(a)
            if a != 255 { hasPartialAlpha = true }
        }
        file.append(chunk("PLTE", plte))
        if hasPartialAlpha {
            file.append(chunk("tRNS", trns))
        }

        var raw = [UInt8]()
        raw.reserveCapacity(height * (width + 1))
        for y in 0..<height {
            raw.append(0)
            raw.append(contentsOf: indexes[(y * width)..<((y + 1) * width)])
        }
        guard let zlib = zlibCompress(raw) else { return nil }
        file.append(chunk("IDAT", zlib))
        file.append(chunk("IEND", Data()))
        return file
    }

    private static func zlibCompress(_ source: [UInt8]) -> Data? {
        guard !source.isEmpty else { return nil }
        var capacity = source.count + source.count / 8 + 64
        for _ in 0..<3 {
            var destination = [UInt8](repeating: 0, count: capacity)
            let written = source.withUnsafeBufferPointer { src in
                destination.withUnsafeMutableBufferPointer { dst in
                    compression_encode_buffer(
                        dst.baseAddress!, dst.count,
                        src.baseAddress!, src.count,
                        nil,
                        COMPRESSION_ZLIB
                    )
                }
            }
            if written > 0 {
                // Compression 框架给出的是裸 deflate。PNG 的 IDAT 必须是 zlib 包装。
                var result = Data([0x78, 0x9C])
                result.append(contentsOf: destination.prefix(written))
                result.append(be32(adler32(source)))
                return result
            }
            capacity *= 2
        }
        return nil
    }

    private static func adler32(_ data: [UInt8]) -> UInt32 {
        var a: UInt32 = 1
        var b: UInt32 = 0
        for byte in data {
            a = (a + UInt32(byte)) % 65521
            b = (b + a) % 65521
        }
        return (b << 16) | a
    }

    private static func chunk(_ type: String, _ payload: Data) -> Data {
        var body = Data(type.utf8)
        body.append(payload)
        var out = Data()
        out.append(be32(UInt32(payload.count)))
        out.append(body)
        out.append(be32(pngCRC(body)))
        return out
    }

    private static func pngCRC(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                let mask: UInt32 = (crc & 1) == 1 ? 0xEDB8_8320 : 0
                crc = (crc >> 1) ^ mask
            }
        }
        return crc ^ 0xFFFF_FFFF
    }

    private static func be32(_ value: UInt32) -> Data {
        Data([
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF),
        ])
    }

    private struct CountedColor {
        var key: UInt32
        var count: Int
    }

    private struct ColorBox {
        var start: Int
        var end: Int
    }

    /// 反复把跨度最大的一组颜色从中间切开，直到最多 256 色。
    private static func medianCut(_ colors: inout [CountedColor]) -> [CountedColor] {
        guard !colors.isEmpty else { return [] }
        var boxes = [ColorBox(start: 0, end: colors.count)]
        while boxes.count < 256 {
            var best: Int?
            var bestRange = 0
            var bestAxis = 0
            for (index, box) in boxes.enumerated() {
                guard box.end - box.start >= 2 else { continue }
                let (axis, range) = widestAxis(colors, box)
                if range > bestRange {
                    bestRange = range
                    bestAxis = axis
                    best = index
                }
            }
            guard let index = best else { break }
            let box = boxes.remove(at: index)
            let sorted = colors[box.start..<box.end].sorted { component($0.key, bestAxis) < component($1.key, bestAxis) }
            colors.replaceSubrange(box.start..<box.end, with: sorted)
            let mid = weightedSplit(colors, box)
            boxes.append(ColorBox(start: box.start, end: mid))
            boxes.append(ColorBox(start: mid, end: box.end))
        }
        return boxes.map { average(colors, $0) }
    }

    private static func widestAxis(_ colors: [CountedColor], _ box: ColorBox) -> (axis: Int, range: Int) {
        var bestAxis = 0
        var bestRange = 0
        for axis in 0..<4 {
            var low = 255
            var high = 0
            for index in box.start..<box.end {
                let value = component(colors[index].key, axis)
                low = min(low, value)
                high = max(high, value)
            }
            let range = high - low
            if range > bestRange {
                bestRange = range
                bestAxis = axis
            }
        }
        return (bestAxis, bestRange)
    }

    private static func weightedSplit(_ colors: [CountedColor], _ box: ColorBox) -> Int {
        let total = colors[box.start..<box.end].reduce(0) { $0 + $1.count }
        var running = 0
        let half = max(total / 2, 1)
        for index in box.start..<(box.end - 1) {
            running += colors[index].count
            if running >= half {
                return index + 1
            }
        }
        return box.end - 1
    }

    private static func average(_ colors: [CountedColor], _ box: ColorBox) -> CountedColor {
        var sr = 0, sg = 0, sb = 0, sa = 0, sn = 0
        for index in box.start..<box.end {
            let (r, g, b, a) = unpack(colors[index].key)
            let n = colors[index].count
            sr += Int(r) * n
            sg += Int(g) * n
            sb += Int(b) * n
            sa += Int(a) * n
            sn += n
        }
        let n = max(sn, 1)
        return CountedColor(
            key: pack(
                UInt8(sr / n),
                UInt8(sg / n),
                UInt8(sb / n),
                UInt8(sa / n)
            ),
            count: sn
        )
    }

    private static func nearestIndex(_ key: UInt32, palette: [CountedColor]) -> UInt8 {
        let (r, g, b, a) = unpack(key)
        var best = 0
        var bestDistance = Int.max
        for (index, entry) in palette.enumerated() {
            let (pr, pg, pb, pa) = unpack(entry.key)
            let dr = Int(r) - Int(pr)
            let dg = Int(g) - Int(pg)
            let db = Int(b) - Int(pb)
            let da = Int(a) - Int(pa)
            let distance = dr * dr + dg * dg + db * db + da * da
            if distance < bestDistance {
                bestDistance = distance
                best = index
                if distance == 0 { break }
            }
        }
        return UInt8(best)
    }

    private static func component(_ key: UInt32, _ axis: Int) -> Int {
        Int((key >> UInt32(8 * (3 - axis))) & 0xFF)
    }

    /// 颜色太多时丢掉低位，把直方图收进可切分的规模。
    private static func coarsen(_ key: UInt32) -> UInt32 {
        let (r, g, b, a) = unpack(key)
        return pack(r & 0xF8, g & 0xF8, b & 0xF8, a & 0xF8)
    }

    private static func pack(_ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8) -> UInt32 {
        (UInt32(r) << 24) | (UInt32(g) << 16) | (UInt32(b) << 8) | UInt32(a)
    }

    private static func unpack(_ key: UInt32) -> (UInt8, UInt8, UInt8, UInt8) {
        (
            UInt8((key >> 24) & 0xFF),
            UInt8((key >> 16) & 0xFF),
            UInt8((key >> 8) & 0xFF),
            UInt8(key & 0xFF)
        )
    }

    private static func unpremultiply(_ channel: UInt8, _ alpha: UInt8) -> UInt8 {
        guard alpha != 0 else { return 0 }
        guard alpha != 255 else { return channel }
        return UInt8(min(255, (Int(channel) * 255 + Int(alpha) / 2) / Int(alpha)))
    }
}
