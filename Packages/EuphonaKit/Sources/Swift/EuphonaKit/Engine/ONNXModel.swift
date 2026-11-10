import CEuphonaApple
import Foundation
import Synchronization

/// A float tensor: row-major values and their shape.
struct Tensor: Sendable {
    var values: [Float]
    var shape: [Int]

    init(_ values: [Float], shape: [Int]) {
        precondition(values.count == shape.reduce(1, *), "tensor shape does not match its values")
        self.values = values
        self.shape = shape
    }
}

struct EngineError: Error, CustomStringConvertible {
    var description: String
}

/// One bundled ONNX model. Runs are serialized; ONNX Runtime sessions are not run concurrently here.
final class ONNXModel: Sendable {
    private let pointer: Mutex<OpaquePointer>

    init(named name: String, threads: Int) throws {
        guard let url = Bundle.module.url(forResource: name, withExtension: "onnx") else {
            throw EngineError(description: "missing model \(name)")
        }
        var message = [CChar](repeating: 0, count: 512)
        guard let created = pa_model_create(url.path(percentEncoded: false), Int32(threads), &message, message.count) else {
            throw EngineError(description: "\(name): \(String(cString: message))")
        }
        pointer = Mutex(created)
    }

    deinit {
        pointer.withLock { pa_model_destroy($0) }
    }

    enum Input {
        case floats(Tensor)
        case int64(value: Int64)
    }

    func run(_ inputs: [(String, Input)], outputs: [String]) throws -> [Tensor] {
        try pointer.withLock { model in
            var message = [CChar](repeating: 0, count: 512)
            var results = [pa_tensor_out](repeating: pa_tensor_out(), count: outputs.count)
            // Keep every buffer alive and pinned for the call.
            let names = inputs.map { strdup($0.0)! } + outputs.map { strdup($0)! }
            defer { names.forEach { free($0) } }
            var shapes: [[Int64]] = []
            var scalars: [Int64] = []
            for (_, input) in inputs {
                switch input {
                case .floats(let tensor): shapes.append(tensor.shape.map(Int64.init))
                case .int64(let value): shapes.append([]); scalars.append(value)
                }
            }
            let status: Int32 = try withPinned(inputs.map(\.1), shapes, scalars) { native in
                for i in native.indices { native[i].name = UnsafePointer(names[i]) }
                let outputNames = names[inputs.count...].map { UnsafePointer($0) as UnsafePointer<CChar>? }
                return outputNames.withUnsafeBufferPointer { outputNamesPointer in
                    pa_model_run(model, native, native.count, outputNamesPointer.baseAddress,
                                 &results, results.count, &message, message.count)
                }
            }
            guard status == 0 else { throw EngineError(description: String(cString: message)) }
            return results.map { out in
                var out = out
                defer { pa_tensor_free(&out) }
                let shape = withUnsafeBytes(of: out.shape) { Array($0.bindMemory(to: Int64.self).prefix(out.rank)) }
                return Tensor(Array(UnsafeBufferPointer(start: out.values, count: out.count)), shape: shape.map(Int.init))
            }
        }
    }

    /// Pins the input buffers and builds the native descriptors pointing into them.
    private func withPinned<R>(_ inputs: [Input], _ shapes: [[Int64]], _ scalars: [Int64],
                               _ body: (inout [pa_tensor_in]) throws -> R) throws -> R {
        var native = [pa_tensor_in](repeating: pa_tensor_in(), count: inputs.count)
        var scalarIndex = 0
        func pin(_ index: Int) throws -> R {
            if index == inputs.count { return try body(&native) }
            return try shapes[index].withUnsafeBufferPointer { shape in
                native[index].shape = shape.baseAddress
                native[index].rank = shape.count
                switch inputs[index] {
                case .floats(let tensor):
                    return try tensor.values.withUnsafeBufferPointer { values in
                        native[index].floats = values.baseAddress
                        return try pin(index + 1)
                    }
                case .int64:
                    let value = scalars[scalarIndex]
                    scalarIndex += 1
                    return try withUnsafePointer(to: value) { pointer in
                        native[index].int64s = pointer
                        return try pin(index + 1)
                    }
                }
            }
        }
        return try pin(0)
    }
}
