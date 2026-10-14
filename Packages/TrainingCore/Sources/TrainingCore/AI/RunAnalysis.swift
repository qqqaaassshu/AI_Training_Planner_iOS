import Foundation

public struct AnalysisFormatError: Error, LocalizedError, Equatable {
    public var errors: [String]
    public var errorDescription: String? { "AI 返回的格式不符合要求" }
}

extension AIClient {
    /// 通过 API 运行一次分析，返回经过校验的分析记录（手动分析和每周自动复盘共用）
    public func runAnalysis(input: AnalysisInput, planVersionId: String, service: AIServiceConfig, apiKey: String) async throws -> AIAnalysis {
        let prompt = buildPrompt(input)
        let text = try await call(service, apiKey: apiKey, AICallParams(system: prompt.system, user: prompt.user))
        switch parseAnalysisReply(text) {
        case .failure(let errors): throw AnalysisFormatError(errors: errors)
        case .ok(let output):
            return createAnalysis(output, kind: input.kind, channel: .api, planVersionId: planVersionId, range: input.range,
                                  provider: service.name, model: service.model, userNote: input.userNote)
        }
    }
}
