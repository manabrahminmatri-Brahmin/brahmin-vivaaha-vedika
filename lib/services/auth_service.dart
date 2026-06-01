// Auth Service - Re-export to new architecture
// This file is deprecated. Use features/auth/auth_controller.dart instead

export '../features/auth/auth_controller.dart';

// Type alias for backwards compatibility with Provider usage
import '../features/auth/auth_controller.dart';
typedef AuthService = AuthController;
