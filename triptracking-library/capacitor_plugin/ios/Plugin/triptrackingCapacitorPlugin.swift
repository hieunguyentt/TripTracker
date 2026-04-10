import Capacitor
import triptracking

@objc(triptrackingCapacitorPlugin)
public class triptrackingCapacitorPlugin: CAPPlugin {

    @objc func doSomething(_ call: CAPPluginCall) {
        let input = call.getString("input") ?? ""
        let result = triptracking().doSomething(input: input)
        call.resolve(["value": result])
    }
}
