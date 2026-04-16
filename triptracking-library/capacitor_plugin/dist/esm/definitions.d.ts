/**
 * TripTracker Capacitor Plugin
 *
 * Bridges TripTracker iOS native code to Ionic/JavaScript.
 * Provides: tracking status, settings pages, geofencing, notifications, logs.
 */
export interface TripTrackerPlugin {
    /**
     * Initialize TripTracker SDK with custom config.
     * Call once at app startup before using any other methods.
     * Only the values you pass are changed — everything else stays at defaults.
     *
     * Defaults:
     *   saveIntervalMinutes: 15, saveDistanceMeters: 30, vehicleThreshold: 6.0 (m/s),
     *   transportType: 0 (Car), autoStopTimeoutMinutes: 5, routeGapMeters: 500,
     *   geofenceEnabled: false, webMonitorEnabled: false, voiceFeedbackEnabled: true,
     *   notifyTripStart: true, notifyTripEnd: true, notifyDistanceKm: true,
     *   notifyGeofenceEnter: true, notifyGeofenceExit: true
     */
    initializeWithConfig(options?: TripTrackerConfigOptions): Promise<{
        initialized: boolean;
    }>;
    /** Open the full native Settings page (sliders, toggles, web monitor, CarPlay). */
    openSettings(): Promise<{
        opened: boolean;
    }>;
    /** Open the Notification Settings page (per-type push toggles + voice). */
    openNotificationSettings(): Promise<{
        opened: boolean;
    }>;
    /** Open the Geofence Manager page (map + zone list). */
    openGeofenceManager(): Promise<{
        opened: boolean;
    }>;
    /** Open the main TripTracker map + tracking view. */
    openMainView(): Promise<{
        opened: boolean;
    }>;
    /** Open the Trip History page. */
    openHistory(): Promise<{
        opened: boolean;
    }>;
    /** Open Daily Locations page. */
    openDailyLocations(): Promise<{
        opened: boolean;
    }>;
    /** Get current tracking status, speed, distance, trip info. */
    getTrackingStatus(): Promise<TrackingStatus>;
    /** Get current GPS coordinates. */
    getCurrentLocation(): Promise<LocationResult>;
    /** Get trip history. */
    getTripHistory(options?: {
        limit?: number;
    }): Promise<TripHistoryResult>;
    /** Get all current settings. */
    getSettings(): Promise<SettingsResult>;
    /**
     * Update a single setting.
     * Keys: vehicleThreshold, saveIntervalMinutes, saveDistanceMeters,
     *       autoEndTimeoutMinutes, routeGapThresholdMeters, webMonitorEnabled,
     *       voiceFeedbackEnabled, geofencingEnabled
     */
    updateSetting(options: {
        key: string;
        value: number | boolean;
    }): Promise<{
        key: string;
        updated: boolean;
    }>;
    /** Get all geofence zones. */
    getGeofenceZones(): Promise<GeofenceZonesResult>;
    /** Add a new geofence zone. */
    addGeofenceZone(options: AddGeofenceOptions): Promise<{
        id: string;
        added: boolean;
    }>;
    /** Remove a geofence zone by ID. */
    removeGeofenceZone(options: {
        id: string;
    }): Promise<{
        id: string;
        removed: boolean;
    }>;
    /** Start the web monitor HTTP server on port 8080. */
    startWebMonitor(): Promise<{
        started: boolean;
    }>;
    /** Stop the web monitor server to save battery. */
    stopWebMonitor(): Promise<{
        stopped: boolean;
    }>;
    /** Share today's log file via share sheet. */
    sendTodayLog(): Promise<{
        shared: boolean;
    }>;
    /** Share all log files via share sheet. */
    sendAllLogs(): Promise<{
        shared: boolean;
        count: number;
    }>;
}
export interface TrackingStatus {
    isTracking: boolean;
    speed: number;
    speedKmh: number;
    distance: number;
    duration: number;
    steps: number;
    tripId: number;
    latitude?: number;
    longitude?: number;
}
export interface LocationResult {
    latitude: number;
    longitude: number;
    speed: number;
    speedKmh: number;
}
export interface TripHistoryResult {
    trips: TripInfo[];
    count: number;
}
export interface TripInfo {
    id: number;
    startTime: number;
    endTime: number;
    distance: number;
    duration: number;
    isActive: boolean;
}
export interface SettingsResult {
    vehicleThreshold: number;
    vehicleThresholdKmh: number;
    saveIntervalMinutes: number;
    saveDistanceMeters: number;
    autoEndTimeoutMinutes: number;
    routeGapThresholdMeters: number;
    webMonitorEnabled: boolean;
    voiceFeedbackEnabled: boolean;
    geofencingEnabled: boolean;
    notifyTripStart: boolean;
    notifyTripEnd: boolean;
    notifyDistanceKm: boolean;
    notifyGeofenceEnter: boolean;
    notifyGeofenceExit: boolean;
}
export interface GeofenceZonesResult {
    zones: GeofenceZoneInfo[];
    count: number;
}
export interface GeofenceZoneInfo {
    id: string;
    name: string;
    latitude: number;
    longitude: number;
    radius: number;
    notifyOnEnter: boolean;
    notifyOnExit: boolean;
    autoStopOnEnter: boolean;
}
export interface AddGeofenceOptions {
    name: string;
    latitude: number;
    longitude: number;
    radius?: number;
    notifyOnEnter?: boolean;
    notifyOnExit?: boolean;
    autoStopOnEnter?: boolean;
}
export interface TripTrackerConfigOptions {
    /** Still/slow periodic save interval in minutes (default 15) */
    saveIntervalMinutes?: number;
    /** GPS save distance threshold in meters (default 30) */
    saveDistanceMeters?: number;
    /** Vehicle speed threshold in m/s (default 6.0 = 22 km/h) */
    vehicleThreshold?: number;
    /** Transport type: 0=Car, 1=Moto, 2=Bike, 3=Walk (default 0) */
    transportType?: number;
    /** Auto-stop timeout in minutes (default 5) */
    autoStopTimeoutMinutes?: number;
    /** Route gap threshold in meters (default 500) */
    routeGapMeters?: number;
    /** Enable geofence monitoring (default false) */
    geofenceEnabled?: boolean;
    /** Enable web monitor HTTP server (default false) */
    webMonitorEnabled?: boolean;
    /** Enable voice feedback (default true) */
    voiceFeedbackEnabled?: boolean;
    /** Enable push for trip start (default true) */
    notifyTripStart?: boolean;
    /** Enable push for trip end (default true) */
    notifyTripEnd?: boolean;
    /** Enable push every 1 km (default true) */
    notifyDistanceKm?: boolean;
    /** Enable push for geofence enter (default true) */
    notifyGeofenceEnter?: boolean;
    /** Enable push for geofence exit (default true) */
    notifyGeofenceExit?: boolean;
    /** POST endpoint for location pings, e.g. "https://api.example.com/ping/v2" */
    pingURL?: string;
    /** POST endpoint for trip end, e.g. "https://api.example.com/end" */
    endURL?: string;
    /** User ID sent with every API call */
    userId?: string;
    /** Vehicle ID sent with every API call */
    vehicleId?: string;
    /** OS info string (default auto-detected) */
    osInfo?: string;
    /** Route/trip ID sent with pings */
    routeId?: string;
    /** Value for AuthorizationKey header */
    authorizationKey?: string;
    /** Value for api-auth-key header */
    apiAuthKey?: string;
}
