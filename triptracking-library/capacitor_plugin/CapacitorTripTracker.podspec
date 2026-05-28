require 'json'
package = JSON.parse(File.read(File.join(__dir__, 'package.json')))

Pod::Spec.new do |s|
  s.name         = 'CapacitorTripTracker'
  s.version          = '1.0.92'
  s.summary      = 'TripTracking Capacitor Plugin'
  s.license      = 'MIT'
  s.author           = { 'Hieu Nguyen' => 'hieu.nguyen@sw.innova.com' }
  s.homepage     = 'https://github.com/hieunguyentt/TripTracker'
  s.author       = 'CarMD'
  s.source       = { :path => '.' }
  s.source_files = 'triptracking-library/capacitor_plugin/ios/Plugin/**/*.{swift,h,m,c,cc,mm,cpp}'
  s.ios.deployment_target = '14.0'
  s.dependency 'Capacitor'  
  s.dependency 'triptracking', '>= 1.0.0'
  s.swift_version = '5.9'
  s.frameworks = 'UIKit', 'CoreLocation', 'CoreMotion', 'MapKit',
                 'AVFoundation', 'UserNotifications', 'Network'

  s.weak_frameworks = 'CarPlay'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'SWIFT_INCLUDE_PATHS' => '$(inherited) $(PODS_CONFIGURATION_BUILD_DIR)/triptracking',
    'OTHER_LDFLAGS' => '-lsqlite3',
    'OTHER_SWIFT_FLAGS' => '-Xcc -DSQLITE_CORE'
  }
end