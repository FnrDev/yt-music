import Foundation
import Observation

/// Single source of truth for playback state across the app: the window,
/// Now Playing, the menu bar, the Dock menu and notifications all read from here.
@MainActor
@Observable
final class PlayerModel {
    private(set) var state = PlayerState()
    /// When `state` was last received, used to extrapolate position.
    private(set) var stateReceivedAt = Date()

    /// Executes a command in the page. Set by `WebBridge`.
    @ObservationIgnored var commandSink: ((PlayerCommand) -> Void)?

    @ObservationIgnored private var observers: [(_ old: PlayerState, _ new: PlayerState) -> Void] = []

    func observe(_ observer: @escaping (_ old: PlayerState, _ new: PlayerState) -> Void) {
        observers.append(observer)
    }

    func update(_ newState: PlayerState) {
        let old = state
        state = newState
        stateReceivedAt = Date()
        for observer in observers { observer(old, newState) }
    }

    func reset() {
        update(PlayerState())
    }

    func send(_ command: PlayerCommand) {
        commandSink?(command)
    }

    /// Current position, extrapolated from the last report while playing.
    func position(at date: Date = Date()) -> Double {
        guard state.isPlaying else { return state.position }
        let elapsed = state.position + date.timeIntervalSince(stateReceivedAt)
        return state.duration > 0 ? min(elapsed, state.duration) : elapsed
    }

    func adjustVolume(by delta: Int) {
        send(.setVolume(max(0, min(100, state.volume + delta))))
    }
}
