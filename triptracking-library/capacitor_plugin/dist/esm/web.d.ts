import { WebPlugin } from '@capacitor/core';
import type { TripTrackerPlugin } from './definitions';
export declare class TripTrackerWeb extends WebPlugin implements TripTrackerPlugin {
    initializeWithConfig(): Promise<{
        initialized: boolean;
    }>;
    openSettings(): Promise<{
        opened: boolean;
    }>;
    openNotificationSettings(): Promise<{
        opened: boolean;
    }>;
    openGeofenceManager(): Promise<{
        opened: boolean;
    }>;
    openMainView(): Promise<{
        opened: boolean;
    }>;
    openHistory(): Promise<{
        opened: boolean;
    }>;
    openDailyLocations(): Promise<{
        opened: boolean;
    }>;
    getTrackingStatus(): Promise<any>;
    getCurrentLocation(): Promise<any>;
    getTripHistory(): Promise<any>;
    getSettings(): Promise<any>;
    updateSetting(): Promise<any>;
    getGeofenceZones(): Promise<any>;
    addGeofenceZone(): Promise<any>;
    removeGeofenceZone(): Promise<any>;
    startWebMonitor(): Promise<any>;
    stopWebMonitor(): Promise<any>;
    sendTodayLog(): Promise<any>;
    sendAllLogs(): Promise<any>;
}
