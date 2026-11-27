"""Host-side contract tests for the Python half of the JavaScriptCore bridge.

The actual JSCore callback is supplied by the iOS Objective-C runtime; these
checks keep input validation and the JSON-facing bridge contract deterministic.
"""
import importlib.util
import json
import pathlib
import sys
import types
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("sealpad_bridge", ROOT / "app" / "bridge.py")
bridge = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = bridge
spec.loader.exec_module(bridge)


class NativeStub(types.ModuleType):
    def __init__(self):
        super().__init__("_sealpad_native")
        self.calls = []

    def evaluate_javascript(self, script):
        self.calls.append(script)
        if script == "1 + 1":
            return "2"
        return "stub-result"


class JavaScriptBridgeContractTests(unittest.TestCase):
    def setUp(self):
        self.native = NativeStub()
        sys.modules["_sealpad_native"] = self.native

    def test_javascript_test_uses_native_evaluator(self):
        result = json.loads(bridge.javascript_test('{"expression":"40 + 2"}'))
        self.assertEqual(result, {"result": "stub-result"})
        self.assertEqual(self.native.calls, ["40 + 2"])

    def test_javascript_test_rejects_non_string_expression(self):
        result = json.loads(bridge.javascript_test('{"expression":42}'))
        self.assertIn("error", result)

    def test_javascript_test_rejects_oversized_expression(self):
        result = json.loads(bridge.javascript_test(json.dumps({"expression": "x" * 100_001})))
        self.assertIn("error", result)


if __name__ == "__main__":
    unittest.main()
