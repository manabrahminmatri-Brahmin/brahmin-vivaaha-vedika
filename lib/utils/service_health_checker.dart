import 'dart:async';
import '../features/auth/auth_controller.dart';
import '../services/presence_service.dart';
import '../services/notification_service.dart';
import 'app_error_handler.dart';

/// Service health checker for comprehensive app functionality monitoring
class ServiceHealthChecker {
  static Future<Map<String, bool>> checkAllServices() async {
    final results = <String, bool>{};
    
    // Check AuthController
    try {
      final authService = AuthController();
      results['auth_service'] = authService.currentUser != null;
      AppErrorHandler.logInfo('ServiceHealth', 'AuthController checked: ${results['auth_service']}');
    } catch (e) {
      results['auth_service'] = false;
      AppErrorHandler.logError('ServiceHealth', 'AuthController check failed: $e');
    }
    
    // Check PresenceService
    try {
      PresenceService();
      results['presence_service'] = true; // Basic instantiation check
      AppErrorHandler.logInfo('ServiceHealth', 'PresenceService checked: ${results['presence_service']}');
    } catch (e) {
      results['presence_service'] = false;
      AppErrorHandler.logError('ServiceHealth', 'PresenceService check failed: $e');
    }
    
    // Check NotificationService
    try {
      final notificationService = NotificationService();
      results['notification_service'] = notificationService.notifications.isNotEmpty;
      AppErrorHandler.logInfo('ServiceHealth', 'NotificationService checked: ${results['notification_service']}');
    } catch (e) {
      results['notification_service'] = false;
      AppErrorHandler.logError('ServiceHealth', 'NotificationService check failed: $e');
    }
    
    return results;
  }
  
  static Future<Map<String, dynamic>> getDetailedHealthReport() async {
    final basicHealth = await checkAllServices();
    final report = <String, dynamic>{};
    
    // Calculate overall health score
    final workingServices = basicHealth.values.where((healthy) => healthy).length;
    final totalServices = basicHealth.length;
    final healthScore = totalServices > 0 ? (workingServices / totalServices) * 100 : 0;
    
    report['overall_health_score'] = healthScore;
    report['services_status'] = basicHealth;
    report['timestamp'] = DateTime.now().toIso8601String();
    report['issues_found'] = workingServices < totalServices;
    
    // Identify critical issues
    final criticalIssues = <String>[];
    basicHealth.forEach((service, isHealthy) {
      if (!isHealthy) {
        criticalIssues.add(service);
      }
    });
    
    report['critical_issues'] = criticalIssues;
    report['recommendations'] = _generateRecommendations(basicHealth);
    
    AppErrorHandler.logInfo('ServiceHealth', 'Health check completed: $healthScore% healthy');
    
    return report;
  }
  
  static List<String> _generateRecommendations(Map<String, bool> healthStatus) {
    final recommendations = <String>[];
    
    healthStatus.forEach((service, isHealthy) {
      if (!isHealthy) {
        switch (service) {
          case 'auth_service':
            recommendations.add('Restart the app and try logging in again');
            break;
          case 'presence_service':
            recommendations.add('Check internet connection and app permissions');
            break;
          case 'notification_service':
            recommendations.add('Pull to refresh notifications');
            break;
        }
      }
    });
    
    if (recommendations.isEmpty) {
      recommendations.add('All services are functioning correctly');
    }
    
    return recommendations;
  }
  
  static Future<void> runHealthCheckAndReport() async {
    AppErrorHandler.logInfo('ServiceHealth', 'Starting comprehensive service health check...');
    
    final report = await getDetailedHealthReport();
    
    AppErrorHandler.logInfo('ServiceHealth', '=== SERVICE HEALTH REPORT ===');
    AppErrorHandler.logInfo('ServiceHealth', 'Overall Health: ${report['overall_health_score']}%');
    AppErrorHandler.logInfo('ServiceHealth', 'Critical Issues: ${report['critical_issues'].length}');
    AppErrorHandler.logInfo('ServiceHealth', 'Timestamp: ${report['timestamp']}');
    
    if (report['issues_found'] == true) {
      AppErrorHandler.logWarning('ServiceHealth', 'Issues detected - see recommendations');
      for (final recommendation in report['recommendations']) {
        AppErrorHandler.logInfo('ServiceHealth', '- $recommendation');
      }
    } else {
      AppErrorHandler.logSuccess('ServiceHealth', 'All services are healthy');
    }
    
    AppErrorHandler.logInfo('ServiceHealth', '=== END HEALTH REPORT ===');
  }
}
