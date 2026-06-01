import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../../legacy/compatibility.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_header.dart';

/// Change MPIN screen
class ChangeMpinScreen extends StatefulWidget {
  const ChangeMpinScreen({super.key});

  @override
  State<ChangeMpinScreen> createState() => _ChangeMpinScreenState();
}

class _ChangeMpinScreenState extends State<ChangeMpinScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentMpinController = TextEditingController();
  final _newMpinController = TextEditingController();
  final _confirmMpinController = TextEditingController();
  
  bool _isLoading = false;

  @override
  void dispose() {
    _currentMpinController.dispose();
    _newMpinController.dispose();
    _confirmMpinController.dispose();
    super.dispose();
  }

  Future<void> _changeMpin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    final authService = context.read<AuthService>();
    
    // Verify current MPIN
    final isValid = await authService.checkMpin(_currentMpinController.text);
    
    if (!isValid) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Current MPIN is incorrect'),
          backgroundColor: AppTheme.kumkumRed,
        ),
      );
      return;
    }

    // Update MPIN - need both old and new MPIN
    final oldMpin = _currentMpinController.text;
    final newMpin = _newMpinController.text;
    final success = await authService.changeMpin(oldMpin, newMpin);
    
    if (!mounted) return;
    setState(() => _isLoading = false);
    
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('MPIN changed successfully!'),
          backgroundColor: AppTheme.sacredGreen,
        ),
      );
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('MPIN change failed. Please verify your old MPIN.'),
          backgroundColor: AppTheme.kumkumRed,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AC.bg(context),
      appBar: AppHeader(
        title: 'Change MPIN',
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppTheme.primaryGold.withAlpha(20),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryGold.withAlpha(30),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.pin,
                        size: 40,
                        color: AppTheme.templeGold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Change Your MPIN',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: AppTheme.primaryOrange,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'MPIN is used for quick login and sensitive operations',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ).animate().fadeIn(),

              const SizedBox(height: 32),

              // Current MPIN
              TextFormField(
                controller: _currentMpinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 4,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Current MPIN',
                  hintText: 'Enter your current 4-digit MPIN',
                  prefixIcon: Icon(Icons.lock_outline),
                  counterText: '',
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your current MPIN';
                  }
                  if (value.length != 4) {
                    return 'MPIN must be 4 digits';
                  }
                  return null;
                },
              ).animate().fadeIn(delay: 100.ms).slideX(begin: -0.1),

              const SizedBox(height: 20),

              // New MPIN
              TextFormField(
                controller: _newMpinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 4,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'New MPIN',
                  hintText: 'Enter new 4-digit MPIN',
                  prefixIcon: Icon(Icons.pin_outlined),
                  counterText: '',
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a new MPIN';
                  }
                  if (value.length != 4) {
                    return 'MPIN must be 4 digits';
                  }
                  if (value == _currentMpinController.text) {
                    return 'New MPIN must be different from current';
                  }
                  // Check for simple patterns
                  if (value == '1234' || value == '0000' || value == '1111') {
                    return 'Please choose a stronger MPIN';
                  }
                  return null;
                },
              ).animate().fadeIn(delay: 200.ms).slideX(begin: -0.1),

              const SizedBox(height: 20),

              // Confirm MPIN
              TextFormField(
                controller: _confirmMpinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 4,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Confirm New MPIN',
                  hintText: 'Re-enter new MPIN',
                  prefixIcon: Icon(Icons.pin_outlined),
                  counterText: '',
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please confirm your new MPIN';
                  }
                  if (value != _newMpinController.text) {
                    return 'MPINs do not match';
                  }
                  return null;
                },
              ).animate().fadeIn(delay: 300.ms).slideX(begin: -0.1),

              SizedBox(height: 16),

              // Tips
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.sacredGreen.withAlpha(15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.sacredGreen.withAlpha(30)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.lightbulb_outline, size: 18, color: AppTheme.sacredGreen),
                        const SizedBox(width: 8),
                        Text(
                          'Security Tips',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                color: AppTheme.sacredGreen,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildTip('Avoid using birth year or phone numbers'),
                    _buildTip('Don\'t use patterns like 1234 or 0000'),
                    _buildTip('Choose a memorable but unique number'),
                    _buildTip('Never share your MPIN with anyone'),
                  ],
                ),
              ).animate().fadeIn(delay: 400.ms),

              const SizedBox(height: 32),

              // Change Button
              Container(
                height: 56,
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AC.border(context),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _changeMpin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isLoading
                      ? SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: AC.card(context),
                            strokeWidth: 2.5,
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check, color: AC.card(context)),
                            SizedBox(width: 8),
                            Text(
                              'Change MPIN',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AC.card(context),
                              ),
                            ),
                          ],
                        ),
                ),
              ).animate().fadeIn(delay: 500.ms).scale(begin: const Offset(0.95, 0.95)),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTip(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_outline, size: 16, color: AC.textMuted(context)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
