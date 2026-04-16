import { WebPlugin } from '@capacitor/core';

import type { TripTrackerPlugin } from './definitions';

export class TripTrackerWeb extends WebPlugin implements TripTrackerPlugin {

  async initializeWithConfig(): Promise<{ initialized: boolean }> {
    throw this.unavailable('initializeWithConfig is only available on iOS/Android');
  }

  async openSettings(): Promise<{ opened: boolean }> {
    throw this.unavailable('openSettings is only available on iOS');
  }

  async openNotificationSettings(): Promise<{ opened: boolean }> {
    throw this.unavailable('openNotificationSettings is only available on iOS');
  }

  async openGeofenceManager(): Promise<{ opened: boolean }> {
    throw this.unavailable('openGeofenceManager is only available on iOS/Android');
  }

  async openMainView(): Promise<{ opened: boolean }> {
    throw this.unavailable('openMainView is only available on iOS/Android');
  }

  async openHistory(): Promise<{ opened: boolean }> {
    throw this.unavailable('openHistory is only available on iOS/Android');
  }

  async openDailyLocations(): Promise<{ opened: boolean }> {
    throw this.unavailable('openDailyLocations is only available on iOS/Android');
  }

  async getTrackingStatus(): Promise<any> {
    throw this.unavailable('getTrackingStatus is only available on iOS');
  }

  async getCurrentLocation(): Promise<any> {
    throw this.unavailable('getCurrentLocation is only available on iOS');
  }

  async getTripHistory(): Promise<any> {
    throw this.unavailable('getTripHistory is only available on iOS');
  }

  async getSettings(): Promise<any> {
    throw this.unavailable('getSettings is only available on iOS');
  }

  async updateSetting(): Promise<any> {
    throw this.unavailable('updateSetting is only available on iOS');
  }

  async getGeofenceZones(): Promise<any> {
    throw this.unavailable('getGeofenceZones is only available on iOS');
  }

  async addGeofenceZone(): Promise<any> {
    throw this.unavailable('addGeofenceZone is only available on iOS');
  }

  async removeGeofenceZone(): Promise<any> {
    throw this.unavailable('removeGeofenceZone is only available on iOS');
  }

  async startWebMonitor(): Promise<any> {
    throw this.unavailable('startWebMonitor is only available on iOS');
  }

  async stopWebMonitor(): Promise<any> {
    throw this.unavailable('stopWebMonitor is only available on iOS');
  }

  async sendTodayLog(): Promise<any> {
    throw this.unavailable('sendTodayLog is only available on iOS');
  }

  async sendAllLogs(): Promise<any> {
    throw this.unavailable('sendAllLogs is only available on iOS');
  }
}
