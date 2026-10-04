import Foundation
import AppKit
import CoreGraphics

struct SegmentationRequest {
    let image: NSImage
    let point: CGPoint // normalized, top-left origin
    let tolerance: Double
}

struct SegmentationResult {
    let maskImage: NSImage
    let bounds: CGRect // normalized, top-left origin
}

protocol SegmentationProvider {
    var name: String { get }
    func segment(_ request: SegmentationRequest) async throws -> SegmentationResult
}

enum SegmentationError: LocalizedError {
    case unreadableImage, invalidPoint
    var errorDescription: String? {
        switch self { case .unreadableImage: return "The canvas image could not be read."; case .invalidPoint: return "The selected point is outside the image." }
    }
}

struct LocalRegionSegmentationProvider: SegmentationProvider {
    let name = "Local Smart Select"

    func segment(_ request: SegmentationRequest) async throws -> SegmentationResult {
        guard let cg = request.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw SegmentationError.unreadableImage }
        let w = cg.width, h = cg.height
        let sx = min(w - 1, max(0, Int(request.point.x * CGFloat(w))))
        let sy = min(h - 1, max(0, Int(request.point.y * CGFloat(h))))
        guard w > 0, h > 0 else { throw SegmentationError.invalidPoint }

        let bytesPerPixel = 4, bytesPerRow = w * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: h * bytesPerRow)
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw SegmentationError.unreadableImage }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        func rgb(_ x: Int, _ y: Int) -> (Double, Double, Double) {
            let i = y * bytesPerRow + x * 4
            return (Double(pixels[i]), Double(pixels[i+1]), Double(pixels[i+2]))
        }
        let seed = rgb(sx, sy)
        let threshold = max(10.0, min(120.0, request.tolerance * 120.0))
        let maxPixels = max(8_000, min(w * h / 2, 500_000))
        var seen = [Bool](repeating: false, count: w * h)
        var selected = [Bool](repeating: false, count: w * h)
        var queueX = [Int](), queueY = [Int](); queueX.reserveCapacity(maxPixels); queueY.reserveCapacity(maxPixels)
        queueX.append(sx); queueY.append(sy); seen[sy*w+sx] = true
        var head = 0, minX = sx, maxX = sx, minY = sy, maxY = sy
        while head < queueX.count && head < maxPixels {
            let x=queueX[head], y=queueY[head]; head += 1
            let c=rgb(x,y); let dr=c.0-seed.0, dg=c.1-seed.1, db=c.2-seed.2
            let distance = sqrt(dr*dr + dg*dg + db*db)
            if distance > threshold { continue }
            selected[y*w+x] = true; minX=min(minX,x); maxX=max(maxX,x); minY=min(minY,y); maxY=max(maxY,y)
            for (nx,ny) in [(x-1,y),(x+1,y),(x,y-1),(x,y+1)] where nx >= 0 && ny >= 0 && nx < w && ny < h {
                let idx=ny*w+nx; if !seen[idx] { seen[idx]=true; queueX.append(nx); queueY.append(ny) }
            }
        }

        var mask = [UInt8](repeating: 0, count: w*h*4)
        for y in 0..<h { for x in 0..<w where selected[y*w+x] { let i=(y*w+x)*4; mask[i]=255; mask[i+1]=255; mask[i+2]=255; mask[i+3]=255 } }
        guard let mctx = CGContext(data:&mask,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue), let out=mctx.makeImage() else { throw SegmentationError.unreadableImage }
        let bounds = CGRect(x:CGFloat(minX)/CGFloat(w), y:CGFloat(minY)/CGFloat(h), width:CGFloat(maxX-minX+1)/CGFloat(w), height:CGFloat(maxY-minY+1)/CGFloat(h))
        return SegmentationResult(maskImage:NSImage(cgImage:out,size:request.image.size),bounds:bounds)
    }
}
