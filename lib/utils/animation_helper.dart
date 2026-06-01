import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Utility class for optimizing animations
class AnimationHelper {
  /// Check if animations should be reduced (for performance)
  static bool get reduceAnimations {
    return kIsWeb || 
           defaultTargetPlatform == TargetPlatform.linux ||
           defaultTargetPlatform == TargetPlatform.windows;
  }
  
  /// Get optimized animation duration
  static Duration getDuration(Duration original) {
    if (reduceAnimations) {
      return Duration(milliseconds: (original.inMilliseconds * 0.5).round());
    }
    return original;
  }
  
  /// Get optimized animation delay
  static Duration getDelay(Duration original) {
    if (reduceAnimations) {
      return Duration(milliseconds: (original.inMilliseconds * 0.3).round());
    }
    return original;
  }
  
  /// Check if complex animations should be disabled
  static bool get disableComplexAnimations {
    return kIsWeb && !kDebugMode;
  }
  
  /// Get simplified animation curve for performance
  static Curve getCurve(Curve original) {
    if (reduceAnimations) {
      return Curves.easeOut;
    }
    return original;
  }
}
