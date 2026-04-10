package com.carmd.triptracking.capacitor

import com.carmd.triptracking.triptracking
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.CapacitorPlugin
import com.getcapacitor.JSObject

@CapacitorPlugin(name = "triptracking")
class triptrackingCapacitorPlugin : Plugin() {

    @PluginMethod
    fun doSomething(call: PluginCall) {
        val input = call.getString("input") ?: ""
        val result = triptracking().doSomething(input)
        val ret = JSObject()
        ret.put("value", result)
        call.resolve(ret)
    }
}
