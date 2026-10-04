import Foundation
import AppKit

struct GeneratedImage { let image: NSImage; let provider: AIProvider; let model: String }

enum AIServiceError: LocalizedError {
    case missingKey, invalidResponse, unsupported(String), remote(String), encoding, network(String)
    var errorDescription: String? { switch self {
    case .missingKey: return "No API key is configured for this provider."
    case .invalidResponse: return "The image provider returned an invalid response."
    case .unsupported(let v): return "\(v) is prepared in the UI but its image adapter is not enabled yet."
    case .remote(let m): return m
    case .encoding: return "The canvas or mask could not be encoded for editing."
    case .network(let message): return "Network error: \(message)"
    } }
}

enum AIImageService {
    static func generate(prompt: String, provider: AIProvider) async throws -> GeneratedImage {
        guard let key=KeychainStore.load(provider:provider) else { throw AIServiceError.missingKey }
        switch provider { case .openAI: return try await generateOpenAI(prompt:prompt,key:key); case .fal: throw AIServiceError.unsupported("fal.ai"); case .gemini: throw AIServiceError.unsupported("Gemini") }
    }

    static func edit(prompt:String, image:NSImage, mask:NSImage, provider:AIProvider) async throws -> GeneratedImage {
        guard let key=KeychainStore.load(provider:provider) else { throw AIServiceError.missingKey }
        guard provider == .openAI else { throw AIServiceError.unsupported(provider.rawValue + " masked editing") }
        guard let imageData=pngData(image), let maskData=openAIEditMaskData(mask) else { throw AIServiceError.encoding }
        let boundary="LayerAI-\(UUID().uuidString)"
        var body=Data()
        func field(_ name:String,_ value:String){ body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using:.utf8)!) }
        func file(_ name:String,_ filename:String,_ data:Data){ body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\nContent-Type: image/png\r\n\r\n".data(using:.utf8)!); body.append(data); body.append("\r\n".data(using:.utf8)!) }
        field("model","gpt-image-1"); field("prompt",prompt); field("size","1536x1024"); file("image","canvas.png",imageData); file("mask","mask.png",maskData); body.append("--\(boundary)--\r\n".data(using:.utf8)!)
        var req=URLRequest(url:URL(string:"https://api.openai.com/v1/images/edits")!); req.httpMethod="POST"; req.setValue("Bearer \(key)",forHTTPHeaderField:"Authorization"); req.setValue("multipart/form-data; boundary=\(boundary)",forHTTPHeaderField:"Content-Type"); req.httpBody=body
        do {
            return try await decode(await URLSession.shared.data(for:req), provider:.openAI, model:"gpt-image-1")
        } catch let error as AIServiceError { throw error }
        catch { throw AIServiceError.network(error.localizedDescription) }
    }

    private static func generateOpenAI(prompt:String,key:String) async throws -> GeneratedImage {
        var req=URLRequest(url:URL(string:"https://api.openai.com/v1/images/generations")!); req.httpMethod="POST"; req.setValue("Bearer \(key)",forHTTPHeaderField:"Authorization"); req.setValue("application/json",forHTTPHeaderField:"Content-Type")
        req.httpBody=try JSONSerialization.data(withJSONObject:["model":"gpt-image-1","prompt":prompt,"size":"1536x1024","quality":"medium","output_format":"png"])
        do {
            return try await decode(await URLSession.shared.data(for:req), provider:.openAI, model:"gpt-image-1")
        } catch let error as AIServiceError { throw error }
        catch { throw AIServiceError.network(error.localizedDescription) }
    }
    private static func decode(_ result:(Data,URLResponse),provider:AIProvider,model:String) async throws -> GeneratedImage {
        let (data,response)=result; guard let http=response as? HTTPURLResponse else { throw AIServiceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { let obj=try? JSONSerialization.jsonObject(with:data) as? [String:Any]; let e=obj?["error"] as? [String:Any]; throw AIServiceError.remote(e?["message"] as? String ?? "Provider error (HTTP \(http.statusCode)).") }
        let obj=try JSONSerialization.jsonObject(with:data) as? [String:Any]; guard let items=obj?["data"] as? [[String:Any]],let b64=items.first?["b64_json"] as? String,let d=Data(base64Encoded:b64),let image=NSImage(data:d) else { throw AIServiceError.invalidResponse }; return GeneratedImage(image:image,provider:provider,model:model)
    }
    private static func pngData(_ image:NSImage)->Data? { guard let cg=image.cgImage(forProposedRect:nil,context:nil,hints:nil) else{return nil}; let rep=NSBitmapImageRep(cgImage:cg); return rep.representation(using:.png,properties:[:]) }
    // OpenAI edits the transparent part of a mask. Smart Select stores selected pixels as opaque white, so invert alpha.
    private static func openAIEditMaskData(_ mask:NSImage)->Data? { guard let cg=mask.cgImage(forProposedRect:nil,context:nil,hints:nil) else{return nil}; let w=cg.width,h=cg.height; var p=[UInt8](repeating:0,count:w*h*4); guard let c=CGContext(data:&p,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else{return nil}; c.draw(cg,in:CGRect(x:0,y:0,width:w,height:h)); for i in stride(from:0,to:p.count,by:4){ let selected=p[i] > 127 || p[i+3] > 127; p[i]=255;p[i+1]=255;p[i+2]=255;p[i+3]=selected ? 0:255 }; guard let out=c.makeImage() else{return nil}; return NSBitmapImageRep(cgImage:out).representation(using:.png,properties:[:]) }
}
