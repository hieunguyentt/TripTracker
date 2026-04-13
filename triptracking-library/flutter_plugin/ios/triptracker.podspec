Pod::Spec.new do |s|
  s.name             = 'triptracker'
  s.version          = '1.0.0'
  s.summary          = 'Flutter plugin for TripTracker iOS GPS tracking.'
  s.description      = 'GPS trip tracking with auto-trip, geofencing, voice feedback, CarPlay.'
  s.homepage         = 'https://github.com/hieunguyentt/TripTracker'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = 'CarMD'
  s.source           = { :path => '.' }

  s.source_files     = 'Classes/**/*.swift'
  s.dependency 'Flutter'
  s.platform         = :ios, '14.0'
  s.swift_version    = '5.9'

  s.frameworks       = 'UIKit', 'CoreLocation', 'CoreMotion', 'MapKit',
                        'AVFoundation', 'UserNotifications', 'Network'
  s.libraries        = 'sqlite3'
  s.weak_frameworks  = 'CarPlay'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
end
