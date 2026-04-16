import { WebPlugin } from '@capacitor/core';
export class TripTrackerWeb extends WebPlugin {
    async initializeWithConfig() {
        throw this.unavailable('initializeWithConfig is only available on iOS/Android');
    }
    async openSettings() {
        throw this.unavailable('openSettings is only available on iOS');
    }
    async openNotificationSettings() {
        throw this.unavailable('openNotificationSettings is only available on iOS');
    }
    async openGeofenceManager() {
        throw this.unavailable('openGeofenceManager is only available on iOS/Android');
    }
    async openMainView() {
        throw this.unavailable('openMainView is only available on iOS/Android');
    }
    async openHistory() {
        throw this.unavailable('openHistory is only available on iOS/Android');
    }
    async openDailyLocations() {
        throw this.unavailable('openDailyLocations is only available on iOS/Android');
    }
    async getTrackingStatus() {
        throw this.unavailable('getTrackingStatus is only available on iOS');
    }
    async getCurrentLocation() {
        throw this.unavailable('getCurrentLocation is only available on iOS');
    }
    async getTripHistory() {
        throw this.unavailable('getTripHistory is only available on iOS');
    }
    async getSettings() {
        throw this.unavailable('getSettings is only available on iOS');
    }
    async updateSetting() {
        throw this.unavailable('updateSetting is only available on iOS');
    }
    async getGeofenceZones() {
        throw this.unavailable('getGeofenceZones is only available on iOS');
    }
    async addGeofenceZone() {
        throw this.unavailable('addGeofenceZone is only available on iOS');
    }
    async removeGeofenceZone() {
        throw this.unavailable('removeGeofenceZone is only available on iOS');
    }
    async startWebMonitor() {
        throw this.unavailable('startWebMonitor is only available on iOS');
    }
    async stopWebMonitor() {
        throw this.unavailable('stopWebMonitor is only available on iOS');
    }
    async sendTodayLog() {
        throw this.unavailable('sendTodayLog is only available on iOS');
    }
    async sendAllLogs() {
        throw this.unavailable('sendAllLogs is only available on iOS');
    }
}
//# sourceMappingURL=web.js.map