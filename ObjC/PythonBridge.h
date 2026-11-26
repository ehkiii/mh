#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Minimal CPython embedding layer. Swift talks to Python only through
/// `callModule:function:argument:` (JSON string in, JSON string out).
@interface PythonBridge : NSObject

/// Boots the interpreter. `resourcePath` is Bundle.main.resourcePath.
+ (BOOL)startWithResourcePath:(NSString *)resourcePath error:(NSError **)error;

/// Calls module.function(argument) and returns the str result (nil on failure).
/// Safe to call from any thread; blocks until the Python function returns.
+ (nullable NSString *)callModule:(NSString *)module
                         function:(NSString *)function
                         argument:(NSString *)argument;

@end

NS_ASSUME_NONNULL_END
