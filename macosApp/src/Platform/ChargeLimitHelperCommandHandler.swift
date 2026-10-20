import Foundation
import kmpDomain

/// 把 helper 线上命令转成 MCL 后端动作。
///
/// 调用方签名由 socket 层先校验。这里只做命令解析、范围检查和结果编码。
final class ChargeLimitHelperCommandHandler: @unchecked Sendable {
    private let backend: ChargeLimitBackend

    init(backend: ChargeLimitBackend) {
        self.backend = backend
    }

    /// 不是充电命令时返回 nil，交给现有 helper 分支处理。
    func handle(_ request: HelperRequest) -> HelperReply? {
        switch request.command {
        case HelperWire.shared.COMMAND_CHARGE_LIMIT_STATUS:
            return statusReply(requestId: request.requestId)
        case HelperWire.shared.COMMAND_CHARGE_LIMIT_CONFIGURE:
            guard let percent = request.payload["percent"].flatMap(Int.init) else {
                return HelperWire.shared.failure(
                    requestId: request.requestId,
                    message: "Missing charge limit"
                )
            }
            return configureReply(requestId: request.requestId, percent: percent)
        case HelperWire.shared.COMMAND_CHARGE_LIMIT_RESTORE:
            return restoreReply(requestId: request.requestId)
        default:
            return nil
        }
    }

    private func statusReply(requestId: String) -> HelperReply {
        switch backend.loadState() {
        case .success(nil):
            return HelperWire.shared.success(
                requestId: requestId,
                result: ["enabled": "false"]
            )
        case .success(let state?):
            var result = [
                "enabled": "true",
                "targetPercent": String(state.targetPercent),
            ]
            if let originalState = state.original.featureState {
                result["originalFeatureState"] = String(originalState)
            }
            if let originalLimit = state.original.limitPercent {
                result["originalLimitPercent"] = String(originalLimit)
            }
            if let originalOptimizedCharging = state.original.optimizedChargingEnabled {
                result["originalOptimizedChargingEnabled"] = String(originalOptimizedCharging)
            }
            return HelperWire.shared.success(requestId: requestId, result: result)
        case .failure(let failure):
            return HelperWire.shared.failure(
                requestId: requestId,
                message: failure.description
            )
        }
    }

    private func configureReply(requestId: String, percent: Int) -> HelperReply {
        switch backend.apply(targetPercent: percent) {
        case .success(let state):
            return HelperWire.shared.success(
                requestId: requestId,
                result: ["targetPercent": String(state.targetPercent)]
            )
        case .failure(let failure):
            return HelperWire.shared.failure(
                requestId: requestId,
                message: failure.description
            )
        }
    }

    private func restoreReply(requestId: String) -> HelperReply {
        switch backend.restore() {
        case .success:
            return HelperWire.shared.success(requestId: requestId, result: [:])
        case .failure(let failure):
            return HelperWire.shared.failure(
                requestId: requestId,
                message: failure.description
            )
        }
    }
}
