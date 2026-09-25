import CoreGraphics
import CoreML
import Accelerate
import Foundation
import VideoToolbox

/// An oriented digit-row locator: a Core ML segmenter emitting PixelLink's
/// pixel and link maps (Deng et al., AAAI 2018; trained by
/// `ml/pump-reader/src/pump_reader/segtrain.py`), decoded here the way
/// `segnet.decode` does in Python - pixel and link thresholds, union-find over
/// positive pixels joined by a positive link in either direction, one
/// minimum-area rectangle per component, a size floor, and the component's mean
/// pixel probability as its confidence. Its rows are quads that follow a turned
/// display, where the object detector's are upright boxes. Reached through
/// `PumpRowDetector.load(contentsOf:)`; the app bundles it as its row locator
/// (`RowSeg.mlpackage`).
struct PumpRowSegmenter: @unchecked Sendable {
    static let inputSize = 512
    static let gridSize = 256
    /// Chosen on the validation stills by `segeval`; the size floor is the train
    /// split's 1st percentiles on the output grid.
    let pixelThreshold: Float
    let linkThreshold: Float
    let minimumShortSide: Double
    let minimumArea: Double
    private let model: MLModel

    static let neighbours: [(dy: Int, dx: Int)] = [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)]

    init(contentsOf url: URL, pixelThreshold: Float = 0.9, linkThreshold: Float = 0.8,
         minimumShortSide: Double = 4.94, minimumArea: Double = 57.0) throws {
        let compiled = url.pathExtension == "mlmodelc" ? url : try MLModel.compileModel(at: url)
        // CPU and Neural Engine, not the GPU: on the iOS simulator the GPU path
        // returns all-zero maps for this float16 program while the CPU path
        // reads the same frame correctly, and the Neural Engine is the phone's
        // fast path anyway.
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndNeuralEngine
        model = try MLModel(contentsOf: compiled, configuration: configuration)
        self.pixelThreshold = pixelThreshold
        self.linkThreshold = linkThreshold
        self.minimumShortSide = minimumShortSide
        self.minimumArea = minimumArea
    }

    func rows(in image: CGImage) -> [PumpRowDetector.Row] {
        let w = image.width, h = image.height
        let scale = Double(Self.inputSize) / Double(max(w, h))
        guard let buffer = Self.letterbox(image, scale: scale),
              let input = try? MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(pixelBuffer: buffer)]),
              let output = try? model.prediction(from: input),
              let maps = output.featureValue(for: "maps")?.multiArrayValue else { return [] }
        return decode(Self.floats(maps)).map { quad, confidence in
            PumpRowDetector.Row(
                quad: quad.map { CGPoint(x: $0.x * 2 / scale / Double(w), y: $0.y * 2 / scale / Double(h)) },
                confidence: confidence)
        }
    }

    /// The same rows from a camera frame: the preview hands the locator pixel
    /// buffers, and the segmenter reads a decoded image.
    func rows(in pixelBuffer: CVPixelBuffer) -> [PumpRowDetector.Row] {
        var image: CGImage?
        VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &image)
        return image.map { rows(in: $0) } ?? []
    }

    /// The maps as floats, read straight from the array's storage when it is
    /// laid out contiguously: element subscripting boxes every one of the
    /// 589 824 values. Any other layout is read element by element.
    static func floats(_ maps: MLMultiArray) -> [Float] {
        let count = maps.count
        var expected = 1
        var contiguous = true
        for (dimension, stride) in zip(maps.shape.reversed(), maps.strides.reversed()) {
            if stride.intValue != expected { contiguous = false; break }
            expected *= dimension.intValue
        }
        guard contiguous else { return (0..<count).map { maps[$0].floatValue } }
        switch maps.dataType {
        case .float16:
            var out = [Float](repeating: 0, count: count)
            out.withUnsafeMutableBufferPointer { dst in
                var src = vImage_Buffer(data: maps.dataPointer, height: 1, width: vImagePixelCount(count),
                                        rowBytes: count * 2)
                var dest = vImage_Buffer(data: dst.baseAddress, height: 1, width: vImagePixelCount(count),
                                         rowBytes: count * 4)
                vImageConvert_Planar16FtoPlanarF(&src, &dest, vImage_Flags(kvImageNoFlags))
            }
            return out
        case .float32:
            return Array(UnsafeBufferPointer(start: maps.dataPointer.assumingMemoryBound(to: Float.self), count: count))
        default:
            return (0..<count).map { maps[$0].floatValue }
        }
    }

    /// Quads on the output grid (TL, TR, BR, BL) with their confidence.
    func decode(_ maps: [Float]) -> [([CGPoint], Double)] {
        let n = Self.gridSize
        func pixel(_ y: Int, _ x: Int) -> Float { maps[y * n + x] }
        func link(_ k: Int, _ y: Int, _ x: Int) -> Float { maps[(1 + k) * n * n + y * n + x] }
        var parent = Array(0..<(n * n))
        func find(_ i: Int) -> Int {
            var i = i
            while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }
            return i
        }
        let positive = (0..<(n * n)).filter { maps[$0] >= pixelThreshold }
        for (k, nb) in Self.neighbours.enumerated() where (nb.dy, nb.dx) > (0, 0) {
            let reverse = Self.neighbours.firstIndex { $0.dy == -nb.dy && $0.dx == -nb.dx }!
            for i in positive {
                let y = i / n, x = i % n, ny = y + nb.dy, nx = x + nb.dx
                guard ny >= 0, ny < n, nx >= 0, nx < n, pixel(ny, nx) >= pixelThreshold else { continue }
                if link(k, y, x) >= linkThreshold || link(reverse, ny, nx) >= linkThreshold {
                    let a = find(i), b = find(ny * n + nx)
                    if a != b { parent[a] = b }
                }
            }
        }
        var groups: [Int: [Int]] = [:]
        for i in positive { groups[find(i), default: []].append(i) }
        var out: [([CGPoint], Double)] = []
        for members in groups.values {
            let points = members.map { CGPoint(x: Double($0 % n), y: Double($0 / n)) }
            guard let rect = Self.minAreaRect(points) else { continue }
            // A pixel is a cell of width 1: the rectangle grows by one cell.
            let long = rect.long + 1, short = rect.short + 1
            guard short >= minimumShortSide, long * short >= minimumArea else { continue }
            let c = rect.centre, d = rect.direction, m = CGPoint(x: -d.y, y: d.x)
            let corners = [(-1.0, -1.0), (1.0, -1.0), (1.0, 1.0), (-1.0, 1.0)].map { sa, sc in
                CGPoint(x: c.x + sa * long / 2 * d.x + sc * short / 2 * m.x,
                        y: c.y + sa * long / 2 * d.y + sc * short / 2 * m.y)
            }
            let confidence = members.reduce(0.0) { $0 + Double(maps[$1]) } / Double(members.count)
            out.append((Self.readingOrder(corners), confidence))
        }
        return out
    }

    struct Rect { let centre: CGPoint; let direction: CGPoint; let long: Double; let short: Double }

    /// The minimum-area rectangle over `points` by rotating calipers on the
    /// convex hull; `direction` is the unit vector along its long side.
    static func minAreaRect(_ points: [CGPoint]) -> Rect? {
        let hull = convexHull(points)
        guard !hull.isEmpty else { return nil }
        if hull.count == 1 { return Rect(centre: hull[0], direction: CGPoint(x: 1, y: 0), long: 0, short: 0) }
        var best: (area: Double, rect: Rect)?
        for i in 0..<hull.count {
            let a = hull[i], b = hull[(i + 1) % hull.count]
            let len = hypot(b.x - a.x, b.y - a.y)
            guard len > 0 else { continue }
            let u = CGPoint(x: (b.x - a.x) / len, y: (b.y - a.y) / len), v = CGPoint(x: -u.y, y: u.x)
            var minU = Double.infinity, maxU = -Double.infinity, minV = Double.infinity, maxV = -Double.infinity
            for p in hull {
                let pu = p.x * u.x + p.y * u.y, pv = p.x * v.x + p.y * v.y
                minU = min(minU, pu); maxU = max(maxU, pu); minV = min(minV, pv); maxV = max(maxV, pv)
            }
            let area = (maxU - minU) * (maxV - minV)
            if best == nil || area < best!.area {
                let cu = (minU + maxU) / 2, cv = (minV + maxV) / 2
                let centre = CGPoint(x: cu * u.x + cv * v.x, y: cu * u.y + cv * v.y)
                let wu = maxU - minU, wv = maxV - minV
                let rect = wu >= wv ? Rect(centre: centre, direction: u, long: wu, short: wv)
                                    : Rect(centre: centre, direction: v, long: wv, short: wu)
                best = (area, rect)
            }
        }
        return best?.rect ?? Rect(centre: hull[0], direction: CGPoint(x: 1, y: 0), long: 0, short: 0)
    }

    /// Andrew's monotone chain.
    static func convexHull(_ points: [CGPoint]) -> [CGPoint] {
        let p = points.sorted { $0.x != $1.x ? $0.x < $1.x : $0.y < $1.y }
        guard p.count > 2 else { return p }
        func cross(_ o: CGPoint, _ a: CGPoint, _ b: CGPoint) -> Double {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }
        var lower: [CGPoint] = [], upper: [CGPoint] = []
        for q in p {
            while lower.count >= 2, cross(lower[lower.count - 2], lower[lower.count - 1], q) <= 0 { lower.removeLast() }
            lower.append(q)
        }
        for q in p.reversed() {
            while upper.count >= 2, cross(upper[upper.count - 2], upper[upper.count - 1], q) <= 0 { upper.removeLast() }
            upper.append(q)
        }
        return Array(lower.dropLast() + upper.dropLast())
    }

    /// TL, TR, BR, BL: the long side read left to right, the upper corner first at each end.
    static func readingOrder(_ box: [CGPoint]) -> [CGPoint] {
        let c = CGPoint(x: box.map(\.x).reduce(0, +) / 4, y: box.map(\.y).reduce(0, +) / 4)
        let e0 = CGPoint(x: box[1].x - box[0].x, y: box[1].y - box[0].y)
        let e1 = CGPoint(x: box[2].x - box[1].x, y: box[2].y - box[1].y)
        var d = hypot(e0.x, e0.y) >= hypot(e1.x, e1.y) ? e0 : e1
        if d.x < 0 { d = CGPoint(x: -d.x, y: -d.y) }
        let order = box.indices.sorted { (box[$0].x - c.x) * d.x + (box[$0].y - c.y) * d.y
            < (box[$1].x - c.x) * d.x + (box[$1].y - c.y) * d.y }
        let left = order.prefix(2).sorted { box[$0].y < box[$1].y }
        let right = order.suffix(2).sorted { box[$0].y < box[$1].y }
        return [box[left[0]], box[right[0]], box[right[1]], box[left[1]]]
    }

    /// The image fitted into the 512 canvas at the top left on black, as the
    /// model's BGRA input buffer (`segtrain.letterbox`).
    static func letterbox(_ image: CGImage, scale: Double) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let attrs = [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true]
        CVPixelBufferCreate(nil, inputSize, inputSize, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &buffer)
        guard let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer), width: inputSize, height: inputSize, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        // Black canvas: zero every byte (alpha included, as the model reads RGB only).
        memset(CVPixelBufferGetBaseAddress(buffer), 0, CVPixelBufferGetBytesPerRow(buffer) * inputSize)
        context.interpolationQuality = .high
        let w = Double(image.width) * scale, h = Double(image.height) * scale
        // CGContext's origin is bottom-left: the top-left placement sits at y = size - h.
        context.draw(image, in: CGRect(x: 0, y: Double(inputSize) - h, width: w, height: h))
        return buffer
    }
}
