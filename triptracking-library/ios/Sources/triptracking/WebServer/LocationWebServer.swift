//
//  LocationWebServer.swift
//  TripTracker
//
//  Native HTTP server using Foundation Network framework only
//  No external dependencies (no Swifter package needed!)
//

import Foundation
import Network

class LocationWebServer {
    
    private var listener: NWListener?
    private let port: NWEndpoint.Port = 8080
    private var connections: [NWConnection] = []
    
    func start() {
        do {
            // Configure TCP parameters — allow port reuse so the server
            // can restart cleanly after an app backgrounding cycle.
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true

            listener = try NWListener(using: parameters, on: port)
            
            listener?.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    if let actualPort = self?.listener?.port?.rawValue {
                        print("🌐 Web server started on port \(actualPort)")
                    }
                case .failed(let error):
                    print("❌ Web server failed: \(error)")
                    // Retry after a short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self?.listener?.cancel()
                        self?.start()
                    }
                case .cancelled:
                    print("🛑 Web server cancelled")
                default:
                    break
                }
            }
            
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            
            listener?.start(queue: .main)
            
        } catch {
            print("❌ Failed to start web server: \(error)")
        }
    }
    
    func stop() {
        listener?.cancel()
        connections.forEach { $0.cancel() }
        connections.removeAll()
        print("🛑 Web server stopped")
    }
    
    private func handleConnection(_ connection: NWConnection) {
        connections.append(connection)
        
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.receiveRequest(from: connection)
            case .failed, .cancelled:
                self?.removeConnection(connection)
            default:
                break
            }
        }
        
        connection.start(queue: .main)
    }
    
    private func receiveRequest(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            
            if let data = data, !data.isEmpty {
                if let request = String(data: data, encoding: .utf8) {
                    // processRequest → sendData → connection.cancel() handles cleanup.
                    // Do NOT cancel here or the response never reaches the browser.
                    self?.processRequest(request, connection: connection)
                    return
                }
            }
            
            if isComplete {
                // Client closed without sending data — clean up
                connection.cancel()
            } else if error == nil {
                self?.receiveRequest(from: connection)
            }
        }
    }
    
    private func processRequest(_ request: String, connection: NWConnection) {
        let lines = request.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { return }
        
        let components = firstLine.components(separatedBy: " ")
        guard components.count >= 2 else { return }
        
        let method = components[0]
        let path = components[1]
        
        guard method == "GET" else {
            sendResponse(connection: connection, statusCode: 405, body: "Method Not Allowed")
            return
        }
        
        // Route requests
        if path == "/" {
            sendHTMLResponse(connection: connection)
        } else if path == "/api/status" {
            sendJSONResponse(connection: connection, json: getStatusJSON())
        } else if path == "/api/settings" {
            sendJSONResponse(connection: connection, json: getSettingsJSON())
        } else if path == "/api/dates" {
            sendJSONResponse(connection: connection, json: getDatesJSON())
        } else if path.starts(with: "/api/locations") {
            let date = extractQueryParameter(from: path, name: "date")
            sendJSONResponse(connection: connection, json: getLocationsJSON(date: date))
        } else if path == "/api/trips" {
            sendJSONResponse(connection: connection, json: getTripsJSON())
        } else if path.starts(with: "/api/trip/") {
            if let tripId = extractTripId(from: path) {
                sendJSONResponse(connection: connection, json: getTripLocationsJSON(tripId: tripId))
            } else {
                sendResponse(connection: connection, statusCode: 400, body: "Invalid trip ID")
            }
        } else {
            sendResponse(connection: connection, statusCode: 404, body: "Not Found")
        }
    }
    
    private func sendHTMLResponse(connection: NWConnection) {
        let html = getHTMLContent()
        let body = Data(html.utf8)
        let header = "HTTP/1.1 200 OK\r\n"
            + "Content-Type: text/html; charset=utf-8\r\n"
            + "Content-Length: \(body.count)\r\n"
            + "Connection: close\r\n"
            + "\r\n"
        var response = Data(header.utf8)
        response.append(body)
        sendData(connection: connection, data: response)
    }
    
    private func sendJSONResponse(connection: NWConnection, json: String) {
        let body = Data(json.utf8)
        let header = "HTTP/1.1 200 OK\r\n"
            + "Content-Type: application/json; charset=utf-8\r\n"
            + "Content-Length: \(body.count)\r\n"
            + "Access-Control-Allow-Origin: *\r\n"
            + "Connection: close\r\n"
            + "\r\n"
        var response = Data(header.utf8)
        response.append(body)
        sendData(connection: connection, data: response)
    }
    
    private func sendResponse(connection: NWConnection, statusCode: Int, body: String) {
        let statusText = statusCode == 404 ? "Not Found" : statusCode == 405 ? "Method Not Allowed" : "Bad Request"
        let bodyData = Data(body.utf8)
        let header = "HTTP/1.1 \(statusCode) \(statusText)\r\n"
            + "Content-Type: text/plain; charset=utf-8\r\n"
            + "Content-Length: \(bodyData.count)\r\n"
            + "Connection: close\r\n"
            + "\r\n"
        var response = Data(header.utf8)
        response.append(bodyData)
        sendData(connection: connection, data: response)
    }
    
    private func sendData(connection: NWConnection, data: Data) {
        connection.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                print("❌ Send error: \(error)")
            }
            connection.cancel()
        })
    }
    
    private func removeConnection(_ connection: NWConnection) {
        connections.removeAll { $0 === connection }
    }
    
    private func extractQueryParameter(from path: String, name: String) -> String? {
        guard let queryString = path.components(separatedBy: "?").last,
              queryString.contains("=") else {
            return nil
        }
        
        let params = queryString.components(separatedBy: "&")
        for param in params {
            let keyValue = param.components(separatedBy: "=")
            if keyValue.count == 2 && keyValue[0] == name {
                return keyValue[1]
            }
        }
        return nil
    }
    
    private func extractTripId(from path: String) -> Int64? {
        let pattern = "/api/trip/(\\d+)/locations"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)),
              let range = Range(match.range(at: 1), in: path) else {
            return nil
        }
        return Int64(path[range])
    }
    
    // MARK: - JSON Responses
    
    private func getStatusJSON() -> String {
        let count = DatabaseManager.shared.getCachedLocationCount()
        return "{\"status\":\"running\",\"total_locations\":\(count)}"
    }
    
    private func getSettingsJSON() -> String {
        let ud  = UserDefaults.standard
        let svc = LocationTrackingService.shared
        let vt  = ud.object(forKey: "tt_vehicleThreshold")     != nil ? Double(ud.float(forKey: "tt_vehicleThreshold"))   : Double(svc.vehicleThreshold)
        let si  = ud.object(forKey: "tt_saveIntervalSecs")     != nil ? ud.double(forKey: "tt_saveIntervalSecs")          : Double(svc.saveIntervalMs) / 1000.0
        let sd  = ud.object(forKey: "tt_saveDistanceVehicleM") != nil ? ud.double(forKey: "tt_saveDistanceVehicleM")      : svc.saveDistanceVehicleM
        let rg  = ud.object(forKey: "tt_routeGapThresholdM")   != nil ? ud.double(forKey: "tt_routeGapThresholdM")        : 500.0
        return "{\"vehicleThreshold\":\(vt),\"saveIntervalSecs\":\(si),\"saveDistanceVehicleM\":\(sd),\"routeGapThresholdM\":\(rg)}"
    }

    private func getDatesJSON() -> String {
        let dates = DatabaseManager.shared.getDatesWithLocations()
        var json = "{\"dates\":["
        
        for (index, dateInfo) in dates.enumerated() {
            if index > 0 { json += "," }
            json += "{\"date\":\"\(dateInfo.date)\",\"count\":\(dateInfo.count)}"
        }
        
        json += "]}"
        return json
    }
    
    private func getLocationsJSON(date: String? = nil) -> String {
        let locations = DatabaseManager.shared.getCachedLocations(date: date)
        
        var json = "{\"locations\":["
        
        for (index, location) in locations.enumerated() {
            if index > 0 { json += "," }
            json += """
            {
                "time":"\(location.formattedTime)",
                "latitude":\(location.latitude),
                "longitude":\(location.longitude),
                "source":"\(location.source)",
                "speed":\(location.speed),
                "accuracy":\(location.accuracy)
            }
            """
        }
        
        json += "]}"
        return json
    }
    
    private func getTripsJSON() -> String {
        let allTrips = DatabaseManager.shared.getAllTrips()
        var tripsWithData: [(trip: Trip, pointCount: Int)] = []
        
        for trip in allTrips {
            let locations = DatabaseManager.shared.getLocationsForTrip(tripId: trip.id)
            if locations.count >= 2 {
                tripsWithData.append((trip, locations.count))
            }
        }
        
        var json = "["
        
        for (index, tripData) in tripsWithData.enumerated() {
            if index > 0 { json += "," }
            let trip = tripData.trip
            json += """
            {
                "id":\(trip.id),
                "startTime":\(trip.startTime),
                "endTime":\(trip.endTime),
                "distance":\(trip.distance),
                "duration":\(trip.duration),
                "steps":\(trip.steps),
                "status":"\(trip.status)",
                "pointCount":\(tripData.pointCount)
            }
            """
        }
        
        json += "]"
        return json
    }
    
    private func getTripLocationsJSON(tripId: Int64) -> String {
        let locations = DatabaseManager.shared.getLocationsForTrip(tripId: tripId)
        let trips = DatabaseManager.shared.getAllTrips()
        
        guard let trip = trips.first(where: { $0.id == tripId }) else {
            return "{\"error\":\"Trip not found\"}"
        }
        
        var json = """
        {
            "tripId":\(tripId),
            "startTime":\(trip.startTime),
            "endTime":\(trip.endTime),
            "distance":\(trip.distance),
            "duration":\(trip.duration),
            "locations":[
        """
        
        for (index, location) in locations.enumerated() {
            if index > 0 { json += "," }
            json += """
            {
                "latitude":\(location.latitude),
                "longitude":\(location.longitude),
                "timestamp":\(location.timestamp),
                "source":"\(location.source)",
                "speed":\(location.speed),
                "accuracy":\(location.accuracy)
            }
            """
        }
        
        json += "]}"
        return json
    }
    
    // MARK: - HTML Content (Embedded - No external file needed!)
    
    private func getHTMLContent() -> String {
        return """
<!DOCTYPE html>
<html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Trip Tracker</title><link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"/><script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script><style>*{margin:0;padding:0;box-sizing:border-box}body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',system-ui,sans-serif;background:#f5f5f5}.header{background:#2196F3;color:#fff;padding:15px 20px;box-shadow:0 2px 4px rgba(0,0,0,.1)}.header h1{font-size:20px;font-weight:600}.tabs{display:flex;background:#fff;border-bottom:2px solid #e0e0e0}.tab{flex:1;padding:15px;text-align:center;cursor:pointer;border:none;background:0 0;font-size:16px;transition:all .3s}.tab.active{background:#2196F3;color:#fff}.tab:hover:not(.active){background:#f0f0f0}.content{padding:20px;max-width:1200px;margin:0 auto}.stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:15px;margin-bottom:20px}.stat-card{background:#fff;padding:20px;border-radius:8px;box-shadow:0 2px 4px rgba(0,0,0,.1)}.stat-card .label{color:#666;font-size:14px;margin-bottom:5px}.stat-card .value{color:#333;font-size:24px;font-weight:700}.calendar-section{background:#fff;padding:20px;border-radius:8px;margin-bottom:20px;box-shadow:0 2px 4px rgba(0,0,0,.1)}.calendar-header{font-size:18px;font-weight:600;margin-bottom:15px}.date-picker{display:flex;gap:10px;margin-bottom:15px;flex-wrap:wrap}.date-picker input{padding:10px;border:1px solid #ddd;border-radius:4px;font-size:14px}.date-picker button{padding:10px 20px;background:#2196F3;color:#fff;border:none;border-radius:4px;cursor:pointer;font-size:14px}.date-picker button:hover{background:#1976D2}.date-picker button:nth-child(4){background:#4CAF50}.date-list{display:flex;gap:10px;flex-wrap:wrap}.date-tile{padding:12px 18px;background:#64B5F6;color:#fff;border-radius:10px;cursor:pointer;text-align:center;min-width:90px;transition:all .3s;box-shadow:0 2px 6px rgba(0,0,0,.15)}.date-tile:hover{background:#42A5F5;transform:translateY(-2px)}.date-tile.active{background:#1565C0;color:#fff;box-shadow:0 3px 8px rgba(0,0,0,.25)}.date-tile .date{font-weight:700;font-size:15px;color:#fff}.date-tile .count{color:rgba(255,255,255,.85);font-size:12px;margin-top:4px}.date-tile.active .count{color:rgba(255,255,255,.9)}.locations{background:#fff;padding:20px;border-radius:8px;box-shadow:0 2px 4px rgba(0,0,0,.1)}.locations-header{display:flex;justify-content:space-between;align-items:center;margin-bottom:15px}.locations-header h2{font-size:18px;font-weight:600}#locations-list{display:flex;flex-direction:column;gap:2px}.location-item{padding:12px 15px;background:#f9f9f9;border-radius:6px;border-left:4px solid #2196F3;display:flex;align-items:center;gap:12px;flex-wrap:nowrap}.location-item .time{font-weight:600;color:#333;font-size:14px;min-width:70px;flex-shrink:0}.location-item .coords{color:#666;font-size:13px;font-family:monospace;min-width:140px;flex-shrink:0}.location-item .meta{display:flex;gap:8px;margin-left:auto;align-items:center;flex-shrink:0}.badge{padding:4px 10px;border-radius:4px;font-size:12px;font-weight:600;text-align:center;line-height:1.3}.badge-sensors{background:#e8f5e9;color:#388e3c}.badge-gps{background:#e3f2fd;color:#1976d2}.badge-stationary{background:#fff3e0;color:#e65100}.badge-slow{background:#e1f5fe;color:#0277bd}.badge-fast{background:#ffebee;color:#c62828}.pagination{display:flex;justify-content:center;align-items:center;gap:15px;margin-top:20px;padding:15px}.pagination button{padding:10px 20px;background:#2196F3;color:#fff;border:none;border-radius:4px;cursor:pointer}.pagination button:disabled{background:#ccc;cursor:not-allowed}.page-info{font-weight:600}.refresh-info{text-align:center;padding:15px;color:#666;font-size:14px}.refresh-indicator{display:inline-block;width:8px;height:8px;background:#4CAF50;border-radius:50%;animation:pulse 2s infinite}@keyframes pulse{0%,100%{opacity:1}50%{opacity:.3}}.trip-list{display:grid;gap:15px}.trip-card{background:#fff;padding:20px;border-radius:8px;box-shadow:0 2px 4px rgba(0,0,0,.1);cursor:pointer;transition:all .3s}.trip-card:hover{transform:translateY(-2px);box-shadow:0 4px 8px rgba(0,0,0,.15)}.trip-header{display:flex;justify-content:space-between;align-items:center;margin-bottom:10px}.trip-date{font-size:16px;font-weight:600}.trip-status{padding:4px 12px;border-radius:12px;font-size:12px;font-weight:600}.status-active{background:#4CAF50;color:#fff}.status-stopped{background:#9E9E9E;color:#fff}.trip-stats{display:grid;grid-template-columns:repeat(3,1fr);gap:10px;margin-top:10px}.trip-stat{text-align:center}.trip-stat .label{font-size:12px;color:#666}.trip-stat .value{font-size:16px;font-weight:600;color:#333}.modal{display:none;position:fixed;top:0;left:0;width:100%;height:100%;background:rgba(0,0,0,.5);z-index:1000}.modal.show{display:flex;align-items:center;justify-content:center}.modal-content{background:#fff;border-radius:8px;width:90%;max-width:1000px;max-height:90vh;overflow:hidden}.modal-header{padding:20px;background:#2196F3;color:#fff;display:flex;justify-content:space-between;align-items:center}.modal-header h2{font-size:18px}.modal-close{background:0 0;border:none;color:#fff;font-size:24px;cursor:pointer}.modal-body{padding:20px}#map{height:600px;width:100%;border-radius:8px}</style></head><body><div class="header"><h1 id="header-title">📍 Trip Tracker - Live Locations</h1></div><div class="tabs"><button class="tab active" onclick="switchTab('live')">📍 Live Locations</button> <button class="tab" onclick="switchTab('history')">🗺️ Route Histories</button></div><div id="live-content" class="content"><div class="stats"><div class="stat-card"><div class="label">Total Locations</div><div class="value" id="total-locations">-</div></div><div class="stat-card"><div class="label">Last Update</div><div class="value" id="last-update">-</div></div><div class="stat-card"><div class="label">Auto Refresh</div><div class="value" id="auto-refresh-val">5s</div></div><div class="stat-card"><div class="label">Save Interval</div><div class="value" id="save-interval">-</div></div></div><div class="calendar-section"><div class="calendar-header">📅 Select Date</div><div class="date-picker"><input type="date" id="date-input"/> <button onclick="loadDateFromInput()">Go to Date</button> <button onclick="loadToday()">Today</button> <button onclick="showDateRouteOnMap()">🗺️ Show on Map</button></div><div id="date-list" class="date-list"></div></div><div class="locations"><div class="locations-header"><h2 id="locations-title">Recent Locations</h2></div><div id="locations-list"></div><div class="pagination"><button id="prev-btn" onclick="prevPage()">« Previous</button> <span class="page-info" id="page-info">Page 1</span> <button id="next-btn" onclick="nextPage()">Next »</button></div></div><div class="refresh-info">Auto-refreshing every <span id="refresh-rate">save interval</span> <span class="refresh-indicator"></span> <span id="next-refresh"></span></div></div><div id="history-content" class="content" style="display:none"><h2 style="margin-bottom:20px">🗺️ All Route Histories</h2><div id="trip-list" class="trip-list"></div></div><div id="map-modal" class="modal"><div class="modal-content"><div class="modal-header"><h2 id="modal-title">Route Map</h2><button class="modal-close" onclick="closeMapModal()">×</button></div><div class="modal-body"><div id="map"></div></div></div></div><script>let allLocations=[],currentPage=1,itemsPerPage=20,selectedDate=null,autoRefreshInterval=null,map=null,currentTab="live",routeGapM=500;function switchTab(t){currentTab=t,document.querySelectorAll(".tab").forEach(t=>t.classList.remove("active")),event.target.classList.add("active"),"live"===t?(document.getElementById("live-content").style.display="block",document.getElementById("history-content").style.display="none",document.getElementById("header-title").textContent="📍 Trip Tracker - Live Locations",startAutoRefresh()):(document.getElementById("live-content").style.display="none",document.getElementById("history-content").style.display="block",document.getElementById("header-title").textContent="🗺️ Trip Tracker - Route Histories",stopAutoRefresh(),loadTrips())}async function loadStatus(){const t=await fetch("/api/status"),e=await t.json();document.getElementById("total-locations").textContent=e.total_locations,updateLastUpdate()}async function loadDates(){const t=await fetch("/api/dates"),e=await t.json(),n=document.getElementById("date-list");n.innerHTML="";const today=(new Date).toISOString().split("T")[0];e.dates.forEach((d,idx)=>{const el=document.createElement("div");el.className="date-tile"+(d.date===today||idx===0?" active":"");el.onclick=()=>loadDate(d.date);const p=d.date.split("-");const months=["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];const label=p.length===3?`${months[parseInt(p[1],10)-1]} ${parseInt(p[2],10)}`:d.date;el.innerHTML=`<div class="date">${label}</div><div class="count">${d.count} pts</div>`;n.appendChild(el)})}async function loadLocations(t=null){const e=t?`/api/locations?date=${t}`:"/api/locations",n=await fetch(e),a=await n.json();allLocations=a.locations,currentPage=1,displayPage()}function displayPage(){const seenTimes=new Set();const dedupedLocations=allLocations.filter(t=>{if(seenTimes.has(t.time))return false;seenTimes.add(t.time);return true;});const t=(currentPage-1)*itemsPerPage,e=t+itemsPerPage,n=dedupedLocations.slice(t,e),a=document.getElementById("locations-list");a.innerHTML="",n.forEach(t=>{const e=document.createElement("div");e.className="location-item";const n=getSourceBadge(t.source),i=getSpeedBadge(t.speed,t.source);e.innerHTML=`<div class="time">${t.time}</div><div class="coords">${t.latitude.toFixed(6)},<br>${t.longitude.toFixed(6)}</div><div class="meta">${n}${i}</div>`,a.appendChild(e)}),updatePagination()}function getSourceBadge(t){const e=t.toLowerCase();return e.includes("sensor")?'<span class="badge badge-sensors">Sensors</span>':'<span class="badge badge-gps">GPS</span>'}function getSpeedBadge(t,src){const isSensor=(src||"").toLowerCase().includes("sensor");const s=isSensor?Math.min(t,5.9):t;const kmh=(s*3.6).toFixed(1);if(s<.5)return'<span class="badge badge-stationary">STILL<br>'+kmh+' km/h</span>';if(s<6)return'<span class="badge badge-slow">SLOW<br>'+kmh+' km/h</span>';return'<span class="badge badge-fast">FAST<br>'+kmh+' km/h</span>'}function updatePagination(){const seenT=new Set();const dl=allLocations.filter(t=>{if(seenT.has(t.time))return false;seenT.add(t.time);return true;});const t=Math.ceil(dl.length/itemsPerPage);document.getElementById("page-info").textContent=`Page ${currentPage} of ${t} (${allLocations.length} total)`,document.getElementById("prev-btn").disabled=1===currentPage,document.getElementById("next-btn").disabled=currentPage===t||0===t}function nextPage(){currentPage++,displayPage()}function prevPage(){currentPage--,displayPage()}function loadDate(t){selectedDate=t,document.querySelectorAll(".date-tile").forEach(t=>t.classList.remove("active")),event.target.closest(".date-tile").classList.add("active"),loadLocations(t)}function loadToday(){const t=(new Date).toISOString().split("T")[0];selectedDate=t,loadLocations(t)}function loadDateFromInput(){const t=document.getElementById("date-input").value;t&&(selectedDate=t,loadLocations(t))}function updateLastUpdate(){const t=(new Date).toLocaleTimeString();document.getElementById("last-update").textContent=t}async function loadTrips(){const t=await fetch("/api/trips"),e=await t.json(),n=document.getElementById("trip-list");n.innerHTML="",e.forEach(t=>{const e=document.createElement("div");e.className="trip-card",e.onclick=()=>viewTripDetails(t.id);const a=fmtDateTime(t.startTime),i="active"===t.status?"status-active":"status-stopped",s="active"===t.status?"Active":"Completed",o=t.distance<1e3?`${t.distance.toFixed(0)} m`:`${(t.distance/1e3).toFixed(2)} km`,d=`${Math.floor(t.duration/60)} min`;e.innerHTML=`<div class="trip-header"><div class="trip-date">${a}</div><span class="trip-status ${i}">${s}</span></div><div class="trip-stats"><div class="trip-stat"><div class="label">Distance</div><div class="value">${o}</div></div><div class="trip-stat"><div class="label">Duration</div><div class="value">${d}</div></div><div class="trip-stat"><div class="label">Points</div><div class="value">${t.pointCount}</div></div></div>`,n.appendChild(e)})}function fmtDate(s){if(!s)return"";const p=s.split("-");return p.length===3?`${p[1]}/${p[2]}/${p[0]}`:s}function fmtDateTime(s){if(!s)return"";const d=new Date(s);const mo=String(d.getMonth()+1).padStart(2,"0");const dy=String(d.getDate()).padStart(2,"0");const yr=d.getFullYear();const hh=String(d.getHours()).padStart(2,"0");const mm=String(d.getMinutes()).padStart(2,"0");return`${mo}/${dy}/${yr} ${hh}:${mm}`}function clearMap(){map.eachLayer(t=>{(t instanceof L.CircleMarker||t instanceof L.Marker||t instanceof L.Polyline)&&map.removeLayer(t)})}function initMap(){if(!map){map=L.map("map");L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",{attribution:"© OpenStreetMap"}).addTo(map)}else{clearMap();setTimeout(()=>map.invalidateSize(),100)}}function dotColor(src,idx,total){if(idx===0)return"#4CAF50";if(idx===total-1)return"#F44336";const s=(src||"").toLowerCase();return s.includes("gps")?"#1976D2":"#43A047"}function haversineM(a,b){const R=6371000,toR=x=>x*Math.PI/180;const dLat=toR(b[0]-a[0]),dLon=toR(b[1]-a[1]);const s=Math.sin(dLat/2)**2+Math.cos(toR(a[0]))*Math.cos(toR(b[0]))*Math.sin(dLon/2)**2;return R*2*Math.atan2(Math.sqrt(s),Math.sqrt(1-s))}function buildRoute(locs,maxGapM=routeGapM){const sorted=[...locs].sort((a,b)=>(a.timestamp||a.time||"").localeCompare(b.timestamp||b.time||""));const segments=[];let seg=[];sorted.forEach((pt,i)=>{const coord=[pt.latitude,pt.longitude];if(i===0){seg.push(coord);return}const prev=seg[seg.length-1];const dist=haversineM(prev,coord);if(dist<=maxGapM){seg.push(coord)}else{if(seg.length>=2)segments.push(seg);seg=[coord]}});if(seg.length>=2)segments.push(seg);return segments}function drawRoute(locs,titleSuffix){if(!locs||!locs.length)return;const sorted=[...locs].sort((a,b)=>(a.timestamp||a.time||"").localeCompare(b.timestamp||b.time||""));const segments=buildRoute(sorted);segments.forEach(seg=>{L.polyline(seg,{color:"#1976D2",weight:3,opacity:.7}).addTo(map)});const bounds=[];sorted.forEach((pt,idx)=>{const c=dotColor(pt.source,idx,sorted.length);const r=idx===0||idx===sorted.length-1?8:4;L.circleMarker([pt.latitude,pt.longitude],{radius:r,color:c,fillColor:c,fillOpacity:.9,weight:2}).addTo(map).bindPopup(`${pt.time||""}<br>${pt.latitude.toFixed(6)}, ${pt.longitude.toFixed(6)}<br>Speed: ${(pt.speed||0).toFixed(1)} m/s<br>${pt.source||""}`);bounds.push([pt.latitude,pt.longitude])});if(bounds.length)map.fitBounds(bounds,{padding:[40,40]})}async function viewTripDetails(t){const e=await fetch(`/api/trip/${t}/locations`),n=await e.json();document.getElementById("map-modal").classList.add("show");document.getElementById("modal-title").textContent="Locations - "+fmtDate(n.startTime.split("T")[0]);initMap();drawRoute(n.locations)}function showDateRouteOnMap(){const t=selectedDate;if(!t)return void alert("Please select a date first");if(!allLocations||!allLocations.length)return void alert("No location data for selected date");document.getElementById("map-modal").classList.add("show");document.getElementById("modal-title").textContent="Locations - "+fmtDate(t);initMap();drawRoute(allLocations)}function closeMapModal(){document.getElementById("map-modal").classList.remove("show")}window.onclick=function(t){document.getElementById("map-modal")===t.target&&closeMapModal()},document.getElementById("date-input").value=(new Date).toISOString().split("T")[0];let refreshIntervalSecs=5;function loadSettings(){fetch("/api/settings").then(r=>r.json()).then(s=>{routeGapM=s.routeGapThresholdM||500;const si=s.saveIntervalSecs||300;const mins=Math.floor(si/60);const secs=Math.round(si%60);const el=document.getElementById("save-interval");if(el)el.textContent=secs>0?mins+"m "+secs+"s":mins+" min";const newInterval=Math.max(5,Math.round(si));if(newInterval!==refreshIntervalSecs){refreshIntervalSecs=newInterval;const ri=document.getElementById("auto-refresh-val");if(ri)ri.textContent=newInterval>=60?Math.floor(newInterval/60)+"m "+((newInterval%60)>0?(newInterval%60)+"s":""):newInterval+"s";stopAutoRefresh();startAutoRefresh();}}).catch(()=>{});}function startAutoRefresh(){if(autoRefreshInterval)return;let t=refreshIntervalSecs;autoRefreshInterval=setInterval(()=>{t--;document.getElementById("next-refresh").textContent="(next in "+t+"s)";if(t<=0){loadStatus();loadLocations(selectedDate);loadSettings();t=refreshIntervalSecs;}},1e3);}function stopAutoRefresh(){if(autoRefreshInterval){clearInterval(autoRefreshInterval);autoRefreshInterval=null;}}loadSettings();loadStatus(),loadDates(),loadToday(),startAutoRefresh()</script></body></html>
"""
    }
}
