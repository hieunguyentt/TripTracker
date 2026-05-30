Pod::Spec.new do |s|
  s.name             = 'triptracking'
  s.version          = '2.0.13'
  s.summary      = 'GPS trip tracking library for iOS — auto-trip, geofencing, CarPlay, voice feedback.'
  s.description  = <<-DESC
    TripTracker is a drop-in iOS library for GPS-based trip tracking.
    Features: auto-start/stop trips, geofencing, CarPlay support,
    voice feedback, web monitor, road-snapped route drawing, logging.
    Use as a CocoaPod or Swift Package.
  DESC
  s.homepage         = 'https://github.com/hieunguyentt/TripTracker'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'Hieu Nguyen' => 'hieu.nguyen@sw.innova.com' }
  s.source           = {
    :git => 'https://github.com/hieunguyentt/TripTracker.git',
    :tag => s.version.to_s
  }
  s.platform              = :ios, '14.0'
  s.swift_version         = '5.9'
  s.ios.deployment_target = '14.0'

  s.source_files = 'Sources/triptracking/**/*.swift'

  s.frameworks = 'UIKit', 'CoreLocation', 'CoreMotion', 'MapKit',
                 'AVFoundation', 'UserNotifications', 'Network'

  s.dependency 'SQLCipher', '>= 4.0.0'

  s.weak_frameworks = 'CarPlay'
end
