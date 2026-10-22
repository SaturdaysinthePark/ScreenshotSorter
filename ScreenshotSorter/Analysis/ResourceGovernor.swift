import Foundation

struct AnalysisBudget: Sendable, Equatable {
    var fastConcurrency: Int
    var deepConcurrency: Int
    var useLanguageModel: Bool
    /// Fast passes in flight while iCloud downloads are allowed: they mostly wait on the network
    /// (~1–1.5 s per original on device), so more of them keep the pipeline busy.
    var fastDownloadConcurrency: Int = 0

    func fastLimit(downloading: Bool) -> Int {
        downloading ? max(fastConcurrency, fastDownloadConcurrency) : fastConcurrency
    }

    var isPaused: Bool { fastConcurrency == 0 && deepConcurrency == 0 }
    static let paused = AnalysisBudget(fastConcurrency: 0, deepConcurrency: 0, useLanguageModel: false)
}

/// Picks how much work to run in parallel from thermal state, power mode and app state.
enum ResourceGovernor {
    static func budget(inBackground: Bool) -> AnalysisBudget {
        let info = ProcessInfo.processInfo
        switch info.thermalState {
        case .critical:
            return .paused
        case .serious:
            return AnalysisBudget(fastConcurrency: 1, deepConcurrency: 1, useLanguageModel: false)
        default:
            break
        }
        if info.isLowPowerModeEnabled {
            // Keep categorizing new screenshots, defer the expensive deep pass until charging
            return AnalysisBudget(fastConcurrency: 2, deepConcurrency: 0, useLanguageModel: false)
        }
        if inBackground {
            return AnalysisBudget(fastConcurrency: 2, deepConcurrency: 1, useLanguageModel: true, fastDownloadConcurrency: 3)
        }
        let cores = max(2, info.activeProcessorCount)
        let fast = min(4, max(2, cores / 2))
        return AnalysisBudget(fastConcurrency: fast, deepConcurrency: 2, useLanguageModel: true, fastDownloadConcurrency: 8)
    }
}
