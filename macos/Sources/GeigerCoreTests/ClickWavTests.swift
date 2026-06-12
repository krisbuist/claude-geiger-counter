import Foundation
import GeigerCore

func clickWavTests() {
    let data = makeClickWavData()
    let n = Int(22050 * 0.005) // 110 samples

    // header and size
    expectEqual(data.count, 44 + n, "wav total size")
    expectEqual(String(data: data.prefix(4), encoding: .ascii), "RIFF", "RIFF magic")
    expectEqual(String(data: data.subdata(in: 8..<16), encoding: .ascii), "WAVEfmt ", "WAVE + fmt chunks")
    expectEqual(String(data: data.subdata(in: 36..<40), encoding: .ascii), "data", "data chunk")

    // sample rate at offset 24, little-endian
    let rate = data.subdata(in: 24..<28).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
    expectEqual(UInt32(littleEndian: rate), 22050, "sample rate 22050")

    // fmt chunk fields, little-endian
    let fmtSize = data.subdata(in: 16..<20).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
    expectEqual(UInt32(littleEndian: fmtSize), 16, "fmt chunk size 16")
    let audioFormat = data.subdata(in: 20..<22).withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }
    expectEqual(UInt16(littleEndian: audioFormat), 1, "audio format PCM")
    let channels = data.subdata(in: 22..<24).withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }
    expectEqual(UInt16(littleEndian: channels), 1, "mono channel count")
    let blockAlign = data.subdata(in: 32..<34).withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }
    expectEqual(UInt16(littleEndian: blockAlign), 1, "block align 1")
    let bitsPerSample = data.subdata(in: 34..<36).withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }
    expectEqual(UInt16(littleEndian: bitsPerSample), 8, "bits per sample 8")

    // golden samples (independently derived via arbitrary-precision LCG)
    expectEqual(Int(data[44]), 165, "golden sample 0")
    expectEqual(Int(data[45]), 84, "golden sample 1")
    expectEqual(Int(data[46]), 166, "golden sample 2")

    // deterministic
    expect(makeClickWavData() == makeClickWavData(), "deterministic output")
}
