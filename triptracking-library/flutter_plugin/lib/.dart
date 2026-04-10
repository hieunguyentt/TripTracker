import 'package:flutter/services.dart';

/// triptracking Flutter Plugin
class triptrackingFlutter {
  static const _channel = MethodChannel('com.carmd.triptracking/flutter');

  /// Example method — replace with your actual feature methods
  static Future<String?> doSomething(String input) async {
    return await _channel.invokeMethod<String>('doSomething', {'input': input});
  }
}
