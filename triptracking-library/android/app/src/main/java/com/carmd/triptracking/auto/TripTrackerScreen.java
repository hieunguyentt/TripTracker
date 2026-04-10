package com.carmd.triptracking.auto;

import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.ServiceConnection;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.util.Log;
import androidx.annotation.NonNull;
import androidx.car.app.AppManager;
import androidx.car.app.CarContext;
import androidx.car.app.Screen;
import androidx.car.app.model.Action;
import androidx.car.app.model.ActionStrip;
import androidx.car.app.model.Template;
import androidx.car.app.navigation.model.NavigationTemplate;
import androidx.lifecycle.DefaultLifecycleObserver;
import androidx.lifecycle.LifecycleOwner;
import com.carmd.triptracking.services.LocationTrackingService;

/**
 * Android Auto screen with interactive Google Maps.
 * Uses NavigationTemplate + SurfaceCallback with OpenStreetMap tiles.
 * Action.PAN enables touch pan/zoom on the map.
 */
public class TripTrackerScreen extends Screen {

    private static final String TAG = "TripTrackerScreen";
    private static final long REFRESH_MS = 1000L;

    private LocationTrackingService trackingService;
    private boolean serviceBound = false;
    private static TripMapRenderer mapRenderer;

    /** Called from phone app to clear route on Android Auto. */
    public static void clearAutoRoute() {
        if (mapRenderer != null) mapRenderer.clearRoute();
    }

    private final Handler refreshHandler = new Handler(Looper.getMainLooper());
    private final Runnable refreshRunnable = new Runnable() {
        @Override public void run() {
            invalidate();
            refreshHandler.postDelayed(this, REFRESH_MS);
        }
    };

    private final ServiceConnection serviceConnection = new ServiceConnection() {
        @Override
        public void onServiceConnected(ComponentName name, IBinder service) {
            LocationTrackingService.LocalBinder binder =
                    (LocationTrackingService.LocalBinder) service;
            trackingService = binder.getService();
            serviceBound = true;
            if (mapRenderer != null) mapRenderer.setTrackingService(trackingService);
            invalidate();
        }

        @Override
        public void onServiceDisconnected(ComponentName name) {
            trackingService = null;
            serviceBound = false;
        }
    };

    public TripTrackerScreen(@NonNull CarContext carContext) {
        super(carContext);

        mapRenderer = new TripMapRenderer();
        mapRenderer.setCacheDir(carContext.getCacheDir());
        try {
            carContext.getCarService(AppManager.class).setSurfaceCallback(mapRenderer);
        } catch (Exception e) {
            Log.e(TAG, "SurfaceCallback failed: " + e.getMessage());
        }

        Intent intent = new Intent(carContext, LocationTrackingService.class);
        carContext.bindService(intent, serviceConnection, Context.BIND_AUTO_CREATE);
        refreshHandler.postDelayed(refreshRunnable, REFRESH_MS);

        getLifecycle().addObserver(new DefaultLifecycleObserver() {
            @Override
            public void onDestroy(@NonNull LifecycleOwner owner) {
                refreshHandler.removeCallbacks(refreshRunnable);
                if (mapRenderer != null) mapRenderer.destroy();
                if (serviceBound) {
                    try { carContext.unbindService(serviceConnection); }
                    catch (Exception e) { /* ignored */ }
                    serviceBound = false;
                }
            }
        });
    }

    @Override
    @NonNull
    public Template onGetTemplate() {
        return new NavigationTemplate.Builder()
                .setActionStrip(new ActionStrip.Builder()
                        .addAction(Action.PAN)
                        .build())
                .build();
    }
}
