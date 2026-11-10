import Accelerate

/// Real FFT with NumPy's scaling: `forward` matches `np.fft.rfft`, `inverse` matches `np.fft.irfft`.
final class RealFFT: @unchecked Sendable {
    let size: Int
    private let log2n: vDSP_Length
    private let setup: FFTSetup

    init(size: Int) {
        precondition(size > 1 && size & (size - 1) == 0, "FFT size must be a power of two")
        self.size = size
        log2n = vDSP_Length(size.trailingZeroBitCount)
        setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    /// Real and imaginary parts of bins 0...size/2 of `x` zero-padded to the FFT size.
    func forward(_ x: ArraySlice<Float>) -> (re: [Float], im: [Float]) {
        var input = [Float](repeating: 0, count: size)
        for (i, v) in x.prefix(size).enumerated() { input[i] = v }
        var re = [Float](repeating: 0, count: size / 2), im = [Float](repeating: 0, count: size / 2)
        re.withUnsafeMutableBufferPointer { rp in
            im.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                input.withUnsafeBytes { raw in
                    vDSP_ctoz(raw.bindMemory(to: DSPComplex.self).baseAddress!, 2, &split, 1, vDSP_Length(size / 2))
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
            }
        }
        // vDSP returns twice the DFT and packs the Nyquist bin into im[0].
        var outRe = [Float](repeating: 0, count: size / 2 + 1), outIm = outRe
        outRe[0] = re[0] / 2
        outRe[size / 2] = im[0] / 2
        for k in 1..<size / 2 {
            outRe[k] = re[k] / 2
            outIm[k] = im[k] / 2
        }
        return (outRe, outIm)
    }

    /// `np.fft.irfft` of a spectrum with zero imaginary part (bins 0...size/2).
    func inverse(real spectrum: [Float]) -> [Float] {
        precondition(spectrum.count == size / 2 + 1)
        var re = [Float](repeating: 0, count: size / 2), im = [Float](repeating: 0, count: size / 2)
        re[0] = spectrum[0]
        im[0] = spectrum[size / 2]
        for k in 1..<size / 2 { re[k] = spectrum[k] }
        var output = [Float](repeating: 0, count: size)
        re.withUnsafeMutableBufferPointer { rp in
            im.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_INVERSE))
                output.withUnsafeMutableBytes { raw in
                    vDSP_ztoc(&split, 1, raw.bindMemory(to: DSPComplex.self).baseAddress!, 2, vDSP_Length(size / 2))
                }
            }
        }
        // vDSP's inverse of a true spectrum gives size times the inverse DFT.
        return vDSP.divide(output, Float(size))
    }
}
