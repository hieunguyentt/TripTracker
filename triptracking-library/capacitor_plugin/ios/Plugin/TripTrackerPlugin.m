//
//  TripTrackerPlugin.m
//  Capacitor bridge for TripTrackerPlugin
//

#import <Foundation/Foundation.h>
#import <Capacitor/Capacitor.h>

CAP_PLUGIN(TripTrackerPlugin, "TripTracker",
    CAP_PLUGIN_METHOD(initializeWithConfig, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(updateVehicleId, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(hasLocationPermission, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(startTracking, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(stopTracking, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(openSettings, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(openNotificationSettings, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(openGeofenceManager, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(openMainView, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(openHistory, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(openDailyLocations, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(getTrackingStatus, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(getCurrentLocation, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(getTripHistory, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(getSettings, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(updateSetting, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(getGeofenceZones, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(addGeofenceZone, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(removeGeofenceZone, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(startWebMonitor, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(stopWebMonitor, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(sendTodayLog, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(sendAllLogs, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(sendRecentLogs, CAPPluginReturnPromise);
)