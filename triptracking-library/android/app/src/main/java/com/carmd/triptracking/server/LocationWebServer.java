package com.carmd.triptracking.server;

import android.content.Context;
import android.util.Log;
import com.carmd.triptracking.database.LocationDatabase;
import com.carmd.triptracking.ui.AppSettings;
import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.PrintWriter;
import java.net.ServerSocket;
import java.net.Socket;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Locale;

/**
 * Simple HTTP server to display real-time location tracking status
 * Access via http://[phone-ip]:8080 from any browser
 */
public class LocationWebServer {
    private static final String TAG = "LocationWebServer";
    private static final int PORT = 8081;
    
    private ServerSocket serverSocket;
    private Thread serverThread;
    private boolean isRunning = false;
    private LocationDatabase database;
    private Context context;
    
    public LocationWebServer(Context context) {
        this.context = context.getApplicationContext();
        this.database = LocationDatabase.getInstance(context);
    }
    
    public void start() {
        if (isRunning) {
            Log.w(TAG, "Server already running");
            return;
        }
        
        serverThread = new Thread(new ServerRunnable());
        serverThread.start();
        Log.d(TAG, "🌐 Web server started on port " + PORT);
    }
    
    public void stop() {
        isRunning = false;
        try {
            if (serverSocket != null) {
                serverSocket.close();
            }
        } catch (IOException e) {
            e.printStackTrace();
        }
        Log.d(TAG, "🛑 Web server stopped");
    }
    
    public boolean isRunning() {
        return isRunning;
    }
    
    private class ServerRunnable implements Runnable {
        @Override
        public void run() {
            try {
                serverSocket = new ServerSocket(PORT);
                isRunning = true;
                
                while (isRunning) {
                    try {
                        Socket socket = serverSocket.accept();
                        handleRequest(socket);
                    } catch (IOException e) {
                        if (isRunning) {
                            Log.e(TAG, "Error accepting connection: " + e.getMessage());
                        }
                    }
                }
            } catch (IOException e) {
                Log.e(TAG, "Could not start server: " + e.getMessage());
            }
        }
    }
    
    private void handleRequest(Socket socket) {
        try {
            BufferedReader in = new BufferedReader(new InputStreamReader(socket.getInputStream()));
            PrintWriter out = new PrintWriter(socket.getOutputStream());
            
            // Read request line
            String requestLine = in.readLine();
            if (requestLine == null) return;
            
            // Skip headers
            String line;
            while ((line = in.readLine()) != null && !line.isEmpty()) {
                // Skip headers
            }
            
            // Determine response based on path
            String response;
            if (requestLine.contains("/api/dates")) {
                response = getDatesJson();
            } else if (requestLine.contains("/api/trips")) {
                response = getTripsJson();
            } else if (requestLine.contains("/api/trip/") && requestLine.contains("/locations")) {
                // Extract trip ID from /api/trip/{id}/locations
                String tripIdStr = requestLine.substring(requestLine.indexOf("/api/trip/") + 10);
                tripIdStr = tripIdStr.substring(0, tripIdStr.indexOf("/"));
                long tripId = Long.parseLong(tripIdStr);
                response = getTripLocationsJson(tripId);
            } else if (requestLine.contains("/api/locations")) {
                // Extract date parameter if present
                String date = null;
                if (requestLine.contains("?date=")) {
                    int start = requestLine.indexOf("?date=") + 6;
                    int end = requestLine.indexOf(" ", start);
                    if (end == -1) end = requestLine.length();
                    date = requestLine.substring(start, end);
                }
                response = getJsonResponse(date);
            } else if (requestLine.contains("/api/settings")) {
                response = getSettingsJson();
            } else if (requestLine.contains("/api/status")) {
                response = getStatusJson();
            } else {
                response = getHtmlResponse();
            }
            
            // Send HTTP response
            out.println("HTTP/1.1 200 OK");
            out.println("Content-Type: " + (requestLine.contains("/api/") ? "application/json" : "text/html"));
            out.println("Access-Control-Allow-Origin: *");
            out.println("Connection: close");
            out.println();
            out.println(response);
            out.flush();
            
            socket.close();
        } catch (IOException e) {
            Log.e(TAG, "Error handling request: " + e.getMessage());
        }
    }
    
    private String getHtmlResponse() {
        // Fully self-contained — no external CSS/JS/fonts/tiles.
        // Works at localhost:8080 with no internet connection.
        return                 "<!DOCTYPE html>\n" +
                "<html>\n" +
                "<head>\n" +
                "<title>Trip Tracker Monitor</title>\n" +
                "<meta charset='UTF-8'>\n" +
                "<meta name='viewport' content='width=device-width, initial-scale=1.0'>\n" +
                "<style>\n" +
                "*{margin:0;padding:0;box-sizing:border-box}\n" +
                "body{font-family:Arial,sans-serif;background:#f5f5f5}\n" +
                ".header{background:#60B4E8;color:white;padding:15px 20px;display:flex;justify-content:space-between;align-items:center}\n" +
                ".header h1{font-size:20px}\n" +
                ".header .status{font-size:13px;opacity:.9}\n" +
                ".tabs{background:white;display:flex;border-bottom:2px solid #e0e0e0}\n" +
                ".tab{flex:1;padding:13px;text-align:center;cursor:pointer;font-weight:bold;color:#666;border-bottom:3px solid transparent}\n" +
                ".tab.active{color:#60B4E8;border-bottom-color:#60B4E8;background:#f8f9fa}\n" +
                ".tab-content{display:none}.tab-content.active{display:block}\n" +
                ".container{max-width:1200px;margin:15px auto;padding:0 15px}\n" +
                ".stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:10px;margin-bottom:15px}\n" +
                ".stat-card{background:white;padding:15px;border-radius:8px;box-shadow:0 2px 4px rgba(0,0,0,.1)}\n" +
                ".stat-card .label{color:#666;font-size:11px;margin-bottom:4px}\n" +
                ".stat-card .value{font-size:20px;font-weight:bold;color:#333}\n" +
                ".calendar-section{background:white;border-radius:8px;box-shadow:0 2px 4px rgba(0,0,0,.1);padding:15px;margin-bottom:15px}\n" +
                ".date-picker{display:flex;flex-wrap:wrap;align-items:center;gap:8px;margin-bottom:12px}\n" +
                ".date-picker input{padding:7px 10px;border:1px solid #ddd;border-radius:4px;font-size:14px}\n" +
                ".date-picker button{padding:7px 14px;background:#60B4E8;color:white;border:none;border-radius:4px;cursor:pointer;font-size:13px}\n" +
                ".date-picker button:hover{background:#4A9FD8}\n" +
                ".date-picker button.map-btn{background:#4CAF50}\n" +
                ".date-list{display:flex;flex-wrap:wrap;gap:8px}\n" +
                ".date-item{padding:10px 14px;background:#f8f9fa;border:2px solid #e0e0e0;border-radius:6px;text-align:center;cursor:pointer}\n" +
                ".date-item:hover{background:#e3f2fd;border-color:#60B4E8}\n" +
                ".date-item.active{background:#60B4E8;color:white;border-color:#60B4E8}\n" +
                ".date-item .date{font-weight:bold;font-size:13px}\n" +
                ".date-item .count{font-size:11px;opacity:.8;margin-top:3px}\n" +
                ".locations{background:white;border-radius:8px;box-shadow:0 2px 4px rgba(0,0,0,.1);overflow:hidden}\n" +
                ".loc-header{background:#f8f9fa;padding:12px 15px;border-bottom:1px solid #e0e0e0;display:flex;justify-content:space-between;align-items:center}\n" +
                ".loc-header h2{font-size:16px}\n" +
                ".location-item{padding:12px 15px;border-bottom:1px solid #f0f0f0;display:grid;grid-template-columns:80px 1fr 70px 100px;gap:8px;align-items:center}\n" +
                ".location-item:hover{background:#f8f9fa}\n" +
                ".time{color:#666;font-size:12px}\n" +
                ".coords{color:#333;font-size:13px;font-family:monospace}\n" +
                ".source{display:inline-block;padding:3px 7px;border-radius:4px;font-size:11px;font-weight:bold}\n" +
                ".source-gps{background:#e3f2fd;color:#1976d2;border:1px solid #90caf9}\n" +
                ".source-sensors{background:#e8f5e9;color:#388e3c;border:1px solid #81c784}\n" +
                ".speed-badge{display:inline-block;padding:3px 7px;border-radius:4px;font-size:11px;font-weight:bold;text-align:center}\n" +
                ".speed-stationary{background:#fff3e0;color:#f57c00}\n" +
                ".speed-slow{background:#e1f5fe;color:#0277bd}\n" +
                ".speed-fast{background:#ffebee;color:#c62828}\n" +
                ".pagination{display:flex;justify-content:center;align-items:center;gap:10px;padding:15px;background:white;border-top:1px solid #e0e0e0}\n" +
                ".pagination button{padding:7px 14px;background:#60B4E8;color:white;border:none;border-radius:4px;cursor:pointer}\n" +
                ".pagination button:disabled{background:#ccc;cursor:not-allowed}\n" +
                ".page-info{color:#666;font-size:13px}\n" +
                ".refresh-info{text-align:center;padding:12px;color:#999;font-size:13px}\n" +
                ".blink{display:inline-block;width:7px;height:7px;border-radius:50%;background:#4CAF50;margin-left:6px;animation:blink 2s infinite}\n" +
                "@keyframes blink{0%,100%{opacity:1}50%{opacity:.2}}\n" +
                ".no-data{text-align:center;padding:30px;color:#999}\n" +
                "/* Map */\n" +
                "#map-container{display:none;position:fixed;inset:0;background:rgba(0,0,0,.75);z-index:1000;flex-direction:column;align-items:center;justify-content:center}\n" +
                "#map-container.show{display:flex}\n" +
                "#map-box{background:white;border-radius:8px;width:95%;max-width:900px;max-height:90vh;display:flex;flex-direction:column;overflow:hidden}\n" +
                "#map-header{padding:15px 20px;border-bottom:1px solid #e0e0e0;display:flex;justify-content:space-between;align-items:center}\n" +
                "#map-header h2{font-size:18px}\n" +
                "#map-close{font-size:26px;cursor:pointer;color:#999;line-height:1}\n" +
                "#map-close:hover{color:#333}\n" +
                "#map-canvas{flex:1;min-height:400px;position:relative;overflow:hidden;background:#e8e8e8}\n" +
                "#map-svg{width:100%;height:100%}\n" +
                "/* Trips tab */\n" +
                ".trip-list{display:grid;gap:12px}\n" +
                ".trip-card{background:white;border-radius:8px;box-shadow:0 2px 4px rgba(0,0,0,.1);padding:18px;cursor:pointer}\n" +
                ".trip-card:hover{box-shadow:0 4px 12px rgba(0,0,0,.15)}\n" +
                ".trip-header{display:flex;justify-content:space-between;align-items:center;margin-bottom:8px}\n" +
                ".trip-date{font-size:16px;font-weight:bold;color:#333}\n" +
                ".trip-status{padding:3px 10px;border-radius:10px;font-size:11px;font-weight:bold}\n" +
                ".status-active{background:#4CAF50;color:white}\n" +
                ".status-stopped{background:#9E9E9E;color:white}\n" +
                ".trip-stats{display:grid;grid-template-columns:repeat(3,1fr);gap:10px;margin-top:10px}\n" +
                ".trip-stat{text-align:center}\n" +
                ".trip-stat-label{font-size:11px;color:#666}\n" +
                ".trip-stat-value{font-size:15px;font-weight:bold;color:#60B4E8;margin-top:3px}\n" +
                "</style>\n" +
                "</head>\n" +
                "<body>\n" +
                "<div class='header'>\n" +
                "  <h1>📍 Trip Tracker Monitor</h1>\n" +
                "  <div class='status' id='status'>Loading...</div>\n" +
                "</div>\n" +
                "<div class='tabs'>\n" +
                "  <div class='tab active' onclick='switchTab(\"live\")'>📍 Live</div>\n" +
                "  <div class='tab' onclick='switchTab(\"history\")'>🗺️ Trips</div>\n" +
                "</div>\n" +
                "\n" +
                "<div id='live-tab' class='tab-content active'>\n" +
                "<div class='container'>\n" +
                "  <div class='stats'>\n" +
                "    <div class='stat-card'><div class='label'>Total Saved</div><div class='value' id='total-count'>-</div></div>\n" +
                "    <div class='stat-card'><div class='label'>Day Count</div><div class='value' id='selected-count'>-</div></div>\n" +
                "    <div class='stat-card'><div class='label'>Last Update</div><div class='value' id='last-update' style='font-size:14px'>-</div></div>\n" +
                "    <div class='stat-card'><div class='label'>Auto Refresh</div><div class='value'>5 s</div></div>\n" +
                "  </div>\n" +
                "  <div class='calendar-section'>\n" +
                "    <div style='font-weight:bold;margin-bottom:10px'>📅 Select Date</div>\n" +
                "    <div class='date-picker'>\n" +
                "      <input type='date' id='date-input'>\n" +
                "      <button onclick='loadDateFromInput()'>Go</button>\n" +
                "      <button onclick='loadToday()'>Today</button>\n" +
                "      <button class='map-btn' onclick='showMapForDate()'>🗺️ Map</button>\n" +
                "    </div>\n" +
                "    <div id='date-list' class='date-list'></div>\n" +
                "  </div>\n" +
                "  <div class='locations'>\n" +
                "    <div class='loc-header'>\n" +
                "      <h2 id='locations-title'>Locations</h2>\n" +
                "    </div>\n" +
                "    <div id='locations-list'></div>\n" +
                "    <div class='pagination'>\n" +
                "      <button id='prev-btn' onclick='prevPage()'>« Prev</button>\n" +
                "      <span class='page-info' id='page-info'>Page 1</span>\n" +
                "      <button id='next-btn' onclick='nextPage()'>Next »</button>\n" +
                "    </div>\n" +
                "  </div>\n" +
                "  <div class='refresh-info'>Auto-refresh every 5 s <span class='blink'></span> <span id='next-refresh'></span></div>\n" +
                "</div>\n" +
                "</div>\n" +
                "\n" +
                "<div id='history-tab' class='tab-content'>\n" +
                "<div class='container'>\n" +
                "  <h2 style='margin:15px 0;font-size:18px'>🗺️ Trip Histories</h2>\n" +
                "  <div id='trips-list' class='trip-list'></div>\n" +
                "</div>\n" +
                "</div>\n" +
                "\n" +
                "<!-- Offline SVG map modal -->\n" +
                "<div id='map-container'>\n" +
                "  <div id='map-box'>\n" +
                "    <div id='map-header'>\n" +
                "      <h2 id='map-title'>Route Map</h2>\n" +
                "      <span id='map-close' onclick='closeMap()'>✕</span>\n" +
                "    </div>\n" +
                "    <div id='map-canvas'>\n" +
                "      <svg id='map-svg' xmlns='http://www.w3.org/2000/svg'></svg>\n" +
                "    </div>\n" +
                "    <div style='padding:8px 15px;font-size:12px;color:#666;background:#f8f9fa;border-top:1px solid #e0e0e0' id='map-info'></div>\n" +
                "  </div>\n" +
                "</div>\n" +
                "\n" +
                "<script>\n" +
                "var activeTab='live', selectedDate=null, currentPage=1, itemsPerPage=20;\n" +
                "var allLocations=[], refreshInterval=null, refreshCounter=5;\n" +
                "\n" +
                "function switchTab(tab){\n" +
                "  activeTab=tab;\n" +
                "  document.querySelectorAll('.tab').forEach(function(t,i){t.classList.toggle('active',i===(tab==='live'?0:1));});\n" +
                "  document.querySelectorAll('.tab-content').forEach(function(c){c.classList.remove('active');});\n" +
                "  document.getElementById(tab+'-tab').classList.add('active');\n" +
                "  if(tab==='live'){startRefresh();}\n" +
                "  else{stopRefresh();loadTrips();}\n" +
                "}\n" +
                "\n" +
                "// ── Data loading ──────────────────────────────────────────────────────────\n" +
                "function api(path,cb){\n" +
                "  var x=new XMLHttpRequest();\n" +
                "  x.open('GET',path);\n" +
                "  x.onload=function(){if(x.status===200){try{cb(JSON.parse(x.responseText));}catch(e){}}};\n" +
                "  x.onerror=function(){document.getElementById('status').textContent='🔴 Server unreachable';};\n" +
                "  x.send();\n" +
                "}\n" +
                "\n" +
                "function loadLocations(){\n" +
                "  var url=selectedDate?'/api/locations?date='+selectedDate:'/api/locations';\n" +
                "  api(url,function(data){\n" +
                "    allLocations=data.locations||[];\n" +
                "    document.getElementById('status').textContent='🟢 Live';\n" +
                "    document.getElementById('total-count').textContent=data.total_count||0;\n" +
                "    document.getElementById('selected-count').textContent=allLocations.length;\n" +
                "    document.getElementById('last-update').textContent=new Date().toLocaleTimeString();\n" +
                "    var title=selectedDate?'Locations for '+fmtDateLong(selectedDate):'Recent Locations';\n" +
                "    document.getElementById('locations-title').textContent=title;\n" +
                "    displayPage();\n" +
                "  });\n" +
                "}\n" +
                "\n" +
                "function loadDates(){\n" +
                "  api('/api/dates',function(data){\n" +
                "    var list=document.getElementById('date-list');\n" +
                "    var dates=data.dates||[];\n" +
                "    if(!dates.length){list.innerHTML='<div class=\"no-data\">No dates yet</div>';return;}\n" +
                "    list.innerHTML=dates.map(function(d){\n" +
                "      return \"<div class='date-item\"+(selectedDate===d.date?' active':'')+\"' onclick='selectDate(\\\"\"+d.date+\"\\\")'>\"\n" +
                "        +\"<div class='date'>\"+fmtDate(d.date)+\"</div>\"\n" +
                "        +\"<div class='count'>\"+d.count+\" pts</div></div>\";\n" +
                "    }).join('');\n" +
                "  });\n" +
                "}\n" +
                "\n" +
                "function loadTrips(){\n" +
                "  api('/api/trips',function(trips){\n" +
                "    var list=document.getElementById('trips-list');\n" +
                "    if(!trips.length){list.innerHTML='<div class=\"no-data\">No trips yet</div>';return;}\n" +
                "    list.innerHTML=trips.map(function(t){\n" +
                "      var start=new Date(t.startTime).toLocaleString();\n" +
                "      var dur=Math.floor(t.duration/60)+' min';\n" +
                "      var dist=t.distance<1000?t.distance.toFixed(0)+' m':(t.distance/1000).toFixed(2)+' km';\n" +
                "      var sc=t.status==='active'?'status-active':'status-stopped';\n" +
                "      return \"<div class='trip-card' onclick='viewTrip(\"+t.id+\")'>\"\n" +
                "        +\"<div class='trip-header'><div class='trip-date'>\"+start+\"</div>\"\n" +
                "        +\"<div class='trip-status \"+sc+\"'>\"+t.status+\"</div></div>\"\n" +
                "        +\"<div class='trip-stats'>\"\n" +
                "        +\"<div class='trip-stat'><div class='trip-stat-label'>Distance</div><div class='trip-stat-value'>\"+dist+\"</div></div>\"\n" +
                "        +\"<div class='trip-stat'><div class='trip-stat-label'>Duration</div><div class='trip-stat-value'>\"+dur+\"</div></div>\"\n" +
                "        +\"<div class='trip-stat'><div class='trip-stat-label'>Points</div><div class='trip-stat-value'>\"+(t.pointCount||0)+\"</div></div>\"\n" +
                "        +\"</div></div>\";\n" +
                "    }).join('');\n" +
                "  });\n" +
                "}\n" +
                "\n" +
                "// ── Display ───────────────────────────────────────────────────────────────\n" +
                "function displayPage(){\n" +
                "  var start=(currentPage-1)*itemsPerPage, end=start+itemsPerPage;\n" +
                "  var page=allLocations.slice(start,end);\n" +
                "  var list=document.getElementById('locations-list');\n" +
                "  if(!page.length){list.innerHTML='<div class=\"no-data\">No locations for this date</div>';}\n" +
                "  else{\n" +
                "    list.innerHTML=page.map(function(loc){\n" +
                "      var spd=loc.speed||0, kmh=(spd*3.6).toFixed(1);\n" +
                "      var cat,cls;\n" +
                "      if(spd<0.5){cat='STILL';cls='speed-stationary';}\n" +
                "      else if(spd>=6){cat='FAST';cls='speed-fast';}\n" +
                "      else{cat='SLOW';cls='speed-slow';}\n" +
                "      var src=(loc.source||'').toLowerCase().replace('/','_');\n" +
                "      return \"<div class='location-item'>\"\n" +
                "        +\"<div class='time'>\"+loc.time+\"</div>\"\n" +
                "        +\"<div class='coords'>\"+loc.latitude.toFixed(6)+\", \"+loc.longitude.toFixed(6)+\"</div>\"\n" +
                "        +\"<div><span class='source source-\"+src+\"'>\"+loc.source+\"</span></div>\"\n" +
                "        +\"<div><span class='speed-badge \"+cls+\"'>\"+cat+\"<br>\"+kmh+\" km/h</span></div>\"\n" +
                "        +\"</div>\";\n" +
                "    }).join('');\n" +
                "  }\n" +
                "  var total=Math.ceil(allLocations.length/itemsPerPage)||1;\n" +
                "  document.getElementById('page-info').textContent='Page '+currentPage+' of '+total+' ('+allLocations.length+')';\n" +
                "  document.getElementById('prev-btn').disabled=currentPage===1;\n" +
                "  document.getElementById('next-btn').disabled=currentPage>=total;\n" +
                "}\n" +
                "\n" +
                "function prevPage(){if(currentPage>1){currentPage--;displayPage();}}\n" +
                "function nextPage(){var t=Math.ceil(allLocations.length/itemsPerPage);if(currentPage<t){currentPage++;displayPage();}}\n" +
                "function selectDate(d){selectedDate=d;currentPage=1;loadDates();loadLocations();}\n" +
                "function loadToday(){var t=new Date().toISOString().split('T')[0];document.getElementById('date-input').value=t;selectDate(t);}\n" +
                "function loadDateFromInput(){var d=document.getElementById('date-input').value;if(d)selectDate(d);}\n" +
                "\n" +
                "// ── Offline SVG map ───────────────────────────────────────────────────────\n" +
                "function drawMap(coords, title, info){\n" +
                "  if(!coords||coords.length<2){alert('Not enough points to draw a route');return;}\n" +
                "  document.getElementById('map-title').textContent=title||'Route Map';\n" +
                "  document.getElementById('map-info').textContent=info||'';\n" +
                "  document.getElementById('map-container').classList.add('show');\n" +
                "\n" +
                "  var svg=document.getElementById('map-svg');\n" +
                "  var W=svg.parentElement.clientWidth||800, H=Math.max(svg.parentElement.clientHeight||450,400);\n" +
                "  svg.setAttribute('viewBox','0 0 '+W+' '+H);\n" +
                "  svg.innerHTML='';\n" +
                "\n" +
                "  // Compute bounds\n" +
                "  var lats=coords.map(function(c){return c[0];}), lngs=coords.map(function(c){return c[1];});\n" +
                "  var minLat=Math.min.apply(null,lats), maxLat=Math.max.apply(null,lats);\n" +
                "  var minLng=Math.min.apply(null,lngs), maxLng=Math.max.apply(null,lngs);\n" +
                "  var pad=40;\n" +
                "  var scaleX=maxLng===minLng?1:(W-pad*2)/(maxLng-minLng);\n" +
                "  var scaleY=maxLat===minLat?1:(H-pad*2)/(maxLat-minLat);\n" +
                "  var scale=Math.min(scaleX,scaleY);\n" +
                "\n" +
                "  function px(lat,lng){\n" +
                "    return [(lng-minLng)*scale+pad, H-((lat-minLat)*scale+pad)];\n" +
                "  }\n" +
                "\n" +
                "  // Background\n" +
                "  var bg=document.createElementNS('http://www.w3.org/2000/svg','rect');\n" +
                "  bg.setAttribute('width',W);bg.setAttribute('height',H);bg.setAttribute('fill','#e8f4e8');\n" +
                "  svg.appendChild(bg);\n" +
                "\n" +
                "  // Grid lines\n" +
                "  var grid=document.createElementNS('http://www.w3.org/2000/svg','g');\n" +
                "  grid.setAttribute('stroke','#ccc');grid.setAttribute('stroke-width','0.5');\n" +
                "  for(var gx=0;gx<=4;gx++){\n" +
                "    var gl=document.createElementNS('http://www.w3.org/2000/svg','line');\n" +
                "    var gxv=pad+(W-pad*2)*gx/4;\n" +
                "    gl.setAttribute('x1',gxv);gl.setAttribute('y1',0);gl.setAttribute('x2',gxv);gl.setAttribute('y2',H);\n" +
                "    grid.appendChild(gl);\n" +
                "  }\n" +
                "  for(var gy=0;gy<=4;gy++){\n" +
                "    var gh=document.createElementNS('http://www.w3.org/2000/svg','line');\n" +
                "    var gyv=pad+(H-pad*2)*gy/4;\n" +
                "    gh.setAttribute('x1',0);gh.setAttribute('y1',gyv);gh.setAttribute('x2',W);gh.setAttribute('y2',gyv);\n" +
                "    grid.appendChild(gh);\n" +
                "  }\n" +
                "  svg.appendChild(grid);\n" +
                "\n" +
                "  // Route polyline\n" +
                "  var points=coords.map(function(c){var p=px(c[0],c[1]);return p[0]+','+p[1];}).join(' ');\n" +
                "  var poly=document.createElementNS('http://www.w3.org/2000/svg','polyline');\n" +
                "  poly.setAttribute('points',points);\n" +
                "  poly.setAttribute('fill','none');poly.setAttribute('stroke','#2196F3');\n" +
                "  poly.setAttribute('stroke-width','3');poly.setAttribute('stroke-linejoin','round');\n" +
                "  poly.setAttribute('stroke-linecap','round');\n" +
                "  svg.appendChild(poly);\n" +
                "\n" +
                "  // Start marker (green circle)\n" +
                "  var sp=px(coords[0][0],coords[0][1]);\n" +
                "  var sm=document.createElementNS('http://www.w3.org/2000/svg','circle');\n" +
                "  sm.setAttribute('cx',sp[0]);sm.setAttribute('cy',sp[1]);sm.setAttribute('r','8');\n" +
                "  sm.setAttribute('fill','#4CAF50');sm.setAttribute('stroke','white');sm.setAttribute('stroke-width','2');\n" +
                "  svg.appendChild(sm);\n" +
                "  var sl=document.createElementNS('http://www.w3.org/2000/svg','text');\n" +
                "  sl.setAttribute('x',sp[0]+11);sl.setAttribute('y',sp[1]+4);sl.setAttribute('font-size','12');sl.setAttribute('fill','#333');\n" +
                "  sl.textContent='Start';svg.appendChild(sl);\n" +
                "\n" +
                "  // End marker (red circle)\n" +
                "  var ep=px(coords[coords.length-1][0],coords[coords.length-1][1]);\n" +
                "  var em=document.createElementNS('http://www.w3.org/2000/svg','circle');\n" +
                "  em.setAttribute('cx',ep[0]);em.setAttribute('cy',ep[1]);em.setAttribute('r','8');\n" +
                "  em.setAttribute('fill','#F44336');em.setAttribute('stroke','white');em.setAttribute('stroke-width','2');\n" +
                "  svg.appendChild(em);\n" +
                "  var el=document.createElementNS('http://www.w3.org/2000/svg','text');\n" +
                "  el.setAttribute('x',ep[0]+11);el.setAttribute('y',ep[1]+4);el.setAttribute('font-size','12');el.setAttribute('fill','#333');\n" +
                "  el.textContent='End';svg.appendChild(el);\n" +
                "\n" +
                "  // Coord labels (corners)\n" +
                "  function coordLabel(txt,x,y,anchor){\n" +
                "    var t=document.createElementNS('http://www.w3.org/2000/svg','text');\n" +
                "    t.setAttribute('x',x);t.setAttribute('y',y);t.setAttribute('font-size','10');\n" +
                "    t.setAttribute('fill','#888');t.setAttribute('text-anchor',anchor||'start');\n" +
                "    t.textContent=txt;svg.appendChild(t);\n" +
                "  }\n" +
                "  coordLabel(minLat.toFixed(4)+', '+minLng.toFixed(4),5,H-5);\n" +
                "  coordLabel(maxLat.toFixed(4)+', '+maxLng.toFixed(4),W-5,12,'end');\n" +
                "}\n" +
                "\n" +
                "function showMapForDate(){\n" +
                "  if(!selectedDate){alert('Select a date first');return;}\n" +
                "  if(!allLocations||allLocations.length<2){alert('Not enough points');return;}\n" +
                "  var coords=allLocations.map(function(l){return[l.latitude,l.longitude];});\n" +
                "  drawMap(coords,'Route — '+fmtDateLong(selectedDate),allLocations.length+' points');\n" +
                "}\n" +
                "\n" +
                "function viewTrip(tripId){\n" +
                "  api('/api/trip/'+tripId+'/locations',function(data){\n" +
                "    if(!data.locations||data.locations.length<2){alert('Not enough points for this trip');return;}\n" +
                "    var coords=data.locations.map(function(l){return[l.latitude,l.longitude];});\n" +
                "    var start=data.startTime?new Date(data.startTime).toLocaleString():'Trip #'+tripId;\n" +
                "    drawMap(coords,'Trip: '+start,data.locations.length+' points');\n" +
                "  });\n" +
                "}\n" +
                "\n" +
                "function closeMap(){document.getElementById('map-container').classList.remove('show');}\n" +
                "document.getElementById('map-container').addEventListener('click',function(e){\n" +
                "  if(e.target===this)closeMap();\n" +
                "});\n" +
                "\n" +
                "// ── Refresh ───────────────────────────────────────────────────────────────\n" +
                "function startRefresh(){\n" +
                "  loadDates();loadLocations();\n" +
                "  if(!refreshInterval){\n" +
                "    refreshInterval=setInterval(function(){if(activeTab==='live')loadLocations();},5000);\n" +
                "  }\n" +
                "}\n" +
                "function stopRefresh(){if(refreshInterval){clearInterval(refreshInterval);refreshInterval=null;}}\n" +
                "\n" +
                "// ── Helpers ───────────────────────────────────────────────────────────────\n" +
                "function fmtDate(d){var x=new Date(d+'T00:00:00');return x.toLocaleDateString('en-US',{month:'short',day:'numeric'});}\n" +
                "function fmtDateLong(d){var x=new Date(d+'T00:00:00');return x.toLocaleDateString('en-US',{year:'numeric',month:'long',day:'numeric'});}\n" +
                "\n" +
                "// Countdown\n" +
                "setInterval(function(){\n" +
                "  refreshCounter--;if(refreshCounter<0)refreshCounter=5;\n" +
                "  document.getElementById('next-refresh').textContent='(next in '+refreshCounter+'s)';\n" +
                "},1000);\n" +
                "\n" +
                "// Init\n" +
                "document.getElementById('date-input').value=new Date().toISOString().split('T')[0];\n" +
                "loadToday();\n" +
                "startRefresh();\n" +
                "</script>\n" +
                "</body>\n" +
                "</html>\n";
    }
    
    private String getJsonResponse(String date) {
        List<LocationDatabase.LocationPoint> locations;
        
        if (date != null && !date.isEmpty()) {
            // Get ALL locations for specific date (cache + trips)
            locations = database.getAllLocationsByDay(date);
        } else {
            // Get recent locations from last 24 hours (cache only)
            locations = database.getCachedLocations(24);
        }
        
        StringBuilder json = new StringBuilder();
        json.append("{");
        json.append("\"total_count\":").append(database.getCachedLocationCount()).append(",");
        json.append("\"date\":").append(date != null ? "\"" + date + "\"" : "null").append(",");
        json.append("\"locations\":[");
        
        SimpleDateFormat timeFormat = new SimpleDateFormat("HH:mm:ss", Locale.US);
        for (int i = 0; i < locations.size(); i++) {
            LocationDatabase.LocationPoint loc = locations.get(locations.size() - 1 - i);
            if (i > 0) json.append(",");
            json.append("{");
            json.append("\"latitude\":").append(loc.latitude).append(",");
            json.append("\"longitude\":").append(loc.longitude).append(",");
            json.append("\"time\":\"").append(timeFormat.format(new Date(loc.timestamp))).append("\",");
            json.append("\"speed\":").append(loc.speed).append(",");
            json.append("\"source\":\"").append(loc.source != null ? loc.source : "UNKNOWN").append("\"");
            json.append("}");
        }
        
        json.append("]}");
        return json.toString();
    }
    
    private String getDatesJson() {
        List<String> days = database.getDaysWithLocations();
        
        StringBuilder json = new StringBuilder();
        json.append("{\"dates\":[");
        
        for (int i = 0; i < days.size(); i++) {
            String day = days.get(i);
            // Get ALL locations (cache + trips) for accurate count
            List<LocationDatabase.LocationPoint> dayLocations = database.getAllLocationsByDay(day);
            
            if (i > 0) json.append(",");
            json.append("{");
            json.append("\"date\":\"").append(day).append("\",");
            json.append("\"count\":").append(dayLocations.size());
            json.append("}");
        }
        
        json.append("]}");
        return json.toString();
    }
    
    private String getTripsJson() {
        List<LocationDatabase.Trip> allTrips = database.getAllTrips();
        
        // Filter to only trips with actual location points (at least 2 for a route)
        List<LocationDatabase.Trip> tripsWithData = new ArrayList<>();
        for (LocationDatabase.Trip trip : allTrips) {
            int pointCount = database.getLocationsForTrip(trip.id).size();
            double distance = trip.distance;
            if (pointCount >= 2 && distance > 0) {  // Only include trips with actual route data
                tripsWithData.add(trip);
            }
        }
        
        StringBuilder json = new StringBuilder();
        json.append("[");
        
        for (int i = 0; i < tripsWithData.size(); i++) {
            LocationDatabase.Trip trip = tripsWithData.get(i);
            
            // Get point count for this trip
            int pointCount = database.getLocationsForTrip(trip.id).size();
            
            if (i > 0) json.append(",");
            json.append("{");
            json.append("\"id\":").append(trip.id).append(",");
            json.append("\"startTime\":").append(trip.startTime).append(",");
            json.append("\"endTime\":").append(trip.endTime).append(",");
            json.append("\"distance\":").append(trip.distance).append(",");
            json.append("\"duration\":").append(trip.duration).append(",");
            json.append("\"steps\":").append(trip.steps).append(",");
            json.append("\"status\":\"").append(trip.status).append("\",");
            json.append("\"pointCount\":").append(pointCount);
            json.append("}");
        }
        
        json.append("]");
        return json.toString();
    }
    
    private String getTripLocationsJson(long tripId) {
        List<LocationDatabase.LocationPoint> locations = database.getLocationsForTrip(tripId);
        
        // Get trip info
        List<LocationDatabase.Trip> allTrips = database.getAllTrips();
        LocationDatabase.Trip trip = null;
        for (LocationDatabase.Trip t : allTrips) {
            if (t.id == tripId) {
                trip = t;
                break;
            }
        }
        
        StringBuilder json = new StringBuilder();
        json.append("{");
        json.append("\"tripId\":").append(tripId).append(",");
        
        if (trip != null) {
            json.append("\"startTime\":").append(trip.startTime).append(",");
            json.append("\"endTime\":").append(trip.endTime).append(",");
            json.append("\"distance\":").append(trip.distance).append(",");
            json.append("\"duration\":").append(trip.duration).append(",");
        }
        
        json.append("\"locations\":[");
        
        for (int i = 0; i < locations.size(); i++) {
            LocationDatabase.LocationPoint loc = locations.get(i);
            if (i > 0) json.append(",");
            json.append("{");
            json.append("\"latitude\":").append(loc.latitude).append(",");
            json.append("\"longitude\":").append(loc.longitude).append(",");
            json.append("\"timestamp\":").append(loc.timestamp).append(",");
            json.append("\"source\":\"").append(loc.source != null ? loc.source : "").append("\",");
            json.append("\"speed\":").append(loc.speed).append(",");
            json.append("\"accuracy\":").append(loc.accuracy);
            json.append("}");
        }
        
        json.append("]}");
        return json.toString();
    }
    
    private String getSettingsJson() {
        // Intervals are now fixed constants (not user-tuneable):
        //   still → 5 min, walk → 1 min, vehicle → 30 m
        float vehicleSpeed = AppSettings.getVehicleSpeed(context);
        float routeGap     = AppSettings.getRouteGap(context);
        return "{\"still_interval_min\":5" +
               ",\"walk_interval_min\":1" +
               ",\"vehicle_distance_m\":30" +
               ",\"vehicle_speed\":" + vehicleSpeed +
               ",\"route_gap\":" + routeGap + "}";
    }

    private String getStatusJson() {
        int count = database.getCachedLocationCount();
        return "{\"status\":\"running\",\"total_locations\":" + count + "}";
    }
}
