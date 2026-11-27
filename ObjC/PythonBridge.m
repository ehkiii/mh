#import "PythonBridge.h"
#import <Python/Python.h>
#import <dispatch/dispatch.h>

// Derived from the Python.h you build against, so it can never drift.
#define PY_VER_STRING [NSString stringWithFormat:@"%d.%d", PY_MAJOR_VERSION, PY_MINOR_VERSION]

static NSError *MakeError(NSString *message) {
    return [NSError errorWithDomain:@"PythonBridge" code:1
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static SealPadJSEvaluator gJavaScriptEvaluator = nil;

/// Python -> Swift -> JavaScriptCore callback. Python invokes this from its
/// worker thread; JavaScriptCore itself is confined to the main thread.
static PyObject *SealPadEvaluateJavaScript(PyObject *self, PyObject *args) {
    const char *utf8Script = NULL;
    if (!PyArg_ParseTuple(args, "s", &utf8Script)) return NULL;

    NSString *script = [NSString stringWithUTF8String:utf8Script];
    if (!script || !gJavaScriptEvaluator) {
        PyErr_SetString(PyExc_RuntimeError, "SealPad JavaScriptCore bridge is not installed");
        return NULL;
    }

    __block NSString *result = nil;
    void (^evaluate)(void) = ^{
        result = gJavaScriptEvaluator(script);
    };

    if ([NSThread isMainThread]) {
        evaluate();
    } else {
        Py_BEGIN_ALLOW_THREADS
        dispatch_sync(dispatch_get_main_queue(), evaluate);
        Py_END_ALLOW_THREADS
    }

    if (!result) {
        PyErr_SetString(PyExc_RuntimeError, "JavaScriptCore evaluation failed");
        return NULL;
    }
    return PyUnicode_FromString(result.UTF8String ?: "");
}

static PyMethodDef SealPadNativeMethods[] = {
    {"evaluate_javascript", SealPadEvaluateJavaScript, METH_VARARGS,
     "Evaluate JavaScript through SealPad's native JavaScriptCore bridge."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef SealPadNativeModule = {
    PyModuleDef_HEAD_INIT, "_sealpad_native", NULL, -1, SealPadNativeMethods,
    NULL, NULL, NULL, NULL
};

static PyObject *PyInit__sealpad_native(void) {
    return PyModule_Create(&SealPadNativeModule);
}

@implementation PythonBridge

+ (void)setJavaScriptEvaluator:(SealPadJSEvaluator)evaluator {
    gJavaScriptEvaluator = [evaluator copy];
}

+ (BOOL)startWithResourcePath:(NSString *)resourcePath error:(NSError **)error {
    // Register our built-in module before CPython starts. This is the only
    // native callback surface exposed to Python; it is not an arbitrary bridge.
    if (PyImport_AppendInittab("_sealpad_native", &PyInit__sealpad_native) == -1) {
        if (error) *error = MakeError(@"Could not register SealPad native module");
        return NO;
    }

    PyStatus status;

    PyPreConfig preconfig;
    PyPreConfig_InitIsolatedConfig(&preconfig);
    preconfig.utf8_mode = 1;
    preconfig.configure_locale = 1;
    status = Py_PreInitialize(&preconfig);
    if (PyStatus_Exception(status)) {
        if (error) *error = MakeError([NSString stringWithFormat:@"Py_PreInitialize: %s", status.err_msg]);
        return NO;
    }

    PyConfig config;
    PyConfig_InitIsolatedConfig(&config);
    config.buffered_stdio = 0;
    config.write_bytecode = 1;          // speeds up launches after an yt-dlp update
    config.module_search_paths_set = 1;

    NSString *home = [resourcePath stringByAppendingPathComponent:@"python"];
    status = PyConfig_SetBytesString(&config, &config.home, home.UTF8String);
    if (PyStatus_Exception(status)) {
        if (error) *error = MakeError(@"Could not set PYTHONHOME");
        PyConfig_Clear(&config);
        return NO;
    }

    NSArray<NSString *> *paths = @[
        [NSString stringWithFormat:@"%@/lib/python%@", home, PY_VER_STRING],
        [NSString stringWithFormat:@"%@/lib/python%@/lib-dynload", home, PY_VER_STRING],
        [resourcePath stringByAppendingPathComponent:@"app"],            // bridge.py
        [resourcePath stringByAppendingPathComponent:@"app_packages"],   // yt_dlp, certifi, ...
    ];
    for (NSString *p in paths) {
        wchar_t *wide = Py_DecodeLocale(p.UTF8String, NULL);
        status = PyWideStringList_Append(&config.module_search_paths, wide);
        PyMem_RawFree(wide);
        if (PyStatus_Exception(status)) {
            if (error) *error = MakeError(@"Could not build sys.path");
            PyConfig_Clear(&config);
            return NO;
        }
    }

    status = Py_InitializeFromConfig(&config);
    PyConfig_Clear(&config);
    if (PyStatus_Exception(status)) {
        if (error) *error = MakeError([NSString stringWithFormat:@"Py_InitializeFromConfig: %s", status.err_msg]);
        return NO;
    }

    // Release the GIL held by this thread so any thread can PyGILState_Ensure().
    PyEval_SaveThread();
    return YES;
}

+ (NSString *)callModule:(NSString *)module function:(NSString *)function argument:(NSString *)argument {
    NSString *result = nil;
    PyGILState_STATE gil = PyGILState_Ensure();

    PyObject *mod = PyImport_ImportModule(module.UTF8String);
    if (mod) {
        PyObject *fn = PyObject_GetAttrString(mod, function.UTF8String);
        if (fn && PyCallable_Check(fn)) {
            PyObject *ret = PyObject_CallFunction(fn, "s", argument.UTF8String);
            if (ret) {
                const char *utf8 = PyUnicode_AsUTF8(ret);
                if (utf8) result = [NSString stringWithUTF8String:utf8];
                Py_DECREF(ret);
            }
        }
        Py_XDECREF(fn);
        Py_DECREF(mod);
    }
    if (PyErr_Occurred()) {
        PyErr_Print();
        PyErr_Clear();
    }

    PyGILState_Release(gil);
    return result;
}

@end
