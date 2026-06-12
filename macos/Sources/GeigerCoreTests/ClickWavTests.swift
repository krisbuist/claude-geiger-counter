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

    // deterministic
    expect(makeClickWavData() == makeClickWavData(), "deterministic output")
}
