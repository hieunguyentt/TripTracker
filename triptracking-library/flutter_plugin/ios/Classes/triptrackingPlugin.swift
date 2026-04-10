import Flutter
import triptracking

public class triptrackingPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.carmd.triptracking/flutter",
            binaryMessenger: registrar.messenger()
        )
        let instance = triptrackingPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "doSomething":
            let args = call.arguments as! [String: Any]
            let input = args["input"] as? String ?? ""
            result(triptracking().doSomething(input: input))
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
