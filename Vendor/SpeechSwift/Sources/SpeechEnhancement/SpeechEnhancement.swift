import Foundation
import AudioCommon

/// Speech enhancement (noise suppression) using DeepFilterNet3 on MLX.
///
/// CloneVoice patch: trimmed from upstream `SpeechEnhancement.swift` to the MLX
/// backend only (no Core ML), with loading from a caller-provided directory so
/// the app's own resumable downloader fetches the weights. Expects
/// `model.safetensors` + `auxiliary.npz` from `aufklarer/DeepFilterNet3-MLX`.
public final class SpeechEnhancer {
    public static let defaultMLXModelId = "aufklarer/DeepFilterNet3-MLX"
    /// Native sample rate (48kHz)
    public static let sampleRate = 48000

    let config: DeepFilterNet3Config
    let mlxNetwork: MLXDeepFilterNet3Network
    let stft: STFTProcessor
    let erbFb: [Float]
    let erbInvFb: [Float]

    var meanNormState: [Float]
    var unitNormState: [Float]
    let meanNormStateInit: [Float]
    let unitNormStateInit: [Float]
    var analysisMem: [Float]
    var synthesisMem: [Float]

    init(
        mlxNetwork: MLXDeepFilterNet3Network,
        config: DeepFilterNet3Config,
        auxData: DeepFilterNet3WeightLoader.AuxiliaryData
    ) {
        self.mlxNetwork = mlxNetwork
        self.config = config
        self.stft = STFTProcessor(fftSize: config.fftSize, hopSize: config.hopSize, window: auxData.window)
        self.erbFb = auxData.erbFb
        self.erbInvFb = auxData.erbInvFb
        self.meanNormState = auxData.meanNormState
        self.unitNormState = auxData.unitNormState
        self.meanNormStateInit = auxData.meanNormState
        self.unitNormStateInit = auxData.unitNormState
        self.analysisMem = [Float](repeating: 0, count: config.fftSize - config.hopSize)
        self.synthesisMem = [Float](repeating: 0, count: config.fftSize - config.hopSize)
    }

    /// Loads the network from a directory containing `model.safetensors` and `auxiliary.npz`.
    public static func load(from directory: URL) throws -> SpeechEnhancer {
        let config = DeepFilterNet3Config.default
        let (network, auxData) = try DeepFilterNet3WeightLoader.loadMLX(from: directory, config: config)
        return SpeechEnhancer(mlxNetwork: network, config: config, auxData: auxData)
    }

    /// Enhance audio by removing noise. Returns enhanced audio at 48 kHz.
    public func enhance(audio: [Float], sampleRate: Int) throws -> [Float] {
        var samples = audio
        if sampleRate != Self.sampleRate {
            samples = AudioFileLoader.resample(audio, from: sampleRate, to: Self.sampleRate)
        }
        resetState()
        return enhanceCore(audio48k: samples)
    }

    public func resetState() {
        analysisMem = [Float](repeating: 0, count: config.fftSize - config.hopSize)
        synthesisMem = [Float](repeating: 0, count: config.fftSize - config.hopSize)
        meanNormState = meanNormStateInit
        unitNormState = unitNormStateInit
    }

    private func enhanceCore(audio48k samples: [Float]) -> [Float] {
        let hop = config.hopSize
        let freqBins = config.freqBins

        // libdf appends a full FFT window so the STFT/iSTFT delay can be removed
        // without truncating non-hop-aligned input lengths.
        let paddedSamples = samples + [Float](repeating: 0, count: config.fftSize)
        let (specReal, specImag) = stft.forward(audio: paddedSamples, analysisMem: &analysisMem)
        let numFrames = specReal.count / freqBins
        guard numFrames > 0 else { return [] }

        var erbFeats = computeERBFeatures(
            real: specReal, imag: specImag, erbFb: erbFb,
            freqBins: freqBins, erbBands: config.erbBands, numFrames: numFrames)
        applyMeanNormalization(
            &erbFeats, state: &meanNormState, alpha: config.normAlpha,
            erbBands: config.erbBands, numFrames: numFrames)

        var specFeatReal = [Float](repeating: 0, count: numFrames * config.dfBins)
        var specFeatImag = [Float](repeating: 0, count: numFrames * config.dfBins)
        for t in 0..<numFrames {
            for f in 0..<config.dfBins {
                specFeatReal[t * config.dfBins + f] = specReal[t * freqBins + f]
                specFeatImag[t * config.dfBins + f] = specImag[t * freqBins + f]
            }
        }
        applyUnitNormalization(
            real: &specFeatReal, imag: &specFeatImag, state: &unitNormState,
            alpha: config.normAlpha, dfBins: config.dfBins, numFrames: numFrames)

        let dfOrder = config.dfOrder
        let coefsCount = dfOrder * numFrames * config.dfBins * 2
        let (erbMaskFlat, coefsRaw) = mlxNetwork.predict(
            erbFeats: erbFeats, specReal: specFeatReal, specImag: specFeatImag, numFrames: numFrames)

        // [O, T, F, 2] → [T, F, O, 2]
        var coefsFlat = [Float](repeating: 0, count: coefsCount)
        for t in 0..<numFrames {
            for f in 0..<config.dfBins {
                for o in 0..<dfOrder {
                    let srcIdx = ((o * numFrames + t) * config.dfBins + f) * 2
                    let dstIdx = ((t * config.dfBins + f) * dfOrder + o) * 2
                    coefsFlat[dstIdx] = coefsRaw[srcIdx]
                    coefsFlat[dstIdx + 1] = coefsRaw[srcIdx + 1]
                }
            }
        }

        var enhancedReal = specReal
        var enhancedImag = specImag
        applyERBMask(
            specReal: &enhancedReal, specImag: &enhancedImag, erbMask: erbMaskFlat,
            erbInvFb: erbInvFb, erbBands: config.erbBands, freqBins: freqBins, numFrames: numFrames)

        let (dfReal, dfImag) = applyDeepFiltering(
            specReal: specReal, specImag: specImag, coefs: coefsFlat,
            dfBins: config.dfBins, dfOrder: config.dfOrder, dfLookahead: config.dfLookahead,
            numFrames: numFrames, freqBins: freqBins)
        for t in 0..<numFrames {
            for f in 0..<config.dfBins {
                enhancedReal[t * freqBins + f] = dfReal[t * config.dfBins + f]
                enhancedImag[t * freqBins + f] = dfImag[t * config.dfBins + f]
            }
        }

        let rawOutput = stft.inverse(real: enhancedReal, imag: enhancedImag, synthesisMem: &synthesisMem)
        let trimStart = config.fftSize - hop
        let trimEnd = min(trimStart + samples.count, rawOutput.count)
        guard trimEnd > trimStart else { return [] }
        return Array(rawOutput[trimStart..<trimEnd])
    }
}
