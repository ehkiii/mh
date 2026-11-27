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
        // Serialize arrays/objects as JSON before crossing into Python.
        // JSValue has no toJSON() method; invoke JavaScript's JSON.stringify.
        if let stringify = js.evaluateScript("JSON.stringify"),
           let json = stringify.call(withArguments: [value]),
           !json.isUndefined, !json.isNull,
           let serialized = json.toString() {
            return serialized
        }
        return value.toString()
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
