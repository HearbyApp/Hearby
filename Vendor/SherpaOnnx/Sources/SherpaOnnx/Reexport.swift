// Re-export the sherpa-onnx C API so app code can `import SherpaOnnx` and
// see the C types/functions directly. The Swift convenience wrapper
// (SherpaOnnx.swift from the upstream package) lives in the app target
// instead of here, because its API is internal and would be invisible
// across the module boundary.
@_exported import sherpa_onnx
