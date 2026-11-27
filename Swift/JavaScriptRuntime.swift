import Foundation
import JavaScriptCore

/// The single JavaScriptCore context used by Python-side challenge providers.
/// JavaScriptCore is intentionally confined to the main thread because the
/// Python callback may originate from yt-dlp's background download worker.
final class JavaScriptRuntime {
    static let shared = JavaScriptRuntime()

    private var context: JSContext?
    private var lastException: String?

    private init() {}

    /// Install the Python -> Swift callback before CPython initialization.
    static func installBridge() {
        PythonBridge.setJavaScriptEvaluator { script in
            JavaScriptRuntime.shared.evaluateOnMainThread(script)
        }
    }

    func evaluate(_ script: String) -> String? {
        if Thread.isMainThread {
            return evaluateOnMainThread(script)
        }
        return DispatchQueue.main.sync {
            evaluateOnMainThread(script)
        }
    }

    private func evaluateOnMainThread(_ script: String) -> String? {
        dispatchPrecondition(condition: .onQueue(.main))
        let js = context ?? makeContext()
        lastException = nil
        let value = js.evaluateScript(script)
        if let exception = lastException {
            NSLog("[SealPad:JavaScriptCore] %@", exception)
            return nil
        }
        guard let value, !value.isUndefined, !value.isNull else {
            return value?.isNull == true ? "null" : nil
        }
        // Preserve arrays/objects across the Python boundary instead of
        // collapsing them to JavaScript strings such as "[object Object]".
        return value.toJSON() ?? value.toString()
    }

    private func makeContext() -> JSContext {
        let js = JSContext()!
        js.name = "SealPadChallengeRuntime"
        js.exceptionHandler = { [weak self] _, exception in
            self?.lastException = exception?.toString() ?? "Unknown JavaScript exception"
        }
        context = js
        return js
    }
}
