import Foundation

/// 5 ms noise-burst click, 22 kHz 8-bit mono WAV, deterministic LCG noise.
/// Note: sample bytes intentionally differ from the JS CLI's WAV — the JS LCG
/// loses float64 precision above 2^53 and produces different (equally random-
/// sounding) noise. Same envelope, rate, and format; exact math here.
public func makeClickWavData() -> Data {
    let sampleRate: UInt32 = 22050
    let n = Int(Double(sampleRate) * 0.005)
    var samples = [UInt8](repeating: 0, count: n)
    var seed: Int64 = 12345
    for i in 0..<n {
        seed = (seed * 1_103_515_245 + 12345) & 0x7fff_ffff
        let noise = Double(seed) / Double(0x7fff_ffff) * 2 - 1
        let decay = exp(-6.0 * Double(i) / Double(n))
        samples[i] = UInt8(clamping: Int((128 + noise * 120 * decay).rounded()))
    }

    var data = Data(capacity: 44 + n)
    func ascii(_ s: String) { data.append(contentsOf: Array(s.utf8)) }
    func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
    func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }

    ascii("RIFF"); u32(UInt32(36 + n)); ascii("WAVE"); ascii("fmt ")
    u32(16)            // fmt chunk size
    u16(1)             // PCM
    u16(1)             // mono
    u32(sampleRate)    // sample rate
    u32(sampleRate)    // byte rate (8-bit mono)
    u16(1)             // block align
    u16(8)             // bits per sample
    ascii("data"); u32(UInt32(n))
    data.append(contentsOf: samples)
    return data
}
