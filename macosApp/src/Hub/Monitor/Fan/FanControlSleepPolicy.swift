import Foundation

/// Stats saves the active custom mode before sleep and restores it after wake.
struct FanControlSleepPolicy {
    private(set) var activeConfiguration: MonitorFanConfiguration?
    private var savedConfiguration: MonitorFanConfiguration?

    mutating func start(_ configuration: MonitorFanConfiguration) {
        activeConfiguration = configuration
        savedConfiguration = nil
    }

    mutating func stop() {
        activeConfiguration = nil
        savedConfiguration = nil
    }

    mutating func willSleep() -> MonitorFanConfiguration? {
        guard let activeConfiguration, !activeConfiguration.mode.isAutomatic else {
            return nil
        }
        savedConfiguration = activeConfiguration
        return activeConfiguration
    }

    mutating func didWake() -> MonitorFanConfiguration? {
        guard activeConfiguration != nil, let savedConfiguration else { return nil }
        self.savedConfiguration = nil
        return savedConfiguration
    }
}
