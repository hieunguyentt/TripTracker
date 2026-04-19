//
//  VoiceFeedbackManager.swift
//  TripTracker
//
//  Announces key trip milestones via AVSpeechSynthesizer:
//    - Trip auto-started
//    - Trip auto-ended (with distance + duration)
//    - Distance milestones (every 1 km)
//    - Geofence enter / exit
//    - Speed alerts (vehicle speed reached / returned to still)
//
//  Toggle on/off via Settings. Persisted in UserDefaults.
//  Works in background with AVAudioSession configured for spoken audio.
//

import Foundation
import AVFoundation

public class VoiceFeedbackManager {

    static let shared = VoiceFeedbackManager()

    private let synthesizer = AVSpeechSynthesizer()
    private let enabledKey = "tt_voiceFeedbackEnabled"

    /// Last announced distance milestone (in km, rounded down).
    private var lastAnnouncedKm: Int = 0

    /// Master toggle. Default: ON for first install.
    public var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: enabledKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: enabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            print("🔊 Voice feedback \(newValue ? "enabled" : "disabled")")
        }
    }

    private init() {
        configureAudioSession()
    }

    // MARK: - Audio Session

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            // .duckOthers lowers music volume while speaking, then restores it
            try session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .mixWithOthers])
            try session.setActive(true)
        } catch {
            print("🔊 Audio session setup failed: \(error)")
        }
    }

    // MARK: - Core speak

    /// Speak a message. Interrupts any current speech.
    public func speak(_ message: String) {
        guard isEnabled else { return }

        // Stop current speech if any
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .word)
        }

        let utterance = AVSpeechUtterance(string: message)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05  // slightly faster
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        // Short pause before speaking so it doesn't clip the first word
        utterance.preUtteranceDelay = 0.1

        synthesizer.speak(utterance)
        print("🔊 Speaking: \(message)")
    }

    // MARK: - Trip Events

    public func announceTripStarted(tripId: Int64) {
        speak("Trip started.")
    }

    public func announceTripEnded(tripId: Int64, distance: Double, duration: Int64) {
        let distText = formatDistance(distance)
        let durText = formatDuration(duration)
        speak("Trip ended. \(distText) in \(durText).")
    }

    /// Call on every location update to check distance milestones.
    /// Triggers voice + push notification + CarPlay alert when a new km is reached.
    public func checkDistanceMilestone(totalDistance: Double) {
        let km = Int(totalDistance / 1000)
        guard km > 0 && km > lastAnnouncedKm else { return }
        lastAnnouncedKm = km

        let message = "\(km) kilometer\(km == 1 ? "" : "s") traveled."

        // Voice announcement
        if isEnabled {
            speak(message)
        }

        // Push notification (shows on phone + CarPlay)
        NotificationManager.shared.notifyDistanceMilestone(km: km, totalDistance: totalDistance)

        // CarPlay-specific alert (NSNotification observed by CarPlayMapManager)
        NotificationCenter.default.post(
            name: .tripDistanceMilestone,
            object: nil,
            userInfo: ["km": km, "distance": totalDistance]
        )
    }

    /// Reset milestone counter (call on trip start).
    public func resetMilestones() {
        lastAnnouncedKm = 0
    }

    // MARK: - Geofence Events

    public func announceGeofenceEntered(zoneName: String) {
        speak("Entered \(zoneName).")
    }

    public func announceGeofenceExited(zoneName: String) {
        speak("Left \(zoneName).")
    }

    // MARK: - Speed Events

    public func announceVehicleSpeedDetected() {
        speak("Vehicle speed detected. Trip recording.")
    }

    public func announceVehicleStopped() {
        speak("Vehicle stopped. Auto stop countdown started.")
    }

    // MARK: - Formatting

    private func formatDistance(_ meters: Double) -> String {
        if meters < 1000 {
            return "\(Int(meters)) meters"
        } else {
            let km = meters / 1000
            if km == Double(Int(km)) {
                return "\(Int(km)) kilometers"
            } else {
                return String(format: "%.1f kilometers", km)
            }
        }
    }

    private func formatDuration(_ seconds: Int64) -> String {
        let hrs  = seconds / 3600
        let mins = (seconds % 3600) / 60
        let secs = seconds % 60

        if hrs > 0 {
            return "\(hrs) hour\(hrs == 1 ? "" : "s") \(mins) minute\(mins == 1 ? "" : "s")"
        } else if mins > 0 {
            return "\(mins) minute\(mins == 1 ? "" : "s")"
        } else {
            return "\(secs) seconds"
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let tripDistanceMilestone = Notification.Name("tt_tripDistanceMilestone")
    static let tripAutoStarted      = Notification.Name("tt_tripAutoStarted")
    static let tripAutoEnded        = Notification.Name("tt_tripAutoEnded")
    static let tripVehicleStopped   = Notification.Name("tt_tripVehicleStopped")
    static let geofenceEntered      = Notification.Name("tt_geofenceEntered")
    static let geofenceExited       = Notification.Name("tt_geofenceExited")
}
