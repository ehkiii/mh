#import "PythonBridge.h"
#import <Python/Python.h>

// Derived from the Python.h you build against, so it can never drift.
#define PY_VER_STRING [NSString stringWithFormat:@"%d.%d", PY_MAJOR_VERSION, PY_MINOR_VERSION]

static NSError *MakeError(NSString *message) {
    return [NSError errorWithDomain:@"PythonBridge" code:1
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

@implementation PythonBridge

+ (BOOL)startWithResourcePath:(NSString *)resourcePath error:(NSError **)error {
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
