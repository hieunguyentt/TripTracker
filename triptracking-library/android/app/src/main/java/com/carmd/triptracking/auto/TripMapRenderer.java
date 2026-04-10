package com.carmd.triptracking.auto;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.Rect;
import android.graphics.RectF;
import android.graphics.Typeface;
import android.location.Location;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.util.LruCache;
import android.view.Surface;
import androidx.annotation.NonNull;
import androidx.car.app.SurfaceCallback;
import androidx.car.app.SurfaceContainer;
import com.carmd.triptracking.services.LocationTrackingService;
import com.carmd.triptracking.tracking.SensorBasedLocationTracker;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Full-screen OpenStreetMap renderer with pan/zoom for Android Auto.
 * Tiles: CartoDB dark_all. No API key needed.
 * Touch: drag=pan, pinch=zoom, fling=inertia, auto-recenters 8s.
 */
public class TripMapRenderer implements SurfaceCallback {

    private static final String TAG = "TripMapRenderer";
    private static final long RENDER_MS = 500L;
    private static final int TILE_SIZE = 256;
    private static final int MAX_TRAIL = 200;

    private static final String TILE_URL =
            "https://tile.openstreetmap.org/%d/%d/%d.png";

    private static final int TRAIL_COLOR = 0xFF1565C0, TRAIL_GLOW = 0x551565C0;
    private static final int DOT_COLOR = 0xFF1565C0, DOT_HALO = 0x441565C0;
    private static final int START_COLOR = 0xFF2E7D32;
    private static final int STATUS_GREEN = 0xCC2E7D32, STATUS_GRAY = 0xCC455A64;
    private static final int SPEED_BG = 0xBB222222, BAR_BG = 0xDD111111;
    private static final int TEXT_WHITE = 0xFFFFFFFF, TEXT_DIM = 0xAAFFFFFF;
    private static final int TEXT_LABEL = 0x99FFFFFF, VAL_ORANGE = 0xFFFF9800;
    private static final int NORTH_RED = 0xFFEF5350;

    private Surface surface;
    private int surfW, surfH;
    private LocationTrackingService svc;
    private boolean ready = false;
    private File tileCacheDir;  // disk cache for offline tiles

    private final LruCache<String, Bitmap> tileCache = new LruCache<String, Bitmap>(64) {
        @Override protected int sizeOf(String k, Bitmap b) { return 1; }
        @Override protected void entryRemoved(boolean e, String k, Bitmap o, Bitmap n) {
            if (e && o != null && !o.isRecycled()) o.recycle();
        }
    };
    private final Set<String> tilesLoading = new HashSet<>();
    private final ExecutorService tileLoader = Executors.newFixedThreadPool(3);

    private int autoZoom = 16, manualZoom = -1;
    private float panPxX = 0f, panPxY = 0f;
    private boolean userPanning = false;
    private long lastInteraction = 0;
    private static final long RECENTER_MS = 8000;
    private long lastKnownTripId = -1;  // track trip changes to clear trail
    private List<Location> lastCompletedTrail = new ArrayList<>(); // keep route after trip ends

    private final Handler handler = new Handler(Looper.getMainLooper());
    private final Runnable loop = new Runnable() {
        @Override public void run() {
            if (ready) draw();
            handler.postDelayed(this, RENDER_MS);
        }
    };

    private final Paint bgP = new Paint(), txtP = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint boxP = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint bmpP = new Paint(Paint.FILTER_BITMAP_FLAG | Paint.ANTI_ALIAS_FLAG);
    private final Paint trailP = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint dotP = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Path trailPath = new Path();

    public void setTrackingService(LocationTrackingService s) { svc = s; }
    public void setCacheDir(File dir) {
        tileCacheDir = new File(dir, "osm_tiles");
        if (!tileCacheDir.exists()) tileCacheDir.mkdirs();
    }
    /** Clear the completed route from the map. */
    public void clearRoute() {
        lastCompletedTrail.clear();
        trailPath.reset();
        lastKnownTripId = -1;
    }
    private int zoom() { return manualZoom >= 0 ? manualZoom : autoZoom; }

    private static double lonToTileX(double lon, int z) {
        return (lon + 180.0) / 360.0 * (1 << z);
    }
    private static double latToTileY(double lat, int z) {
        double r = Math.toRadians(lat);
        return (1 - Math.log(Math.tan(r) + 1 / Math.cos(r)) / Math.PI) / 2 * (1 << z);
    }

    private void ensureTile(int z, int x, int y) {
        String key = z + "/" + x + "/" + y;
        if (tileCache.get(key) != null || tilesLoading.contains(key)) return;
        tilesLoading.add(key);
        tileLoader.execute(() -> {
            try {
                // 1) Try disk cache first (works offline)
                Bitmap bmp = loadFromDisk(z, x, y);
                if (bmp != null) {
                    tileCache.put(key, bmp);
                    tilesLoading.remove(key);
                    return;
                }

                // 2) Download from network
                HttpURLConnection conn = (HttpURLConnection)
                        new URL(String.format(Locale.US, TILE_URL, z, x, y)).openConnection();
                conn.setConnectTimeout(5000); conn.setReadTimeout(5000);
                conn.setRequestProperty("User-Agent", "TripTracker/1.0");
                if (conn.getResponseCode() == 200) {
                    InputStream is = conn.getInputStream();
                    // Read all bytes so we can save to disk AND decode
                    java.io.ByteArrayOutputStream baos = new java.io.ByteArrayOutputStream();
                    byte[] buf = new byte[4096];
                    int len;
                    while ((len = is.read(buf)) != -1) baos.write(buf, 0, len);
                    is.close();
                    byte[] data = baos.toByteArray();

                    bmp = BitmapFactory.decodeByteArray(data, 0, data.length);
                    if (bmp != null) {
                        tileCache.put(key, bmp);
                        // 3) Save to disk for offline use
                        saveToDisk(z, x, y, data);
                    }
                }
                conn.disconnect();
            } catch (Exception e) {
                Log.w(TAG, "Tile: " + key);
            } finally {
                tilesLoading.remove(key);
            }
        });
    }

    private File tileFile(int z, int x, int y) {
        if (tileCacheDir == null) return null;
        File dir = new File(tileCacheDir, z + "/" + x);
        return new File(dir, y + ".png");
    }

    private Bitmap loadFromDisk(int z, int x, int y) {
        File f = tileFile(z, x, y);
        if (f == null || !f.exists()) return null;
        try {
            // Skip tiles older than 30 days
            if (System.currentTimeMillis() - f.lastModified() > 30L * 24 * 60 * 60 * 1000) {
                f.delete();
                return null;
            }
            return BitmapFactory.decodeStream(new FileInputStream(f));
        } catch (Exception e) {
            return null;
        }
    }

    private void saveToDisk(int z, int x, int y, byte[] data) {
        File f = tileFile(z, x, y);
        if (f == null) return;
        try {
            f.getParentFile().mkdirs();
            FileOutputStream fos = new FileOutputStream(f);
            fos.write(data);
            fos.close();
        } catch (Exception e) {
            Log.w(TAG, "Tile save fail: " + z + "/" + x + "/" + y);
        }
    }

    @Override public void onSurfaceAvailable(@NonNull SurfaceContainer c) {
        surface = c.getSurface(); surfW = c.getWidth(); surfH = c.getHeight();
        ready = surface != null && surface.isValid();
        if (ready) draw();
        handler.removeCallbacks(loop); handler.postDelayed(loop, RENDER_MS);
    }
    @Override public void onSurfaceDestroyed(@NonNull SurfaceContainer c) {
        ready = false; handler.removeCallbacks(loop); surface = null;
    }
    @Override public void onVisibleAreaChanged(@NonNull Rect a) {}
    @Override public void onStableAreaChanged(@NonNull Rect a) {}

    @Override public void onScroll(float dx, float dy) {
        panPxX -= dx; panPxY -= dy;
        userPanning = true; lastInteraction = System.currentTimeMillis();
    }
    @Override public void onFling(float vx, float vy) {
        panPxX += vx * 0.06f; panPxY += vy * 0.06f;
        userPanning = true; lastInteraction = System.currentTimeMillis();
    }
    @Override public void onScale(float fx, float fy, float sf) {
        int z = zoom();
        if (sf > 1.05f) z = Math.min(z + 1, 19);
        else if (sf < 0.95f) z = Math.max(z - 1, 10);
        if (z != zoom()) { float r = (float) Math.pow(2, z - zoom()); panPxX *= r; panPxY *= r; }
        manualZoom = z; userPanning = true; lastInteraction = System.currentTimeMillis();
    }

    private void draw() {
        if (surface == null || !surface.isValid()) { ready = false; return; }
        Canvas c = null;
        try { c = surface.lockHardwareCanvas(); }
        catch (Exception e1) { try { c = surface.lockCanvas(null); } catch (Exception e2) { return; } }
        if (c == null) return;
        try {
            int w = c.getWidth(), h = c.getHeight();
            boolean tracking = false; float speedKmh = 0f, heading = 0f;
            double dist = 0; long elapsed = 0, tripId = 0; int steps = 0;
            String movement = "Still"; Location loc = null;
            List<Location> trail = new ArrayList<>();

            if (svc != null) {
                tracking = svc.isCurrentlyTracking();
                // Check if phone app requested route clear
                if (svc.consumeRouteClearRequest()) {
                    lastCompletedTrail.clear();
                    trailPath.reset();
                    lastKnownTripId = -1;
                }
                float spd = svc.getCurrentGpsSpeed();
                speedKmh = spd * 3.6f; heading = svc.getCurrentHeading();
                loc = svc.getCurrentLocation();
                if (spd >= 6f) movement = "Driving";
                else if (spd >= 0.5f) movement = "Walking";
                autoZoom = spd >= 25 ? 14 : spd >= 10 ? 15 : spd >= 3 ? 16 : 17;
                if (userPanning && System.currentTimeMillis() - lastInteraction > RECENTER_MS) {
                    panPxX = 0; panPxY = 0; manualZoom = -1; userPanning = false;
                }
                if (!tracking) {
                    // Not tracking — show last completed route (if any)
                    trail = lastCompletedTrail;
                }
                if (tracking) {
                    dist = svc.getTotalDistance();
                    elapsed = (System.currentTimeMillis() - svc.getTripStartTime()) / 1000;
                    tripId = svc.getCurrentTripId();

                    // New trip or trip ID changed — clear old route
                    if (tripId != lastKnownTripId) {
                        lastCompletedTrail = new ArrayList<>();
                        trailPath.reset();
                        lastKnownTripId = tripId;
                    }

                    trail = svc.getRecentTrailLocations(MAX_TRAIL);
                    // Skip trail if trip just started (< 3 points = no meaningful route)
                    if (trail.size() < 3) trail = new ArrayList<>();
                    else lastCompletedTrail = new ArrayList<>(trail); // save for after trip ends
                    SensorBasedLocationTracker.TrackingStats st = svc.getTrackingStats();
                    if (st != null) steps = st.getStepCount();
                }
            }
            drawMap(c, w, h, loc, trail, heading);
            drawStatusBar(c, w, h, tracking, tripId, movement);
            drawSpeedPill(c, w, h, speedKmh);
            drawCompass(c, w, h, heading);
            drawBottomBar(c, w, h, tracking, dist, elapsed, steps);
            if (userPanning) {
                long rem = RECENTER_MS - (System.currentTimeMillis() - lastInteraction);
                if (rem > 0) {
                    String hint = "Re-centers in " + (rem / 1000 + 1) + "s";
                    txtP.setTextSize(13); float tw = txtP.measureText(hint);
                    float px = w / 2f, py = h * 0.87f;
                    boxP.setColor(0xCCFFFFFF); boxP.setStyle(Paint.Style.FILL);
                    c.drawRoundRect(new RectF(px-tw/2-14,py-16,px+tw/2+14,py+6),10,10,boxP);
                    txtP.setColor(0xFF333333); txtP.setTextAlign(Paint.Align.CENTER);
                    txtP.setTypeface(Typeface.DEFAULT); c.drawText(hint, px, py, txtP);
                }
            }
            txtP.setColor(0x88000000); txtP.setTextAlign(Paint.Align.RIGHT);
            txtP.setTextSize(9); c.drawText("© OpenStreetMap", w - 8, h - 60, txtP);
        } finally { try { surface.unlockCanvasAndPost(c); } catch (Exception e) {} }
    }

    private void drawMap(Canvas c, int w, int h, Location loc,
                          List<Location> trail, float heading) {
        bgP.setColor(0xFFE8E4D8); c.drawRect(0, 0, w, h, bgP);
        if (loc == null) {
            txtP.setColor(0xFF555555); txtP.setTextAlign(Paint.Align.CENTER);
            txtP.setTextSize(16); c.drawText("Acquiring GPS…", w/2f, h/2f, txtP); return;
        }
        int z = zoom();
        double gpsTX = lonToTileX(loc.getLongitude(), z);
        double gpsTY = latToTileY(loc.getLatitude(), z);
        double vTX = gpsTX - panPxX / TILE_SIZE, vTY = gpsTY - panPxY / TILE_SIZE;
        float cx = w/2f, cy = h/2f;
        int cxi = (int)Math.floor(vTX), cyi = (int)Math.floor(vTY);
        float ox = cx - (float)((vTX - cxi) * TILE_SIZE);
        float oy = cy - (float)((vTY - cyi) * TILE_SIZE);
        int maxT = (1 << z) - 1, tH = w/TILE_SIZE+3, tV = h/TILE_SIZE+3;

        for (int dx = -tH/2; dx <= tH/2; dx++)
            for (int dy = -tV/2; dy <= tV/2; dy++) {
                int tx = cxi+dx, ty = cyi+dy;
                int wtx = ((tx%(maxT+1))+(maxT+1))%(maxT+1);
                if (ty < 0 || ty > maxT) continue;
                float px = ox+dx*TILE_SIZE, py = oy+dy*TILE_SIZE;
                Bitmap tile = tileCache.get(z+"/"+wtx+"/"+ty);
                if (tile != null && !tile.isRecycled())
                    c.drawBitmap(tile, new Rect(0,0,tile.getWidth(),tile.getHeight()),
                            new RectF(px,py,px+TILE_SIZE,py+TILE_SIZE), bmpP);
                ensureTile(z, wtx, ty);
            }

        float gpX = cx+(float)((gpsTX-vTX)*TILE_SIZE);
        float gpY = cy+(float)((gpsTY-vTY)*TILE_SIZE);

        if (trail.size() >= 2) {
            trailP.setStyle(Paint.Style.STROKE); trailP.setStrokeCap(Paint.Cap.ROUND);
            trailP.setStrokeJoin(Paint.Join.ROUND);
            trailP.setColor(TRAIL_GLOW); trailP.setStrokeWidth(8f);
            drawTrail(c, trail, z, vTX, vTY, cx, cy);
            trailP.setColor(TRAIL_COLOR); trailP.setStrokeWidth(4f);
            drawTrail(c, trail, z, vTX, vTY, cx, cy);
            Location f = trail.get(0);
            float sx = cx+(float)((lonToTileX(f.getLongitude(),z)-vTX)*TILE_SIZE);
            float sy = cy+(float)((latToTileY(f.getLatitude(),z)-vTY)*TILE_SIZE);
            dotP.setColor(START_COLOR); dotP.setStyle(Paint.Style.FILL);
            c.drawCircle(sx, sy, 7, dotP);
        }

        dotP.setColor(DOT_HALO); dotP.setStyle(Paint.Style.FILL);
        c.drawCircle(gpX, gpY, 22, dotP);
        float sz=14, hr=(float)Math.toRadians(-heading);
        Path a = new Path();
        a.moveTo(gpX+sz*(float)Math.sin(hr), gpY-sz*(float)Math.cos(hr));
        a.lineTo(gpX+sz*0.5f*(float)Math.sin(hr+Math.PI*0.8), gpY-sz*0.5f*(float)Math.cos(hr+Math.PI*0.8));
        a.lineTo(gpX+sz*0.5f*(float)Math.sin(hr-Math.PI*0.8), gpY-sz*0.5f*(float)Math.cos(hr-Math.PI*0.8));
        a.close(); dotP.setColor(DOT_COLOR); c.drawPath(a, dotP);
        dotP.setColor(TEXT_WHITE); c.drawCircle(gpX, gpY, 4, dotP);
    }

    private void drawTrail(Canvas c, List<Location> trail, int z,
                            double vTX, double vTY, float cx, float cy) {
        trailPath.reset(); boolean first = true;
        for (Location p : trail) {
            float px = cx+(float)((lonToTileX(p.getLongitude(),z)-vTX)*TILE_SIZE);
            float py = cy+(float)((latToTileY(p.getLatitude(),z)-vTY)*TILE_SIZE);
            if (first) { trailPath.moveTo(px,py); first=false; } else trailPath.lineTo(px,py);
        }
        c.drawPath(trailPath, trailP);
    }

    private void drawStatusBar(Canvas c, int w, int h, boolean t, long id, String m) {
        float bH = Math.max(32, h*0.065f);
        boxP.setColor(t?STATUS_GREEN:STATUS_GRAY); boxP.setStyle(Paint.Style.FILL);
        c.drawRect(0,0,w,bH,boxP);
        txtP.setColor(TEXT_WHITE); txtP.setTextAlign(Paint.Align.LEFT);
        txtP.setTypeface(Typeface.create(Typeface.DEFAULT,Typeface.BOLD));
        txtP.setTextSize(bH*0.5f);
        c.drawText(t?"  TRACKING — Trip #"+id:"  IDLE",8,bH*0.67f,txtP);
        txtP.setTextAlign(Paint.Align.RIGHT); txtP.setColor(TEXT_DIM);
        txtP.setTypeface(Typeface.DEFAULT); c.drawText(m+"  ",w-8,bH*0.67f,txtP);
    }

    private void drawSpeedPill(Canvas c, int w, int h, float spd) {
        float t=h*0.09f, l=w*0.02f, pW=w*0.14f, pH=h*0.2f;
        boxP.setColor(SPEED_BG); boxP.setStyle(Paint.Style.FILL);
        c.drawRoundRect(new RectF(l,t,l+pW,t+pH),14,14,boxP);
        txtP.setColor(TEXT_WHITE); txtP.setTextAlign(Paint.Align.CENTER);
        txtP.setTypeface(Typeface.create(Typeface.DEFAULT,Typeface.BOLD));
        txtP.setTextSize(pH*0.45f);
        c.drawText(String.format(Locale.US,"%.0f",spd),l+pW/2,t+pH*0.52f,txtP);
        txtP.setColor(TEXT_DIM); txtP.setTextSize(pH*0.18f);
        txtP.setTypeface(Typeface.DEFAULT);
        c.drawText("km/h",l+pW/2,t+pH*0.78f,txtP);
    }

    private void drawCompass(Canvas c, int w, int h, float heading) {
        float cx=w-w*0.06f, cy=h*0.1f, r=Math.min(w,h)*0.035f;
        boxP.setColor(0xAA222222); boxP.setStyle(Paint.Style.FILL);
        c.drawCircle(cx,cy,r+4,boxP);
        dotP.setColor(0xCCFFFFFF); dotP.setStyle(Paint.Style.STROKE);
        dotP.setStrokeWidth(1.5f); c.drawCircle(cx,cy,r,dotP);
        dotP.setStyle(Paint.Style.FILL);
        float rad=(float)Math.toRadians(-heading);
        // N dot inside circle
        dotP.setColor(NORTH_RED);
        c.drawCircle(cx+r*0.6f*(float)Math.sin(rad),cy-r*0.6f*(float)Math.cos(rad),3,dotP);
        // N label just outside circle
        txtP.setColor(NORTH_RED); txtP.setTextAlign(Paint.Align.CENTER);
        txtP.setTextSize(9); txtP.setTypeface(Typeface.create(Typeface.DEFAULT,Typeface.BOLD));
        c.drawText("N",cx+(r+6)*(float)Math.sin(rad),cy-(r+6)*(float)Math.cos(rad)+3,txtP);
    }

    private void drawBottomBar(Canvas c, int w, int h, boolean t, double d, long e, int s) {
        float bH=Math.max(50,h*0.1f), bY=h-bH;
        boxP.setColor(BAR_BG); boxP.setStyle(Paint.Style.FILL); c.drawRect(0,bY,w,h,boxP);
        if (!t) {
            txtP.setColor(VAL_ORANGE); txtP.setTextAlign(Paint.Align.CENTER);
            txtP.setTextSize(bH*0.36f); txtP.setTypeface(Typeface.create(Typeface.DEFAULT,Typeface.BOLD));
            c.drawText("Waiting for vehicle speed…",w*0.5f,bY+bH*0.62f,txtP); return;
        }
        float cW=w/2f;
        String dv=d<1000?String.format(Locale.US,"%.0f m",d):String.format(Locale.US,"%.1f km",d/1000);
        drawCell(c,0,bY,cW,bH,"DISTANCE",dv,VAL_ORANGE);
        long hr=e/3600, mn=(e%3600)/60, sc=e%60;
        String dur=hr>0?String.format(Locale.US,"%d:%02d:%02d",hr,mn,sc)
                :String.format(Locale.US,"%02d:%02d",mn,sc);
        drawCell(c,cW,bY,cW,bH,"DURATION",dur,TEXT_WHITE);
    }

    private void drawCell(Canvas c, float x, float y, float w, float h, String l, String v, int vc) {
        txtP.setColor(TEXT_LABEL); txtP.setTextAlign(Paint.Align.CENTER);
        txtP.setTextSize(h*0.2f); txtP.setTypeface(Typeface.DEFAULT);
        c.drawText(l,x+w/2,y+h*0.32f,txtP);
        txtP.setColor(vc); txtP.setTextSize(h*0.45f);
        txtP.setTypeface(Typeface.create(Typeface.DEFAULT,Typeface.BOLD));
        c.drawText(v,x+w/2,y+h*0.78f,txtP);
    }

    public void destroy() {
        handler.removeCallbacks(loop); ready=false; surface=null;
        tileLoader.shutdown(); tileCache.evictAll();
    }
}
