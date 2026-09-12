import Foundation

/// The deliberately small surface exposed by the privileged sleep helper.
///
/// State is returned as a raw value because the helper must be able to report
/// `unknown` without allowing the client to mistake a failed read for a safe
/// disabled state.
@objc protocol KiplessSleepHelperProtocol {
    func getState(withReply reply: @escaping (Int, String?) -> Void)
    func acquireSleepOverride(withReply reply: @escaping (Bool, String?) -> Void)
    func releaseSleepOverride(withReply reply: @escaping (Bool, String?) -> Void)
}
