import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_initializer.dart';
import '../../core/identity_service.dart';
import '../../data/reference_data.dart';
import '../../models/auth_result.dart';
import '../../models/gender.dart';
import '../../models/user.dart' as app_models;
import '../../services/auth_service.dart';
import '../../services/astrology_service.dart';
import '../../services/location_service.dart';
import '../../services/pincode_analytics_service.dart';
import '../../services/pin_code_location_resolver.dart';
import '../../widgets/pin_code_location_autofill.dart';
import '../../services/navigation_service.dart';
import '../../services/profile_document_submission_service.dart';
import '../../theme/app_theme.dart';
import 'package:flutter/services.dart';
import '../../utils/english_text_formatters.dart';
import '../../utils/pin_location_form_sync.dart';
import '../../utils/phone_number_guard.dart';
import '../../widgets/celebration_effects.dart';
import '../../widgets/custom_dropdown.dart';
import '../../widgets/multi_select_chip.dart';
import '../../widgets/profile_photo_picker.dart';

/// Multi-step profile wizard for completing user profile
class ProfileWizardScreen extends StatefulWidget {
  final bool isEditMode;
  final int
  initialStep; // 0: Basic, 1: Birth, 2: Religious, 3: Education, 4: Family, 5: Lifestyle

  const ProfileWizardScreen({
    super.key,
    this.isEditMode = false,
    this.initialStep = 0,
  });

  @override
  State<ProfileWizardScreen> createState() => _ProfileWizardScreenState();
}

class _ProfileWizardScreenState extends State<ProfileWizardScreen> {
  static const String _loginRoute = '/login';

  int _currentStep = 0;
  final int _totalSteps = 6;
  bool _checkingLogoutRouteGuard = true;

  // Form keys for each step
  final _basicFormKey = GlobalKey<FormState>();
  final _birthFormKey = GlobalKey<FormState>();
  final _religiousFormKey = GlobalKey<FormState>();
  final _educationFormKey = GlobalKey<FormState>();
  final _familyFormKey = GlobalKey<FormState>();
  final _lifestyleFormKey = GlobalKey<FormState>();

  // Simple focus nodes for basic auto-advance
  final _firstNameFocus = FocusNode();
  final _lastNameFocus = FocusNode();
  final _relationFocus = FocusNode();

  // Birth details focus nodes
  final _birthDateFocus = FocusNode();
  final _birthTimeFocus = FocusNode();
  final _placeOfBirthFocus = FocusNode();
  final _birthStateFocus = FocusNode();
  final _birthCityFocus = FocusNode();

  // Religious details focus nodes
  final _nakshatraFocus = FocusNode();
  final _padaFocus = FocusNode();
  final _rasiFocus = FocusNode();
  final _gothramFocus = FocusNode();
  final _sectFocus = FocusNode();
  final _subSectFocus = FocusNode();

  // Education focus nodes
  final _educationFocus = FocusNode();
  final _specializationFocus = FocusNode();
  final _universityNameFocus = FocusNode();
  final _educationLocationFocus = FocusNode();
  final _educationCityFocus = FocusNode();
  final _additionalQualificationsFocus = FocusNode();
  final _qualificationNotesFocus = FocusNode();

  // Career focus nodes
  final _companyNameFocus = FocusNode();
  final _businessDescriptionFocus = FocusNode();
  final _jobTitleFocus = FocusNode();
  final _workLocationFocus = FocusNode();
  final _workCityFocus = FocusNode();
  final _annualIncomeFocus = FocusNode();

  // Family focus nodes
  final _fatherNameFocus = FocusNode();
  final _motherNameFocus = FocusNode();
  final _motherSurnameFocus = FocusNode();
  final _familyOriginFocus = FocusNode();
  final _familyOriginCityFocus = FocusNode();
  final _knownReferenceFocus = FocusNode();
  final _knownReference2Focus = FocusNode();
  final _aboutFamilyFocus = FocusNode();
  final _fatherOccupationFocus = FocusNode();
  final _motherOccupationFocus = FocusNode();

  // Lifestyle focus nodes
  final _heightFocus = FocusNode();
  final _weightFocus = FocusNode();
  final _complexionFocus = FocusNode();
  final _bodyTypeFocus = FocusNode();
  final _physicalStatusFocus = FocusNode();
  final _manglikStatusFocus = FocusNode();
  final _dietFocus = FocusNode();
  final _smokingFocus = FocusNode();
  final _drinkingFocus = FocusNode();
  final _maritalStatusFocus = FocusNode();
  final _aboutMeFocus = FocusNode();
  final _hobbiesFocus = FocusNode();

  // Profile Created By
  String? _profileCreatedBy;
  final _profileCreatedByRelationController = TextEditingController();

  // Basic Info Controllers
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  Gender _gender = Gender.male;

  // Auto-advance focus to next field.
  // We do NOT call unfocus() before requestFocus() — doing so closes the
  // keyboard and then reopens it, causing a jarring flicker. Simply calling
  // requestFocus() on the next node moves the cursor smoothly while keeping
  // the keyboard visible and in place.
  void _advanceToNextField(String currentField, {String? specificNextField}) {
    if (specificNextField != null) {
      _getFocusNode(specificNextField)?.requestFocus();
    } else {
      switch (_currentStep) {
        case 0:
          _advanceBasicInfoFocus(currentField);
          break;
        case 1:
          _advanceBirthDetailsFocus(currentField);
          break;
        case 2:
          _advanceReligiousFocus(currentField);
          break;
        case 3:
          _advanceEducationFocus(currentField);
          break;
        case 4:
          _advanceFamilyFocus(currentField);
          break;
        case 5:
          _advanceLifestyleFocus(currentField);
          break;
      }
    }
  }

  // Helper method to get focus node by name
  FocusNode? _getFocusNode(String fieldName) {
    switch (fieldName) {
      // Basic Info
      case 'first_name':
        return _firstNameFocus;
      case 'last_name':
        return _lastNameFocus;
      case 'relation':
        return _relationFocus;

      // Birth Details
      case 'birthDate':
        return _birthDateFocus;
      case 'birthTime':
        return _birthTimeFocus;
      case 'placeOfBirth':
        return _placeOfBirthFocus;
      case 'birthState':
        return _birthStateFocus;
      case 'birthCity':
        return _birthCityFocus;

      // Religious Details
      case 'nakshatra':
        return _nakshatraFocus;
      case 'pada':
        return _padaFocus;
      case 'rasi':
        return _rasiFocus;
      case 'gothram':
        return _gothramFocus;
      case 'sect':
        return _sectFocus;
      case 'subSect':
        return _subSectFocus;

      // Education
      case 'education':
        return _educationFocus;
      case 'specialization':
        return _specializationFocus;
      case 'university':
        return _universityNameFocus;
      case 'educationLocation':
        return _educationLocationFocus;
      case 'educationCity':
        return _educationCityFocus;
      case 'additionalQualifications':
        return _additionalQualificationsFocus;
      case 'qualificationNotes':
        return _qualificationNotesFocus;

      // Career
      case 'company':
        return _companyNameFocus;
      case 'jobTitle':
        return _jobTitleFocus;
      case 'workLocation':
        return _workLocationFocus;
      case 'workCity':
        return _workCityFocus;
      case 'annualIncome':
        return _annualIncomeFocus;

      // Family
      case 'fatherName':
        return _fatherNameFocus;
      case 'motherName':
        return _motherNameFocus;
      case 'motherSurname':
        return _motherSurnameFocus;
      case 'familyOrigin':
        return _familyOriginFocus;
      case 'familyOriginCity':
        return _familyOriginCityFocus;
      case 'knownReference':
        return _knownReferenceFocus;
      case 'knownReference2':
        return _knownReference2Focus;
      case 'aboutFamily':
        return _aboutFamilyFocus;
      case 'fatherOccupation':
        return _fatherOccupationFocus;
      case 'motherOccupation':
        return _motherOccupationFocus;

      // Lifestyle
      case 'height':
        return _heightFocus;
      case 'weight':
        return _weightFocus;
      case 'complexion':
        return _complexionFocus;
      case 'bodyType':
        return _bodyTypeFocus;
      case 'physicalStatus':
        return _physicalStatusFocus;
      case 'manglikStatus':
        return _manglikStatusFocus;
      case 'diet':
        return _dietFocus;
      case 'smoking':
        return _smokingFocus;
      case 'drinking':
        return _drinkingFocus;
      case 'maritalStatus':
        return _maritalStatusFocus;
      case 'about_me':
        return _aboutMeFocus;
      case 'hobbies':
        return _hobbiesFocus;

      default:
        return null;
    }
  }

  bool _profileIdMatchesGender(String profileId, Gender gender) {
    final normalized = profileId.trim().toUpperCase();
    if (normalized.isEmpty) return false;

    return gender == Gender.female
        ? normalized.startsWith('MB') || normalized.startsWith('BVV-F-')
        : normalized.startsWith('MG') || normalized.startsWith('BVV-M-');
  }

  String _profileIdForConfirmedGender(app_models.User user, Gender gender) {
    final currentProfileId = user.profileId.trim();
    if (currentProfileId.isNotEmpty &&
        currentProfileId != user.id &&
        _profileIdMatchesGender(currentProfileId, gender)) {
      return currentProfileId;
    }

    return app_models.User.generateProfileIdForGender(gender);
  }

  // Basic info focus advancement
  void _advanceBasicInfoFocus(String currentField) {
    switch (currentField) {
      case 'relation':
        _firstNameFocus.requestFocus();
        break;
      case 'first_name':
        _lastNameFocus.requestFocus();
        break;
      case 'last_name':
        FocusScope.of(context).unfocus();
        break;
    }
  }

  // Birth details focus advancement
  void _advanceBirthDetailsFocus(String currentField) {
    switch (currentField) {
      case 'birthDate':
        _birthTimeFocus.requestFocus();
        break;
      case 'birthTime':
        _placeOfBirthFocus.requestFocus();
        break;
      case 'placeOfBirth':
        if (_placeOfBirthCountry == 'India') {
          _birthStateFocus.requestFocus();
        } else {
          _birthCityFocus.requestFocus();
        }
        break;
      case 'birthState':
        _birthCityFocus.requestFocus();
        break;
      case 'birthCity':
        _manglikStatusFocus.requestFocus();
        break;
      case 'manglikStatus':
        FocusScope.of(context).unfocus();
        break;
    }
  }

  // Religious details focus advancement
  void _advanceReligiousFocus(String currentField) {
    switch (currentField) {
      case 'nakshatra':
        _padaFocus.requestFocus();
        break;
      case 'pada':
        _rasiFocus.requestFocus();
        break;
      case 'rasi':
        _gothramFocus.requestFocus();
        break;
      case 'gothram':
        _sectFocus.requestFocus();
        break;
      case 'sect':
        _subSectFocus.requestFocus();
        break;
      case 'subSect':
        FocusScope.of(context).unfocus();
        break;
    }
  }

  // Education focus advancement
  void _advanceEducationFocus(String currentField) {
    switch (currentField) {
      case 'education':
        _specializationFocus.requestFocus();
        break;
      case 'specialization':
        _universityNameFocus.requestFocus();
        break;
      case 'university':
        _educationLocationFocus.requestFocus();
        break;
      case 'educationLocation':
        _educationCityFocus.requestFocus();
        break;
      case 'educationCity':
        _additionalQualificationsFocus.requestFocus();
        break;
      case 'additionalQualifications':
        _qualificationNotesFocus.requestFocus();
        break;
      case 'qualificationNotes':
        _companyNameFocus.requestFocus();
        break;
      case 'company':
        _jobTitleFocus.requestFocus();
        break;
      case 'jobTitle':
        _workLocationFocus.requestFocus();
        break;
      case 'workLocation':
        _workCityFocus.requestFocus();
        break;
      case 'workCity':
        _annualIncomeFocus.requestFocus();
        break;
      case 'annualIncome':
        FocusScope.of(context).unfocus();
        break;
    }
  }

  // Family details focus advancement
  void _advanceFamilyFocus(String currentField) {
    switch (currentField) {
      case 'fatherName':
        _fatherOccupationFocus.requestFocus();
        break;
      case 'fatherOccupation':
        _motherNameFocus.requestFocus();
        break;
      case 'motherName':
        _motherOccupationFocus.requestFocus();
        break;
      case 'motherOccupation':
        _familyOriginFocus.requestFocus();
        break;
      case 'familyOrigin':
        if (_familyOriginCountry == 'India') {
          _familyOriginCityFocus.requestFocus();
        } else {
          _knownReferenceFocus.requestFocus();
        }
        break;
      case 'familyOriginCity':
        _knownReferenceFocus.requestFocus();
        break;
      case 'knownReference':
        _knownReference2Focus.requestFocus();
        break;
      case 'knownReference2':
        _aboutFamilyFocus.requestFocus();
        break;
      case 'aboutFamily':
        FocusScope.of(context).unfocus();
        break;
    }
  }

  // Lifestyle focus advancement
  void _advanceLifestyleFocus(String currentField) {
    switch (currentField) {
      case 'height':
        _weightFocus.requestFocus();
        break;
      case 'weight':
        _complexionFocus.requestFocus();
        break;
      case 'complexion':
        _bodyTypeFocus.requestFocus();
        break;
      case 'bodyType':
        _physicalStatusFocus.requestFocus();
        break;
      case 'physicalStatus':
        _manglikStatusFocus.requestFocus();
        break;
      case 'manglikStatus':
        _dietFocus.requestFocus();
        break;
      case 'diet':
        _smokingFocus.requestFocus();
        break;
      case 'smoking':
        _drinkingFocus.requestFocus();
        break;
      case 'drinking':
        _maritalStatusFocus.requestFocus();
        break;
      case 'maritalStatus':
        _aboutMeFocus.requestFocus();
        break;
      case 'about_me':
        _hobbiesFocus.requestFocus();
        break;
      case 'hobbies':
        FocusScope.of(context).unfocus();
        break;
    }
  }

  // Validation method to focus on first missing required field
  void _validateAndFocusOnMissingField() {
    switch (_currentStep) {
      case 0: // Basic Info
        if (_profileCreatedBy == null) {
          _showValidationError('Please select who is creating this profile');
          return;
        }
        if (_profileCreatedBy == 'Other' &&
            _profileCreatedByRelationController.text.trim().isEmpty) {
          _relationFocus.requestFocus();
          _showValidationError('Please specify your relationship');
          return;
        }
        if (_firstNameController.text.trim().isEmpty) {
          _firstNameFocus.requestFocus();
          _showValidationError('Please enter your first name');
          return;
        }
        if (_lastNameController.text.trim().isEmpty) {
          _lastNameFocus.requestFocus();
          _showValidationError('Please enter your last name');
          return;
        }
        break;

      case 1: // Birth Details
        if (_dateOfBirth == DateTime(2000, 1, 1)) {
          _birthDateFocus.requestFocus();
          _showValidationError('Please select your birth date');
          return;
        }
        if (_birthTime == null) {
          _birthTimeFocus.requestFocus();
          _showValidationError('Please select your birth time');
          return;
        }
        if (_placeOfBirthCountry == null) {
          _placeOfBirthFocus.requestFocus();
          _showValidationError('Please select your country of birth');
          return;
        }
        if (_placeOfBirthCountry == 'India' && _placeOfBirthState == null) {
          _birthStateFocus.requestFocus();
          _showValidationError('Please select your state of birth');
          return;
        }
        if (_placeOfBirthController.text.trim().isEmpty) {
          _birthCityFocus.requestFocus();
          _showValidationError('Please enter your city of birth');
          return;
        }
        break;

      case 2: // Religious Details
        if (_sect == null) {
          _sectFocus.requestFocus();
          _showValidationError('Please select your sect');
          return;
        }
        if (_subSect == null) {
          _subSectFocus.requestFocus();
          _showValidationError('Please select your sub-sect');
          return;
        }
        if (_gothram == null) {
          _gothramFocus.requestFocus();
          _showValidationError('Please select your gothram');
          return;
        }
        if (_nakshatra == null) {
          _nakshatraFocus.requestFocus();
          _showValidationError('Please select your nakshatra');
          return;
        }
        if (_pada == null) {
          _padaFocus.requestFocus();
          _showValidationError('Please select your pada');
          return;
        }
        break;

      case 3: // Education & Career
        if (_education == null) {
          _educationFocus.requestFocus();
          _showValidationError('Please select your highest qualification');
          return;
        }
        if (_universityNameController.text.trim().isEmpty) {
          _universityNameFocus.requestFocus();
          _showValidationError('Please enter your university name');
          return;
        }
        if (_occupation == null) {
          _showValidationError('Please select your occupation');
          return;
        }
        if (_occupation == 'Other' &&
            _occupationOtherController.text.trim().isEmpty) {
          _showValidationError('Please specify your occupation');
          return;
        }
        if (_occupation == ReferenceData.ownBusinessOccupation &&
            _businessDescriptionController.text.trim().isEmpty) {
          _businessDescriptionFocus.requestFocus();
          _showValidationError('Please describe your business');
          return;
        }
        break;

      case 4: // Family Details
        if (_fatherNameController.text.trim().isEmpty) {
          _fatherNameFocus.requestFocus();
          _showValidationError('Please enter your father\'s name');
          return;
        }
        if (_motherNameController.text.trim().isEmpty) {
          _motherNameFocus.requestFocus();
          _showValidationError('Please enter your mother\'s name');
          return;
        }
        break;

      case 5: // Lifestyle & Interests
        if (_height == null) {
          _heightFocus.requestFocus();
          _showValidationError('Please select your height');
          return;
        }
        if (_complexion == null) {
          _complexionFocus.requestFocus();
          _showValidationError('Please select your complexion');
          return;
        }
        if (_bodyType == null) {
          _bodyTypeFocus.requestFocus();
          _showValidationError('Please select your body type');
          return;
        }
        if (_physicalStatus == null) {
          _physicalStatusFocus.requestFocus();
          _showValidationError('Please select your physical status');
          return;
        }
        break;
    }
  }

  // Show validation error message
  void _showSnack(SnackBar snackBar, {bool clearExisting = false}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) {
      debugPrint('⚠️ ProfileWizard: missing ScaffoldMessenger, snack skipped');
      return;
    }
    if (clearExisting) {
      messenger.clearSnackBars();
    }
    messenger.showSnackBar(snackBar);
  }

  void _showValidationError(String message) {
    _showSnack(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.kumkumRed,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Called by PhoneNumberGuard / AlphaOnlyGuard when blocked input is detected.
  void _showInputGuardWarning(String message) {
    _showSnack(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: Color(0xFF856404),
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Color(0xFF664D03), fontSize: 13),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFFFFF3CD),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFFFFD700), width: 1.2),
        ),
        duration: const Duration(seconds: 3),
      ),
      clearExisting: true,
    );
  }

  // Birth Details
  DateTime _dateOfBirth = DateTime(2000, 1, 1);
  TimeOfDay? _birthTime;
  String? _timeOfBirth;
  final _placeOfBirthController = TextEditingController();
  bool _isCalculatingNakshatra = false;
  String? _placeOfBirthCountry;
  String? _placeOfBirthState;

  // Physical Details
  String? _height;
  String? _weight;
  String? _complexion;
  String? _bodyType;
  String? _physicalStatus;

  // Religious/Astrological Details
  String? _sect;
  String? _subSect;
  String? _gothram;
  String? _nakshatra;
  String? _pada;
  String? _rasi;
  bool _starConfirmed = false;
  bool _showStarConflict = false;
  String? _manglikStatus; // Kuja Dosha (Manglik Status)

  // Education & Career
  String? _education;
  String? _specialization;
  String? _educationStatus; // Pursuing / Completed
  final _universityNameController = TextEditingController();
  String? _educationLocationCountry;
  String? _educationLocationState;
  final _educationLocationCityController = TextEditingController();
  final _additionalQualificationsController = TextEditingController();
  final _qualificationNotesController = TextEditingController();
  // Controllers for "Others" fields
  final _educationOtherController = TextEditingController();
  final _specializationOtherController = TextEditingController();
  String? _occupation;
  String? _employmentType;
  final _companyNameController = TextEditingController();
  final _businessDescriptionController = TextEditingController();
  final _incomeController = TextEditingController(); // free-text salary entry
  String? _incomeRange;
  // Controller for "Others" occupation field
  final _occupationOtherController = TextEditingController();

  // Family Details
  String? _maritalStatus;
  String? _familyType;
  String? _familyStatus;
  String? _familyValues;
  final _fatherNameController = TextEditingController(); // Father's full name
  String? _fatherOccupation;
  final _fatherNoteController =
      TextEditingController(); // Father's occupation note
  final _motherNameController = TextEditingController(); // Mother's full name
  String? _motherOccupation;
  final _motherNoteController =
      TextEditingController(); // Mother's occupation note
  final _motherSurnameController =
      TextEditingController(); // Mother's maiden surname for reference
  // Family Origin Location
  String? _familyOriginCountry;
  String? _familyOriginState;
  final _familyOriginCityController = TextEditingController();
  final _knownReferenceController =
      TextEditingController(); // Known reference person 1
  final _knownReference2Controller =
      TextEditingController(); // Known reference person 2
  int _brothers = 0;
  int _brothersMarried = 0;
  int _sisters = 0;
  int _sistersMarried = 0;
  final _aboutFamilyController =
      TextEditingController(); // Anything to say about your family

  // Location
  String _country = 'India';
  String? _state;
  final _cityController = TextEditingController();
  final _currentCityFocus = FocusNode();

  // Native Place Location
  String? _nativePlaceCountry;
  String? _nativePlaceState;
  final _nativePlaceCityController = TextEditingController();

  final _birthPinSlot = PinLocationSlot();
  final _educationPinSlot = PinLocationSlot();
  final _residencePinSlot = PinLocationSlot();
  final _familyOriginPinSlot = PinLocationSlot();
  final _nativePlacePinSlot = PinLocationSlot();

  // Lifestyle
  String? _foodHabit;
  String? _smokingHabit;
  String? _drinkingHabit;

  // Interests
  List<String> _selectedHobbies = [];
  List<String> _selectedLanguages = ['Telugu', 'English'];

  // About
  final _aboutMeController = TextEditingController();
  final _partnerPreferencesController = TextEditingController();

  // Partner Preferences (Detailed)
  int? _partnerAgeMin;
  int? _partnerAgeMax;
  String? _partnerHeightMin;
  String? _partnerHeightMax;
  List<String> _selectedPartnerEducation = [];
  List<String> _selectedPartnerOccupation = [];
  String? _partnerIncomeMin;
  List<String> _selectedPartnerMaritalStatus = [];
  List<String> _selectedPartnerLocations = [];
  bool?
  _partnerManglikPreference; // true = accepts manglik, false = doesn't accept, null = no preference

  // Profile Photo
  String? _profilePicturePath;
  bool _isPhotoPrivate = false;

  @override
  void initState() {
    super.initState();
    _redirectLockedSessionAwayFromWizard();
    if (widget.isEditMode) {
      _loadExistingProfile();
    }
    // Set initial step if provided
    if (widget.initialStep > 0 && widget.initialStep < _totalSteps) {
      _currentStep = widget.initialStep;
    }
  }

  Future<void> _redirectLockedSessionAwayFromWizard() async {
    if (widget.isEditMode) {
      _checkingLogoutRouteGuard = false;
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final userId = (prefs.getString('current_user_id') ?? '').trim();
    final mpinDone = prefs.getBool('mpin_setup_complete') ?? false;
    final appLocked = prefs.getBool('app_locked') ?? false;
    final hasLogoutMarker = prefs.getInt('logout_timestamp') != null;

    if (userId.isNotEmpty && mpinDone && (appLocked || hasLogoutMarker)) {
      await prefs.setBool('app_locked', true);
      await prefs.setBool('mpin_verified', false);
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        NavigationService()
            .navigatorKey
            .currentState
            ?.pushNamedAndRemoveUntil(_loginRoute, (_) => false);
      });
      return;
    }

    if (mounted) {
      setState(() => _checkingLogoutRouteGuard = false);
    }
  }

  void _loadExistingProfile() {
    final authService = Provider.of<AuthService>(context, listen: false);
    final profile = authService.currentUser?.profile;

    debugPrint('🔍 PROFILE WIZARD: Loading existing profile in EDIT MODE...');
    debugPrint('🔍 PROFILE WIZARD: Profile exists: ${profile != null}');

    if (profile != null) {
      debugPrint(
        '🔍 PROFILE WIZARD: Profile ID: ${authService.currentUser?.profileId}',
      );
      debugPrint('🔍 PROFILE WIZARD: First name: ${profile.firstName}');
      debugPrint('🔍 PROFILE WIZARD: Last name: ${profile.lastName}');
      debugPrint('🔍 PROFILE WIZARD: Gender: ${profile.gender}');
      debugPrint('🔍 PROFILE WIZARD: Date of birth: ${profile.dateOfBirth}');

      setState(() {
        _profileCreatedBy = profile.profileCreatedBy;
        _profileCreatedByRelationController.text =
            profile.profileCreatedByRelation ?? '';
        _firstNameController.text = profile.firstName;
        _lastNameController.text = profile.lastName;
        final dynamicGender = (profile as dynamic).gender;
        _gender = dynamicGender is Gender ? dynamicGender : Gender.male;
        final dynamicDob = (profile as dynamic).dateOfBirth;
        _dateOfBirth = dynamicDob is DateTime ? dynamicDob : _dateOfBirth;
        _timeOfBirth = profile.timeOfBirth;
        _placeOfBirthController.text = profile.placeOfBirth ?? '';
        _placeOfBirthCountry = profile.placeOfBirthCountry ?? 'India';
        _placeOfBirthState = profile.placeOfBirthState;
        _birthPinSlot.seed(
          country: _placeOfBirthCountry,
          state: _placeOfBirthState,
          city: _placeOfBirthController.text,
        );
        _height = profile.height;
        _weight = profile.weight;
        _complexion = profile.complexion;
        _bodyType = profile.bodyType;
        _physicalStatus = profile.physicalStatus;
        _sect = profile.sect;
        _subSect = profile.subSect;
        _gothram = profile.gothram;
        _nakshatra = profile.nakshatra;
        _pada = profile.pada;
        _rasi = profile.rasi;
        _starConfirmed = profile.starConfirmed ?? true;
        _manglikStatus = profile.manglikStatus;
        // hasHoroscope is not in UI yet, so not loading it
        _education = profile.education;
        // Check if education is not in the standard list, then treat as "Other"
        if (_education != null &&
            !ReferenceData.educationLevels.contains(_education)) {
          _educationOtherController.text = _education!;
          _education = 'Other';
        }
        _specialization = profile.specialization;
        // Check if specialization is not in the standard list for the education, then treat as "Other"
        if (_specialization != null &&
            _education != null &&
            _education != 'Other') {
          final specializations = ReferenceData.specializationsFor(_education!);
          if (!specializations.contains(_specialization)) {
            _specializationOtherController.text = _specialization!;
            _specialization = 'Other';
          }
        }
        _educationStatus = profile.educationStatus;
        _universityNameController.text = profile.universityName ?? '';
        _educationLocationCountry = profile.educationLocationCountry ?? 'India';
        _educationLocationState = profile.educationLocationState;
        _educationLocationCityController.text =
            profile.educationLocationCity ?? '';
        _educationPinSlot.seed(
          country: _educationLocationCountry,
          state: _educationLocationState,
          city: _educationLocationCityController.text,
        );
        _additionalQualificationsController.text =
            profile.additionalQualifications ?? '';
        _qualificationNotesController.text = profile.qualificationNotes ?? '';
        _occupation = profile.occupation;
        // Check if occupation is not in the standard list, then treat as "Other"
        if (_occupation != null &&
            !ReferenceData.occupations.contains(_occupation)) {
          _occupationOtherController.text = _occupation!;
          _occupation = 'Other';
        }
        _employmentType = profile.employmentType;
        _companyNameController.text = profile.companyName ?? '';
        _businessDescriptionController.text =
            profile.businessDescription ?? '';
        _incomeRange = profile.incomeRange;
        // Populate free-text income field — if the stored value is a custom
        // entry (not in the quick-select list) show it in the text field.
        if (_incomeRange != null &&
            !ReferenceData.incomeRanges.contains(_incomeRange)) {
          _incomeController.text = _incomeRange!;
          _incomeRange = null; // clear dropdown so text field is authoritative
        } else {
          _incomeController.clear();
        }
        _maritalStatus = profile.maritalStatus;
        _familyType = profile.familyType;
        _familyStatus = profile.familyStatus;
        _familyValues = profile.familyValues;
        _fatherNameController.text = profile.fatherName ?? '';
        _fatherOccupation = profile.fatherOccupation;
        _fatherNoteController.text = profile.fatherNote ?? '';
        _motherNameController.text = profile.motherName ?? '';
        _motherOccupation = profile.motherOccupation;
        _motherNoteController.text = profile.motherNote ?? '';
        _motherSurnameController.text = profile.motherSurname ?? '';
        // Family Origin - parse from familyOrigin if it contains location info
        // For now, we'll store it as a single string, but we can enhance this later
        _familyOriginCountry = profile.familyOriginCountry ?? 'India';
        _familyOriginState = profile.familyOriginState;
        _familyOriginCityController.text = profile.familyOriginCity ?? '';
        _familyOriginPinSlot.seed(
          country: _familyOriginCountry,
          state: _familyOriginState,
          city: _familyOriginCityController.text,
        );
        _knownReferenceController.text = profile.knownReference ?? '';
        _knownReference2Controller.text = profile.knownReference2 ?? '';
        _brothers = profile.brothers ?? 0;
        _brothersMarried = profile.brothersMarried ?? 0;
        _sisters = profile.sisters ?? 0;
        _sistersMarried = profile.sistersMarried ?? 0;
        _aboutFamilyController.text = profile.aboutFamily ?? '';
        _country = profile.country ?? 'India';
        _state = profile.state;
        _cityController.text = profile.city ?? '';
        _residencePinSlot.seed(
          country: _country,
          state: _state,
          city: _cityController.text,
        );
        _nativePlaceCountry = profile.nativePlaceCountry ?? 'India';
        _nativePlaceState = profile.nativePlaceState;
        _nativePlaceCityController.text = profile.nativePlaceCity ?? '';
        _nativePlacePinSlot.seed(
          country: _nativePlaceCountry,
          state: _nativePlaceState,
          city: _nativePlaceCityController.text,
        );
        _foodHabit = profile.foodHabit;
        _smokingHabit = profile.smokingHabit;
        _drinkingHabit = profile.drinkingHabit;

        // Handle List<String> fields robustly - they might come as arrays or comma-separated strings
        _selectedHobbies = _parseListField(profile.hobbies) ?? [];
        _selectedLanguages =
            _parseListField(profile.languages) ?? ['Telugu', 'English'];
        _aboutMeController.text = profile.aboutMe ?? '';
        // Load both partnerExpectations and partnerPreferences - prefer partnerExpectations
        _partnerPreferencesController.text =
            profile.partnerExpectations ?? profile.partnerPreferences ?? '';
        // Load partner preferences
        _partnerAgeMin = profile.partnerAgeMin;
        _partnerAgeMax = profile.partnerAgeMax;
        _partnerHeightMin = profile.partnerHeightMin;
        _partnerHeightMax = profile.partnerHeightMax;

        // Handle partner preference List<String> fields robustly
        _selectedPartnerEducation =
            _parseListField(profile.partnerEducation) ?? [];
        _selectedPartnerOccupation =
            _parseListField(profile.partnerOccupation) ?? [];
        _partnerIncomeMin = profile.partnerIncomeMin;
        _selectedPartnerMaritalStatus =
            _parseListField(profile.partnerMaritalStatus) ?? [];
        _selectedPartnerLocations =
            _parseListField(profile.partnerLocations) ?? [];
        _partnerManglikPreference = profile.partnerManglikPreference;
        _profilePicturePath = profile.profilePicture;
        _isPhotoPrivate = profile.isPhotoPrivate ?? false;
      });
    }
  }

  /// Extra bottom inset so the last fields clear safe area, keyboard, and step nav.
  EdgeInsets _wizardStepPadding(BuildContext context) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    // Keep bottom inset minimal to avoid visible empty scroll area on short steps.
    return EdgeInsets.only(
      left: 20,
      right: 20,
      top: 20,
      bottom: 12 + safeBottom,
    );
  }

  Widget _safeStepWidget(Widget Function() builder, String stepName) {
    try {
      return builder();
    } catch (e, st) {
      debugPrint('❌ ProfileWizard step [$stepName] crashed: $e\n$st');
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                color: AppTheme.kumkumRed,
                size: 40,
              ),
              const SizedBox(height: 10),
              Text(
                '$stepName failed to render.',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppTheme.kumkumRed,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: () => setState(() {}),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
  }

  /// Parse a string list field robustly (arrays or comma-separated strings).
  List<String>? _parseListField(dynamic field) {
    if (field == null) return null;

    if (field is List) {
      return field.cast<String>();
    }

    if (field is String) {
      // Handle comma-separated string format
      return field
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }

    return null;
  }

  /// Calculate age from date of birth
  int _calculateAge(DateTime dateOfBirth) {
    final now = DateTime.now();
    int years = now.year - dateOfBirth.year;
    if (now.month < dateOfBirth.month ||
        (now.month == dateOfBirth.month && now.day < dateOfBirth.day)) {
      years--;
    }
    return years;
  }

  /// Calculate nakshatra and pada from date, time, and place of birth
  /// Uses Chandra Manam (Lunar Calendar) based calculation via ChandraManamProvider
  /// This calculates nakshatra based on the moon's position using place of birth coordinates
  Future<void> _calculateNakshatra() async {
    if (_birthTime == null) return;
    if (_placeOfBirthController.text.trim().isEmpty ||
        (_placeOfBirthCountry == 'India'
            ? _placeOfBirthState == null
            : _placeOfBirthCountry == null)) {
      if (mounted) {
        _showSnack(
          const SnackBar(
            content: Text(
              'Please enter place of birth first to calculate nakshatra accurately',
            ),
            backgroundColor: AppTheme.kumkumRed,
          ),
        );
      }
      return;
    }

    setState(() => _isCalculatingNakshatra = true);

    try {
      // Combine date and time
      final birthDateTime = DateTime(
        _dateOfBirth.year,
        _dateOfBirth.month,
        _dateOfBirth.day,
        _birthTime!.hour,
        _birthTime!.minute,
      );

      // Get coordinates from place of birth
      final coordinates = LocationService.getCoordinatesFromPlace(
        placeOfBirth: _placeOfBirthController.text.trim(),
        country: _placeOfBirthCountry,
        state: _placeOfBirthState,
      );

      // Calculate nakshatra using astrology service with coordinates (Chandra Manam - lunar calendar)
      final details = await AstrologyService.calculate(
        birthDateTime,
        latitude: coordinates['latitude'],
        longitude: coordinates['longitude'],
      );

      if (!mounted) return;
      setState(() {
        _nakshatra = details.nakshatra;
        _pada = details.pada;
        _rasi = _getRasiFromNakshatra(details.nakshatra);
        _starConfirmed = false; // User needs to confirm
        _showStarConflict = false;
        _isCalculatingNakshatra = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isCalculatingNakshatra = false);
      if (mounted) {
        _showSnack(
          SnackBar(
            content: Text('Could not calculate nakshatra: $e'),
            backgroundColor: AppTheme.kumkumRed,
          ),
        );
      }
    }
  }

  /// Get rasi from nakshatra
  String? _getRasiFromNakshatra(String nakshatra) {
    // Nakshatra to Rasi mapping
    const nakshatraToRasi = {
      'Ashwini': 'Mesha (Aries)',
      'Bharani': 'Mesha (Aries)',
      'Krittika': 'Vrishabha (Taurus)',
      'Rohini': 'Vrishabha (Taurus)',
      'Mrigashira': 'Mithuna (Gemini)',
      'Ardra': 'Mithuna (Gemini)',
      'Punarvasu': 'Karka (Cancer)',
      'Pushya': 'Karka (Cancer)',
      'Ashlesha': 'Karka (Cancer)',
      'Magha': 'Simha (Leo)',
      'Purva Phalguni': 'Simha (Leo)',
      'Uttara Phalguni': 'Kanya (Virgo)',
      'Hasta': 'Kanya (Virgo)',
      'Chitra': 'Tula (Libra)',
      'Swati': 'Tula (Libra)',
      'Vishakha': 'Vrischika (Scorpio)',
      'Anuradha': 'Vrischika (Scorpio)',
      'Jyeshtha': 'Vrischika (Scorpio)',
      'Moola': 'Dhanu (Sagittarius)',
      'Purva Ashadha': 'Dhanu (Sagittarius)',
      'Uttara Ashadha': 'Makara (Capricorn)',
      'Shravana': 'Makara (Capricorn)',
      'Dhanishta': 'Kumbha (Aquarius)',
      'Shatabhisha': 'Kumbha (Aquarius)',
      'Purva Bhadrapada': 'Meena (Pisces)',
      'Uttara Bhadrapada': 'Meena (Pisces)',
      'Revati': 'Meena (Pisces)',
    };

    // Try to match nakshatra (handle both with and without Telugu text)
    final simpleName = nakshatra.split(' (').first;
    return nakshatraToRasi[simpleName];
  }

  /// Convert pada number to display format
  String? _padaToDisplay(String? pada) {
    if (pada == null) return null;
    // If already in display format, return as-is
    if (pada.contains('Pada')) return pada;
    // Convert number to display format
    switch (pada) {
      case '1':
        return '1st Pada';
      case '2':
        return '2nd Pada';
      case '3':
        return '3rd Pada';
      case '4':
        return '4th Pada';
      default:
        return pada;
    }
  }

  /// Convert pada display format to number
  String? _padaToNumber(String? pada) {
    if (pada == null) return null;
    // If already a number, return as-is
    if (!pada.contains('Pada')) return pada;
    // Convert display format to number
    if (pada.startsWith('1')) return '1';
    if (pada.startsWith('2')) return '2';
    if (pada.startsWith('3')) return '3';
    if (pada.startsWith('4')) return '4';
    return pada;
  }

  /// Find matching nakshatra in reference data
  String? _findMatchingNakshatra(String? nakshatra) {
    if (nakshatra == null) return null;
    // If exact match exists, return it
    if (ReferenceData.nakshatras.contains(nakshatra)) return nakshatra;
    // Try to find by simple name (without Telugu)
    final simpleName = nakshatra.split(' (').first;
    for (final n in ReferenceData.nakshatras) {
      if (n.startsWith(simpleName)) return n;
    }
    return null;
  }

  /// Show dialog to manually change nakshatra
  Future<void> _showChangeStarDialog() async {
    // Find matching nakshatra in reference data
    String? selectedNakshatra = _findMatchingNakshatra(_nakshatra);
    String? selectedPada = _padaToDisplay(_pada);

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.star, color: AppTheme.templeGold),
              SizedBox(width: 8),
              const Text('Select Birth Star'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'If you know your correct birth star from horoscope, select it below:',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AC.textMuted(context)),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selectedNakshatra,
                  dropdownColor: AC.surface2(context),
                  style: TextStyle(color: AC.text(context), fontSize: 14),
                  onTap: () {
                    // Dismiss keyboard when dropdown is tapped
                    FocusScope.of(context).unfocus();
                  },
                  decoration: InputDecoration(
                    labelText: 'నక్షత్రం (Nakshatra)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.stars, color: AC.textSub(context)),
                  ),
                  items: ReferenceData.nakshatras
                      .map(
                        (n) => DropdownMenuItem(
                          value: n,
                          child: Text(
                            n,
                            style: TextStyle(color: AC.text(context)),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setDialogState(() => selectedNakshatra = value);
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selectedPada,
                  dropdownColor: AC.surface2(context),
                  style: TextStyle(color: AC.text(context), fontSize: 14),
                  onTap: () {
                    // Dismiss keyboard when dropdown is tapped
                    FocusScope.of(context).unfocus();
                  },
                  decoration: InputDecoration(
                    labelText: 'పాదం (Pada)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(
                      Icons.format_list_numbered,
                      color: AC.textSub(context),
                    ),
                  ),
                  items: ReferenceData.padas
                      .map(
                        (p) => DropdownMenuItem(
                          value: p,
                          child: Text(
                            p,
                            style: TextStyle(color: AC.text(context)),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setDialogState(() => selectedPada = value);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (selectedNakshatra != null) {
                  setState(() {
                    _nakshatra = selectedNakshatra;
                    _pada = _padaToNumber(selectedPada);
                    _rasi = _getRasiFromNakshatra(selectedNakshatra!);
                    _starConfirmed = true;
                  });
                  Navigator.pop(context);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryOrange,
              ),
              child: const Text('Save & Confirm'),
            ),
          ],
        ),
      ),
    );
  }

  /// Show time picker and calculate nakshatra
  Future<void> _selectBirthTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _birthTime ?? const TimeOfDay(hour: 6, minute: 0),
      builder: (context, child) {
        final base = Theme.of(context);
        return Theme(
          data: base.copyWith(
            colorScheme: base.colorScheme.copyWith(
              primary: AppTheme.primaryOrange,
              onPrimary: Colors.white,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );

    if (picked != null) {
      setState(() {
        _birthTime = picked;
        _timeOfBirth = picked.format(context);
      });
      // Auto-calculate nakshatra when time is selected (if place is already entered)
      if (_placeOfBirthController.text.trim().isNotEmpty &&
          (_placeOfBirthCountry == 'India'
              ? _placeOfBirthState != null
              : _placeOfBirthCountry != null)) {
        _calculateNakshatra();
      }
    }
  }

  @override
  void dispose() {
    _profileCreatedByRelationController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _placeOfBirthController.dispose();
    _companyNameController.dispose();
    _businessDescriptionController.dispose();
    _incomeController.dispose();
    _currentCityFocus.dispose();
    _cityController.dispose();
    _universityNameController.dispose();
    _educationLocationCityController.dispose();
    _additionalQualificationsController.dispose();
    _qualificationNotesController.dispose();
    _educationOtherController.dispose();
    _specializationOtherController.dispose();
    _occupationOtherController.dispose();
    _motherSurnameController.dispose();
    _familyOriginCityController.dispose();
    _nativePlaceCityController.dispose();
    _knownReferenceController.dispose();
    _knownReference2Controller.dispose();
    _aboutMeController.dispose();
    _partnerPreferencesController.dispose();
    super.dispose();
  }

  bool get _isOwnBusinessOccupation =>
      _occupation == ReferenceData.ownBusinessOccupation;

  void _onPinLookupError(String message) {
    if (message.trim().isEmpty) return;
    _showValidationError(message);
  }

  void _trackManualLocationEntry() {
    PinCodeAnalyticsService.logManualLocationEntry();
  }

  void _warnUnmatchedPinState(String apiState) {
    _showValidationError(
      'Could not match state "$apiState". Please select state manually.',
    );
  }

  void _applyResidencePin(PinCodeResolvedLocation resolved) {
    _applyPinResolvedToForm(
      resolved: resolved,
      slot: _residencePinSlot,
      applyCountry: (c) => _country = c ?? 'India',
      applyState: (s) => _state = s,
      cityController: _cityController,
      countryGetter: () => _country,
    );
  }

  void _applyBirthPin(PinCodeResolvedLocation resolved) {
    _applyPinResolvedToForm(
      resolved: resolved,
      slot: _birthPinSlot,
      applyCountry: (c) => _placeOfBirthCountry = c,
      applyState: (s) => _placeOfBirthState = s,
      cityController: _placeOfBirthController,
      countryGetter: () => _placeOfBirthCountry,
      onApplied: (r) {
        if (_birthTime != null &&
            _nakshatra == null &&
            r.cityForProfile.isNotEmpty) {
          _calculateNakshatra();
        }
      },
    );
  }

  void _applyEducationLocationPin(PinCodeResolvedLocation resolved) {
    _applyPinResolvedToForm(
      resolved: resolved,
      slot: _educationPinSlot,
      applyCountry: (c) => _educationLocationCountry = c ?? 'India',
      applyState: (s) => _educationLocationState = s,
      cityController: _educationLocationCityController,
      countryGetter: () => _educationLocationCountry,
    );
  }

  void _applyFamilyOriginPin(PinCodeResolvedLocation resolved) {
    _applyPinResolvedToForm(
      resolved: resolved,
      slot: _familyOriginPinSlot,
      applyCountry: (c) => _familyOriginCountry = c ?? 'India',
      applyState: (s) => _familyOriginState = s,
      cityController: _familyOriginCityController,
      countryGetter: () => _familyOriginCountry,
    );
  }

  void _applyNativePlacePin(PinCodeResolvedLocation resolved) {
    _applyPinResolvedToForm(
      resolved: resolved,
      slot: _nativePlacePinSlot,
      applyCountry: (c) => _nativePlaceCountry = c ?? 'India',
      applyState: (s) => _nativePlaceState = s,
      cityController: _nativePlaceCityController,
      countryGetter: () => _nativePlaceCountry,
    );
  }

  void _applyPinResolvedToForm({
    required PinCodeResolvedLocation resolved,
    required PinLocationSlot slot,
    required void Function(String?) applyCountry,
    required void Function(String?) applyState,
    required TextEditingController cityController,
    required String? Function() countryGetter,
    void Function(PinCodeResolvedLocation resolved)? onApplied,
  }) {
    if (!mounted) return;
    setState(() {
      applyPinResolvedToSlot(
        resolved: resolved,
        slot: slot,
        cityController: cityController,
      );
      commitPinSlotToFields(
        slot: slot,
        setCountry: applyCountry,
        setStateValue: applyState,
      );
    });
    onApplied?.call(resolved);
    if (countryGetter() == 'India' && resolved.state == null) {
      _warnUnmatchedPinState(resolved.apiState);
    }
  }

  Widget _buildPinAutofill({
    required void Function(PinCodeResolvedLocation resolved) onApply,
    FocusNode? focusAfterSingleMatch,
    String? sectionTitle,
  }) {
    return PinCodeLocationAutofillSection(
      sectionTitle: sectionTitle,
      onApply: onApply,
      onError: _onPinLookupError,
      onManualLocationEdit: _trackManualLocationEntry,
      focusAfterSingleMatch: focusAfterSingleMatch,
    );
  }

  String? _resolvedOccupationForSave() {
    if (_occupation == 'Other') {
      final t = _occupationOtherController.text.trim();
      return t.isEmpty ? null : t;
    }
    return _occupation;
  }

  Future<void> _nextStep() async {
    // First, validate the form fields and focus on missing required fields
    _validateAndFocusOnMissingField();

    // Then check if form is valid
    bool formValid = false;

    switch (_currentStep) {
      case 0:
        formValid = _basicFormKey.currentState?.validate() ?? false;
        break;
      case 1:
        formValid = _birthFormKey.currentState?.validate() ?? false;
        break;
      case 2:
        formValid = _religiousFormKey.currentState?.validate() ?? false;
        break;
      case 3:
        formValid = _educationFormKey.currentState?.validate() ?? false;
        break;
      case 4:
        formValid = _familyFormKey.currentState?.validate() ?? false;
        break;
      case 5:
        formValid = _lifestyleFormKey.currentState?.validate() ?? false;
        break;
    }

    if (!formValid) {
      // Don't proceed if validation failed
      return;
    }

    if (_currentStep < _totalSteps - 1) {
      // Persist progress before leaving the step (wizard kept data in memory only).
      final result = await _persistWizardProfileToServer(draftPlaceholders: true);
      if (!mounted) return;
      if (!result.success) {
        _showSnack(
          SnackBar(
            content: Text(
              result.message.contains('Permission denied')
                  ? result.message
                  : 'Could not save progress: ${result.message}',
            ),
            backgroundColor: AppTheme.kumkumRed,
            duration: const Duration(seconds: 5),
          ),
        );
        return;
      }
      setState(() {
        _currentStep++;
      });
    } else {
      // Save profile
      _saveProfile();
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
      });
    }
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 0:
        return _safeStepWidget(_buildBasicInfoStep, 'Basic Information');
      case 1:
        return _safeStepWidget(_buildBirthDetailsStep, 'Birth Details');
      case 2:
        return _safeStepWidget(_buildReligiousStep, 'Religious Details');
      case 3:
        return _safeStepWidget(_buildEducationStep, 'Education & Career');
      case 4:
        return _safeStepWidget(_buildFamilyStep, 'Family Details');
      case 5:
      default:
        return _safeStepWidget(_buildLifestyleStep, 'Lifestyle & Interests');
    }
  }

  /// Auto-generate About Me text based on filled profile data
  void _autoGenerateAboutMe() {
    final StringBuffer about = StringBuffer();

    // Name and basic intro
    final name = toTitleCaseLabel(_firstNameController.text.trim());
    final isGroom = _gender == Gender.male;

    if (name.isNotEmpty) {
      about.write('I am $name, ');
    } else {
      about.write('I am ');
    }

    // Education and profession (proper casing for degrees and job titles)
    if (_education != null && _occupation != null) {
      final edu = formatEducationForProse(_education);
      final article = indefiniteArticleBeforePhrase(edu);
      if (_occupation == ReferenceData.ownBusinessOccupation) {
        about.write('$article $edu graduate running my own business');
        final biz = _businessDescriptionController.text.trim();
        if (biz.isNotEmpty) {
          about.write(' ($biz)');
        }
        about.write('. ');
      } else {
        final occLabel = _occupation == 'Other'
            ? toTitleCaseLabel(_occupationOtherController.text.trim())
            : toTitleCaseLabel(_occupation!);
        about.write('$article $edu graduate working as $occLabel');
        final company = toTitleCaseLabel(_companyNameController.text.trim());
        if (company.isNotEmpty) {
          about.write(' at $company');
        }
        about.write('. ');
      }
    } else if (_education != null) {
      final edu = formatEducationForProse(_education);
      final article = indefiniteArticleBeforePhrase(edu);
      about.write('$article $edu graduate. ');
    } else if (_occupation != null) {
      if (_occupation == ReferenceData.ownBusinessOccupation) {
        about.write('I run my own business. ');
      } else if (_occupation == 'Other') {
        about.write(
          'I work as ${toTitleCaseLabel(_occupationOtherController.text.trim())}. ',
        );
      } else {
        about.write('I work as ${toTitleCaseLabel(_occupation!)}. ');
      }
    }

    // Location
    if (_cityController.text.trim().isNotEmpty && _state != null) {
      about.write(
        'Currently residing in ${formatCityStateLine(_cityController.text.trim(), _state)}. ',
      );
    } else if (_state != null) {
      about.write('Currently residing in ${toTitleCaseLabel(_state)}. ');
    }

    // Family background
    if (_familyType != null || _familyValues != null) {
      about.write('I come from a ');
      if (_familyValues != null) {
        about.write('${toTitleCaseLabel(_familyValues)} ');
      }
      if (_familyType != null) {
        about.write('${toTitleCaseLabel(_familyType)} family');
      } else {
        about.write('family');
      }

      if (_nativePlaceCityController.text.trim().isNotEmpty) {
        about.write(
          ' from ${formatCityStateLine(_nativePlaceCityController.text.trim(), _nativePlaceState)}',
        );
      }
      about.write('. ');
    }

    // Religious background
    if (_sect != null && _gothram != null) {
      about.write(
        'We belong to the ${toTitleCaseLabel(_sect)} sect with ${toTitleCaseLabel(_gothram)} gothram. ',
      );
    }

    // Hobbies
    if (_selectedHobbies.isNotEmpty) {
      about.write(
        'My hobbies include ${formatCommaSeparatedLabels(_selectedHobbies)}. ',
      );
    }

    // Food habit
    if (_foodHabit != null) {
      final fh = toTitleCaseLabel(_foodHabit);
      final a = indefiniteArticleBeforePhrase(fh);
      about.write('I am $a $fh. ');
    }

    // Closing
    about.write(
      'Looking for a ${isGroom ? 'life partner' : 'suitable match'} who shares similar values and interests.',
    );

    setState(() {
      _aboutMeController.text = about.toString();
    });
  }

  /// Auto-generate Partner Preferences text based on profile
  void _autoGeneratePartnerPreferences() {
    final StringBuffer prefs = StringBuffer();
    final isGroom = _gender == Gender.male;

    prefs.write(
      'Looking for a ${isGroom ? 'well-educated and cultured bride' : 'well-settled and caring groom'} ',
    );

    // Education preference
    if (_education != null) {
      prefs.write('with similar educational background. ');
    } else {
      prefs.write('with good education. ');
    }

    // Family values
    if (_familyValues != null) {
      prefs.write(
        'Should come from a ${toTitleCaseLabel(_familyValues)} family with good values. ',
      );
    } else {
      prefs.write('Should have good family values and upbringing. ');
    }

    // Location preference
    if (_state != null) {
      prefs.write(
        'Preference for someone from ${toTitleCaseLabel(_state)} or nearby states. ',
      );
    }

    // Sect preference
    if (_sect != null) {
      prefs.write(
        'Should belong to the ${toTitleCaseLabel(_sect)} sect or a compatible one. ',
      );
    }

    // Food habit preference
    if (_foodHabit != null) {
      prefs.write('Preferably ${toTitleCaseLabel(_foodHabit)}. ');
    }

    // General closing
    prefs.write(
      '${isGroom ? 'She' : 'He'} should be understanding, caring, and family-oriented.',
    );

    setState(() {
      _partnerPreferencesController.text = prefs.toString();
    });
  }

  /// Builds [UserProfile] from current wizard field state.
  app_models.UserProfile _composeWizardProfile({
    required app_models.UserProfile? existingProfile,
    required bool draftPlaceholders,
  }) {
    final firstNameRaw = _firstNameController.text.trim();
    final lastNameRaw = _lastNameController.text.trim();
    return app_models.UserProfile(
      profileCreatedBy: _profileCreatedBy,
      profileCreatedByRelation: _profileCreatedBy == 'Other'
          ? _profileCreatedByRelationController.text.trim()
          : null,
      firstName: draftPlaceholders && firstNameRaw.isEmpty
          ? 'Draft'
          : firstNameRaw,
      lastName: draftPlaceholders && lastNameRaw.isEmpty
          ? 'Profile'
          : lastNameRaw,
      gender: _gender,
      dateOfBirth: _dateOfBirth,
      timeOfBirth: _timeOfBirth,
      placeOfBirth: _placeOfBirthController.text.trim().isNotEmpty
          ? _placeOfBirthController.text.trim()
          : null,
      placeOfBirthCountry: _placeOfBirthCountry,
      placeOfBirthState: _placeOfBirthState,
      height: _height,
      complexion: _complexion,
      bodyType: _bodyType,
      physicalStatus: _physicalStatus,
      sect: _sect,
      subSect: _subSect,
      gothram: _gothram,
      nakshatra: _nakshatra,
      pada: _pada,
      rasi: _rasi,
      starConfirmed: _starConfirmed,
      manglikStatus: _manglikStatus,
      hasHoroscope: existingProfile?.hasHoroscope, // Preserve existing value
      education: _education == 'Other'
          ? (_educationOtherController.text.trim().isEmpty
                ? null
                : _educationOtherController.text.trim())
          : _education,
      specialization: _specialization == 'Other'
          ? (_specializationOtherController.text.trim().isEmpty
                ? null
                : _specializationOtherController.text.trim())
          : _specialization,
      educationStatus: _educationStatus,
      universityName: _universityNameController.text.trim().isNotEmpty
          ? _universityNameController.text.trim()
          : null,
      educationLocationCountry: _educationLocationCountry,
      educationLocationState: _educationLocationState,
      educationLocationCity:
          _educationLocationCityController.text.trim().isNotEmpty
          ? _educationLocationCityController.text.trim()
          : null,
      additionalQualifications:
          _additionalQualificationsController.text.trim().isNotEmpty
          ? _additionalQualificationsController.text.trim()
          : null,
      qualificationNotes: _qualificationNotesController.text.trim().isNotEmpty
          ? _qualificationNotesController.text.trim()
          : null,
      occupation: _resolvedOccupationForSave(),
      employmentType: _isOwnBusinessOccupation
          ? 'Self Employed / Business'
          : _employmentType,
      companyName: _isOwnBusinessOccupation
          ? null
          : (_companyNameController.text.trim().isNotEmpty
                ? _companyNameController.text.trim()
                : null),
      businessDescription: _isOwnBusinessOccupation
          ? (_businessDescriptionController.text.trim().isNotEmpty
                ? _businessDescriptionController.text.trim()
                : null)
          : null,
      incomeRange: _incomeController.text.trim().isNotEmpty
          ? _incomeController.text.trim()
          : _incomeRange,
      maritalStatus: _maritalStatus,
      familyType: _familyType,
      familyStatus: _familyStatus,
      familyValues: _familyValues,
      fatherName: _fatherNameController.text.trim().isNotEmpty
          ? _fatherNameController.text.trim()
          : null,
      fatherOccupation: _fatherOccupation,
      fatherNote: _fatherNoteController.text.trim().isNotEmpty
          ? _fatherNoteController.text.trim()
          : null,
      motherName: _motherNameController.text.trim().isNotEmpty
          ? _motherNameController.text.trim()
          : null,
      motherOccupation: _motherOccupation,
      motherNote: _motherNoteController.text.trim().isNotEmpty
          ? _motherNoteController.text.trim()
          : null,
      motherSurname: _motherSurnameController.text.trim().isNotEmpty
          ? _motherSurnameController.text.trim()
          : null,
      familyOrigin: null,
      familyOriginCountry: _familyOriginCountry,
      familyOriginState: _familyOriginState,
      familyOriginCity: _familyOriginCityController.text.trim().isNotEmpty
          ? _familyOriginCityController.text.trim()
          : null,
      knownReference: _knownReferenceController.text.trim().isNotEmpty
          ? _knownReferenceController.text.trim()
          : null,
      knownReference2: _knownReference2Controller.text.trim().isNotEmpty
          ? _knownReference2Controller.text.trim()
          : null,
      brothers: _brothers,
      brothersMarried: _brothersMarried,
      sisters: _sisters,
      sistersMarried: _sistersMarried,
      aboutFamily: _aboutFamilyController.text.trim().isNotEmpty
          ? _aboutFamilyController.text.trim()
          : null,
      country: _country,
      state: _state,
      city: _cityController.text.trim().isNotEmpty
          ? _cityController.text.trim()
          : null,
      nativePlace: null,
      nativePlaceCountry: _nativePlaceCountry,
      nativePlaceState: _nativePlaceState,
      nativePlaceCity: _nativePlaceCityController.text.trim().isNotEmpty
          ? _nativePlaceCityController.text.trim()
          : null,
      foodHabit: _foodHabit,
      smokingHabit: _smokingHabit,
      drinkingHabit: _drinkingHabit,
      hobbies: _selectedHobbies,
      interests: existingProfile?.interests, // Preserve existing value
      languages: _selectedLanguages,
      aboutMe: _aboutMeController.text.trim().isNotEmpty
          ? _aboutMeController.text.trim()
          : null,
      partnerPreferences: _partnerPreferencesController.text.trim().isNotEmpty
          ? _partnerPreferencesController.text.trim()
          : null,
      partnerExpectations: _partnerPreferencesController.text.trim().isNotEmpty
          ? _partnerPreferencesController.text.trim()
          : null, // Save to both fields for compatibility
      profilePicture: _profilePicturePath,
      isPhotoPrivate: _isPhotoPrivate,
      photoLastUpdated: _profilePicturePath != null ? DateTime.now() : null,
      // Partner Preferences (Detailed)
      partnerAgeMin: _partnerAgeMin,
      partnerAgeMax: _partnerAgeMax,
      partnerHeightMin: _partnerHeightMin,
      partnerHeightMax: _partnerHeightMax,
      partnerEducation: _selectedPartnerEducation.isNotEmpty
          ? _selectedPartnerEducation
          : null,
      partnerOccupation: _selectedPartnerOccupation.isNotEmpty
          ? _selectedPartnerOccupation
          : null,
      partnerIncomeMin: _partnerIncomeMin,
      partnerMaritalStatus: _selectedPartnerMaritalStatus.isNotEmpty
          ? _selectedPartnerMaritalStatus
          : null,
      partnerLocations: _selectedPartnerLocations.isNotEmpty
          ? _selectedPartnerLocations
          : null,
      partnerManglikPreference: _partnerManglikPreference,
      // Preserve existing values for fields not in UI
      willingToRelocate: existingProfile?.willingToRelocate,
      relocatePreference: existingProfile?.relocatePreference,
      settledAbroad: existingProfile?.settledAbroad,
      citizenship: existingProfile?.citizenship,
      photos: existingProfile?.photos, // Preserve existing photos
    );
  }

  /// Writes wizard state to Firestore; returns failure when the server rejects the write.
  Future<AuthResult> _persistWizardProfileToServer({
    required bool draftPlaceholders,
  }) async {
    final authService = context.read<AuthService>();
    final currentUser = authService.currentUser;
    if (currentUser == null) {
      return AuthResult.failure('No user logged in');
    }
    final profile = _composeWizardProfile(
      existingProfile: currentUser.profile,
      draftPlaceholders: draftPlaceholders,
    );
    return authService.updateUserProfile(
      currentUser.copyWith(profile: profile).toDatabaseJson(),
    );
  }

  /// Save draft profile (allows incomplete profiles)
  Future<void> _saveDraft() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryOrange),
      ),
    );

    final result = await _persistWizardProfileToServer(draftPlaceholders: true);

    if (!mounted) return;
    Navigator.pop(context);

    if (!result.success) {
      _showSnack(
        SnackBar(
          content: Text(
            result.message.contains('Permission denied')
                ? result.message
                : 'Failed to save draft: ${result.message}',
          ),
          backgroundColor: AppTheme.kumkumRed,
          duration: const Duration(seconds: 5),
        ),
      );
      return;
    }

    _showSnack(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: AC.card(context)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Draft saved! You can continue later from your profile.',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: AppTheme.sacredGreen,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );

    NavigationService().invalidateCaches();
    if (widget.isEditMode && mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _saveProfile() async {
    final authService = context.read<AuthService>();

    // Get existing profile to preserve values for fields not in UI
    final existingProfile = authService.currentUser?.profile;

    final profile = _composeWizardProfile(
      existingProfile: existingProfile,
      draftPlaceholders: false,
    );

    final prevCompletionPct = existingProfile?.computedCompletionPercentage ?? 0;
    final reachedFullCompletion =
        profile.computedCompletionPercentage >= 100 && prevCompletionPct < 100;

    final currentUser = authService.currentUser!;
    final confirmedProfileId = _profileIdForConfirmedGender(
      currentUser,
      _gender,
    );
    final result = await authService.updateUserProfile(
      currentUser
          .copyWith(profileId: confirmedProfileId, profile: profile)
          .toDatabaseJson(),
    );

    if (!mounted) return;

    if (result.success) {
      debugPrint('✅ Profile update successful: ${result.message}');

      if (reachedFullCompletion && mounted) {
        await CelebrationEffects.showProfileCompleteCelebration(context);
      }
      if (!mounted) return;

      // For edit mode: save and navigate directly to home (no dialog)
      // For new profile: show success dialog then navigate
      if (widget.isEditMode) {
        // Mark profile as complete so NavigationService routes to /home
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('profile_complete', true);
        NavigationService().invalidateCaches();
        if (!mounted) return;
        Navigator.of(context).pushNamedAndRemoveUntil('/home', (r) => false);
      } else {
        // Show success popup dialog for new profile completion
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.check_circle, color: AppTheme.sacredGreen, size: 32),
                const SizedBox(width: 12),
                Text(
                  'Profile Completed!',
                  style: TextStyle(
                    color: AppTheme.sacredGreen,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Congratulations! Your profile is now complete and live.',
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Other users can now view your profile and connect with you.',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                const Text(
                  'You will now be redirected to the home screen.',
                  style: TextStyle(fontSize: 12, color: Colors.blue),
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.sacredGreen,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Continue to Home'),
              ),
            ],
          ),
        );
      }

      if (mounted) {
        await IdentityService().setProfileId(confirmedProfileId);
        final initResult = await AppInitializer.initialize();
        if (initResult.isError) {
          debugPrint(
            '⚠️ Profile wizard: app identity refresh failed after profile_id generation: '
            '${initResult.message}',
          );
        }
      }

      if (mounted) {
        if (!widget.isEditMode) {
          await _promptOptionalDocumentUpload();
          if (!mounted) return;
        }
        // Mark profile as complete so NavigationService routes to /home
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('profile_complete', true);
        NavigationService().invalidateCaches();
        if (!mounted) return;
        Navigator.of(context).pushNamedAndRemoveUntil('/home', (r) => false);
      }
    } else {
      debugPrint('❌ Profile update failed: ${result.message}');

      // Enhanced error handling with specific messages
      String errorMessage = result.message;

      // Check for common issues and provide specific guidance
      if (errorMessage.toLowerCase().contains('network') ||
          errorMessage.toLowerCase().contains('connection')) {
        errorMessage =
            'Network error. Please check your internet connection and try again.';
      } else if (errorMessage.toLowerCase().contains('permission') ||
          errorMessage.toLowerCase().contains('unauthorized')) {
        errorMessage = 'Permission denied. Please login again and try.';
      } else if (errorMessage.toLowerCase().contains('timeout')) {
        errorMessage = 'Request timed out. Please try again.';
      } else if (errorMessage.toLowerCase().contains('validation') ||
          errorMessage.toLowerCase().contains('invalid')) {
        errorMessage = 'Invalid data. Please check all fields and try again.';
      }

      _showSnack(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_outline, color: AC.card(context), size: 28),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Profile Update Failed',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: AC.card(context),
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      errorMessage,
                      style: TextStyle(fontSize: 12, color: AC.card(context)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          backgroundColor: AppTheme.kumkumRed,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: () {
              // Retry the save operation
              _saveProfile();
            },
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  Future<void> _promptOptionalDocumentUpload() async {
    final uid = context.read<AuthService>().currentUser?.id ?? '';
    if (uid.isEmpty) return;
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        bool uploading = false;
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: const Text('Upload ID Proof (Optional)'),
            content: const Text(
              'You can upload your ID proof now for faster verification, or skip and upload later from My Profile.',
            ),
            actions: [
              TextButton(
                onPressed: uploading ? null : () => Navigator.pop(ctx),
                child: const Text('Skip'),
              ),
              ElevatedButton.icon(
                onPressed: uploading
                    ? null
                    : () async {
                        setLocal(() => uploading = true);
                        final result = await ProfileDocumentSubmissionService()
                            .pickAndSubmitIdProof(uid);
                        if (!mounted) return;
                        if (result.cancelled) {
                          setLocal(() => uploading = false);
                          return;
                        }
                        if (!ctx.mounted || !context.mounted) return;
                        Navigator.pop(ctx);
                        _showSnack(
                          SnackBar(
                            content: Text(
                              result.success
                                  ? 'Document submitted for admin review.'
                                  : (result.errorMessage ??
                                        'Could not upload document.'),
                            ),
                            backgroundColor: result.success
                                ? Colors.green
                                : AppTheme.kumkumRed,
                          ),
                        );
                      },
                icon: uploading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.badge_outlined),
                label: Text(uploading ? 'Uploading...' : 'Upload'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _calculateStar() {
    if (_nakshatra != null && _pada != null) {
      final calculatedRasi = ReferenceData.getRasiForNakshatra(_nakshatra!);
      if (calculatedRasi.isNotEmpty) {
        setState(() {
          _rasi = calculatedRasi;
          _showStarConflict = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingLogoutRouteGuard) {
      return TooltipVisibility(
        visible: false,
        child: Scaffold(backgroundColor: AC.bg(context)),
      );
    }

    return TooltipVisibility(
      visible: false,
      child: Scaffold(
        backgroundColor: AC.bg(context),
        resizeToAvoidBottomInset: true, // Fix keyboard overlap
        appBar: widget.isEditMode
            ? AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                leading: IconButton(
                  icon: Icon(Icons.close, color: AC.textSub(context)),
                  onPressed: () => _showDiscardChangesDialog(context),
                ),
                title: Text(
                  'Edit Profile',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppTheme.primaryOrange,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                centerTitle: true,
                actions: [
                  TextButton.icon(
                    onPressed: _saveAndGoBack,
                    icon: const Icon(Icons.check, color: AppTheme.sacredGreen),
                    label: const Text(
                      'Save',
                      style: TextStyle(
                        color: AppTheme.sacredGreen,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              )
            : null,
        // resizeToAvoidBottomInset: true (set above) shrinks the Scaffold body
        // when the keyboard opens. The Container must NOT have a fixed height —
        // doing so fights the shrink and causes fields to be hidden behind the
        // keyboard. The nav buttons are hidden while the keyboard is open so the
        // full height is available for the scroll content.
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader().animate().fadeIn().slideY(begin: -0.2),
              _buildProgressBar().animate().fadeIn(delay: 200.ms),
              Expanded(child: _buildCurrentStep()),
              if (MediaQuery.viewInsetsOf(context).bottom == 0)
                _buildNavigationButtons().animate().fadeIn(delay: 300.ms),
            ],
          ),
        ),
      ),
    );
  }

  void _showDiscardChangesDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Discard Changes?'),
        content: const Text(
          'You have unsaved changes. Are you sure you want to discard them?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Keep Editing'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.kumkumRed,
            ),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveAndGoBack() async {
    final authService = context.read<AuthService>();

    // Get existing profile to preserve values for fields not in UI
    final existingProfile = authService.currentUser?.profile;

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryOrange),
      ),
    );

    final profile = app_models.UserProfile(
      profileCreatedBy: _profileCreatedBy,
      profileCreatedByRelation: _profileCreatedBy == 'Other'
          ? _profileCreatedByRelationController.text.trim()
          : null,
      firstName: _firstNameController.text.trim(),
      lastName: _lastNameController.text.trim(),
      gender: _gender,
      dateOfBirth: _dateOfBirth,
      timeOfBirth: _timeOfBirth,
      placeOfBirth: _placeOfBirthController.text.trim(),
      placeOfBirthCountry: _placeOfBirthCountry,
      placeOfBirthState: _placeOfBirthState,
      height: _height,
      complexion: _complexion,
      bodyType: _bodyType,
      physicalStatus: _physicalStatus,
      sect: _sect,
      subSect: _subSect,
      gothram: _gothram,
      nakshatra: _nakshatra,
      pada: _pada,
      rasi: _rasi,
      starConfirmed: _starConfirmed,
      manglikStatus: _manglikStatus,
      hasHoroscope: existingProfile?.hasHoroscope, // Preserve existing value
      education: _education,
      specialization: _specialization,
      educationStatus: _educationStatus,
      universityName: _universityNameController.text.trim().isNotEmpty
          ? _universityNameController.text.trim()
          : null,
      educationLocationCountry: _educationLocationCountry,
      educationLocationState: _educationLocationState,
      educationLocationCity:
          _educationLocationCityController.text.trim().isNotEmpty
          ? _educationLocationCityController.text.trim()
          : null,
      additionalQualifications:
          _additionalQualificationsController.text.trim().isNotEmpty
          ? _additionalQualificationsController.text.trim()
          : null,
      qualificationNotes: _qualificationNotesController.text.trim().isNotEmpty
          ? _qualificationNotesController.text.trim()
          : null,
      occupation: _resolvedOccupationForSave(),
      employmentType: _isOwnBusinessOccupation
          ? 'Self Employed / Business'
          : _employmentType,
      companyName: _isOwnBusinessOccupation
          ? null
          : _companyNameController.text.trim().isNotEmpty
          ? _companyNameController.text.trim()
          : null,
      businessDescription: _isOwnBusinessOccupation
          ? (_businessDescriptionController.text.trim().isNotEmpty
                ? _businessDescriptionController.text.trim()
                : null)
          : null,
      incomeRange: _incomeController.text.trim().isNotEmpty
          ? _incomeController.text.trim()
          : _incomeRange,
      maritalStatus: _maritalStatus,
      familyType: _familyType,
      familyStatus: _familyStatus,
      familyValues: _familyValues,
      fatherName: _fatherNameController.text.trim().isNotEmpty
          ? _fatherNameController.text.trim()
          : null,
      fatherOccupation: _fatherOccupation,
      fatherNote: _fatherNoteController.text.trim().isNotEmpty
          ? _fatherNoteController.text.trim()
          : null,
      motherName: _motherNameController.text.trim().isNotEmpty
          ? _motherNameController.text.trim()
          : null,
      motherOccupation: _motherOccupation,
      motherNote: _motherNoteController.text.trim().isNotEmpty
          ? _motherNoteController.text.trim()
          : null,
      motherSurname: _motherSurnameController.text.trim().isNotEmpty
          ? _motherSurnameController.text.trim()
          : null,
      familyOrigin: null, // Deprecated - use location fields
      familyOriginCountry: _familyOriginCountry,
      familyOriginState: _familyOriginState,
      familyOriginCity: _familyOriginCityController.text.trim().isNotEmpty
          ? _familyOriginCityController.text.trim()
          : null,
      knownReference: _knownReferenceController.text.trim().isNotEmpty
          ? _knownReferenceController.text.trim()
          : null,
      knownReference2: _knownReference2Controller.text.trim().isNotEmpty
          ? _knownReference2Controller.text.trim()
          : null,
      brothers: _brothers,
      brothersMarried: _brothersMarried,
      sisters: _sisters,
      sistersMarried: _sistersMarried,
      aboutFamily: _aboutFamilyController.text.trim().isNotEmpty
          ? _aboutFamilyController.text.trim()
          : null,
      country: _country,
      state: _state,
      city: _cityController.text.trim().isNotEmpty
          ? _cityController.text.trim()
          : null,
      nativePlace: null, // Deprecated - use location fields
      nativePlaceCountry: _nativePlaceCountry,
      nativePlaceState: _nativePlaceState,
      nativePlaceCity: _nativePlaceCityController.text.trim().isNotEmpty
          ? _nativePlaceCityController.text.trim()
          : null,
      foodHabit: _foodHabit,
      smokingHabit: _smokingHabit,
      drinkingHabit: _drinkingHabit,
      hobbies: _selectedHobbies,
      interests: existingProfile?.interests, // Preserve existing value
      languages: _selectedLanguages,
      aboutMe: _aboutMeController.text.trim(),
      partnerPreferences: _partnerPreferencesController.text.trim().isNotEmpty
          ? _partnerPreferencesController.text.trim()
          : null,
      partnerExpectations: _partnerPreferencesController.text.trim().isNotEmpty
          ? _partnerPreferencesController.text.trim()
          : null, // Save to both fields for compatibility
      profilePicture: _profilePicturePath,
      isPhotoPrivate: _isPhotoPrivate,
      photoLastUpdated: _profilePicturePath != null ? DateTime.now() : null,
      // Partner Preferences (Detailed)
      partnerAgeMin: _partnerAgeMin,
      partnerAgeMax: _partnerAgeMax,
      partnerHeightMin: _partnerHeightMin,
      partnerHeightMax: _partnerHeightMax,
      partnerEducation: _selectedPartnerEducation.isNotEmpty
          ? _selectedPartnerEducation
          : null,
      partnerOccupation: _selectedPartnerOccupation.isNotEmpty
          ? _selectedPartnerOccupation
          : null,
      partnerIncomeMin: _partnerIncomeMin,
      partnerMaritalStatus: _selectedPartnerMaritalStatus.isNotEmpty
          ? _selectedPartnerMaritalStatus
          : null,
      partnerLocations: _selectedPartnerLocations.isNotEmpty
          ? _selectedPartnerLocations
          : null,
      partnerManglikPreference: _partnerManglikPreference,
      // Preserve existing values for fields not in UI
      willingToRelocate: existingProfile?.willingToRelocate,
      relocatePreference: existingProfile?.relocatePreference,
      settledAbroad: existingProfile?.settledAbroad,
      citizenship: existingProfile?.citizenship,
      photos: existingProfile?.photos, // Preserve existing photos
    );

    final result = await authService.updateUserProfile(
      (authService.currentUser!).copyWith(profile: profile).toDatabaseJson(),
    );

    if (!mounted) return;

    // Close loading dialog
    Navigator.pop(context);

    if (result.success) {
      _showSnack(
        const SnackBar(
          content: Text('Profile updated successfully!'),
          backgroundColor: AppTheme.sacredGreen,
        ),
      );
      // refreshUserData() already runs inside updateUserProfile after write.
      // Go back to profile screen
      if (mounted) Navigator.pop(context);
    } else {
      _showSnack(
        SnackBar(
          content: Text(result.message),
          backgroundColor: AppTheme.kumkumRed,
        ),
      );
    }
  }

  Widget _buildHeader() {
    final safeStepIndex = _currentStep.clamp(0, _totalSteps - 1);
    final stepTitles = [
      'Basic Information',
      'Birth Details',
      'Religious Details',
      'Education & Career',
      'Family Details',
      'Lifestyle & Interests',
    ];

    return Container(
      padding: EdgeInsets.fromLTRB(20, widget.isEditMode ? 8 : 16, 20, 16),
      child: Column(
        children: [
          Row(
            children: [
              if (_currentStep > 0)
                IconButton(
                  onPressed: _previousStep,
                  icon: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: AppTheme.primaryOrange,
                  ),
                )
              else
                const SizedBox(width: 48),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      widget.isEditMode
                          ? 'Section ${safeStepIndex + 1} of $_totalSteps'
                          : 'Step ${safeStepIndex + 1} of $_totalSteps',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppTheme.primaryGold,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      stepTitles[safeStepIndex],
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: AppTheme.primaryOrange,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
              ),
              if (_currentStep < _totalSteps - 1)
                IconButton(
                  onPressed: () {
                    // Allow quick navigation between sections in edit mode
                    if (widget.isEditMode) {
                      setState(() {
                        _currentStep++;
                      });
                    }
                  },
                  icon: Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: widget.isEditMode
                        ? AppTheme.primaryOrange
                        : Colors.transparent,
                  ),
                )
              else
                const SizedBox(width: 48),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    final progress = (_currentStep + 1) / _totalSteps;
    final percentage = (progress * 100).round();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        children: [
          // Progress text
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Step ${_currentStep + 1} of $_totalSteps',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.primaryOrange,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '$percentage% Complete',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.primaryOrange,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: AC.surface(context),
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppTheme.primaryGold,
              ),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationButtons() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AC.card(context),
        boxShadow: [
          BoxShadow(
            color: AC.surface(context),
            blurRadius: 10,
            offset: Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Save Draft button (always visible except on last step)
          if (_currentStep < _totalSteps - 1 && !widget.isEditMode)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _saveDraft,
                icon: Icon(Icons.save_outlined),
                label: const Text('Save Draft & Continue Later'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primaryOrange,
                  side: BorderSide(color: AppTheme.primaryOrange),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          if (_currentStep < _totalSteps - 1 && !widget.isEditMode)
            const SizedBox(height: 12),
          // Navigation buttons
          Row(
            children: [
              if (_currentStep > 0)
                Expanded(
                  child: OutlinedButton(
                    onPressed: _previousStep,
                    child: const Text('Previous'),
                  ),
                ),
              if (_currentStep > 0) const SizedBox(width: 16),
              Expanded(
                flex: _currentStep > 0 ? 2 : 1,
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AC.border(context),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: _nextStep,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _currentStep == _totalSteps - 1
                              ? 'Complete Profile'
                              : 'Continue',
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          _currentStep == _totalSteps - 1
                              ? Icons.check_circle_outline
                              : Icons.arrow_forward_rounded,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ========== STEP 1: BASIC INFO ==========
  Widget _buildBasicInfoStep() {
    return SingleChildScrollView(
      key: const PageStorageKey<String>('profile_wizard_step_basic'),
      padding: _wizardStepPadding(context),
      child: Form(
        key: _basicFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Profile Created By Section
            _buildSectionTitle('Profile Created By', Icons.how_to_reg),
            const SizedBox(height: 16),

            // Profile Created By Dropdown
            CustomDropdown(
              label: 'Who is creating this profile? *',
              hint: 'Select who is registering',
              value: _profileCreatedBy,
              items: ReferenceData.profileCreatedByOptions,
              onChanged: (value) {
                setState(() => _profileCreatedBy = value);
                // Auto-advance to next field
                if (value == 'Other') {
                  _advanceToNextField(
                    'profileCreatedBy',
                    specificNextField: 'relation',
                  );
                } else {
                  _advanceToNextField(
                    'profileCreatedBy',
                    specificNextField: 'first_name',
                  );
                }
              },
              icon: Icons.person_pin_outlined,
            ),
            const SizedBox(height: 16),

            // If "Other" is selected, show relation text field
            if (_profileCreatedBy == 'Other')
              TextFormField(
                inputFormatters: [
                  PhoneNumberGuard(onPhoneDetected: _showInputGuardWarning),
                ],
                controller: _profileCreatedByRelationController,
                focusNode: _relationFocus,
                scrollPadding: const EdgeInsets.only(bottom: 160),
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                onEditingComplete: () => _advanceToNextField('relation'),
                decoration: InputDecoration(
                  labelText: 'Specify Relationship *',
                  hintText: 'Enter your relation with the person',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: AppTheme.primaryOrange,
                      width: 2,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),

            const SizedBox(height: 20),

            // First Name
            TextFormField(
              inputFormatters: [
                PhoneNumberGuard(onPhoneDetected: _showInputGuardWarning),
              ],
              controller: _firstNameController,
              focusNode: _firstNameFocus,
              scrollPadding: const EdgeInsets.only(bottom: 160),
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              onTap: () {
                // Ensure proper focus when tapping
                FocusScope.of(context).requestFocus(_firstNameFocus);
              },
              onEditingComplete: () => _advanceToNextField('first_name'),
              decoration: InputDecoration(
                labelText: 'First Name *',
                hintText: 'Enter your first name',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(
                    color: AppTheme.primaryOrange,
                    width: 2,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Last Name
            TextFormField(
              inputFormatters: [
                PhoneNumberGuard(onPhoneDetected: _showInputGuardWarning),
              ],
              controller: _lastNameController,
              focusNode: _lastNameFocus,
              scrollPadding: const EdgeInsets.only(bottom: 160),
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onEditingComplete: () => _advanceToNextField('last_name'),
              decoration: InputDecoration(
                labelText: 'Last Name *',
                hintText: 'Enter your last name',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(
                    color: AppTheme.primaryOrange,
                    width: 2,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Gender Selection
            _buildSectionTitle('I am a', Icons.people_outline),
            const SizedBox(height: 16),

            // Gender Options — icon-based cards
            LayoutBuilder(
              builder: (context, constraints) {
                final useVerticalLayout = constraints.maxWidth < 340;
                if (useVerticalLayout) {
                  return Column(
                    children: [
                      _buildGenderOption(
                        gender: Gender.male,
                        icon: Icons.man_rounded,
                        label: 'Groom',
                      ),
                      const SizedBox(height: 12),
                      _buildGenderOption(
                        gender: Gender.female,
                        icon: Icons.woman_rounded,
                        label: 'Bride',
                      ),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _buildGenderOption(
                        gender: Gender.male,
                        icon: Icons.man_rounded,
                        label: 'Groom',
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildGenderOption(
                        gender: Gender.female,
                        icon: Icons.woman_rounded,
                        label: 'Bride',
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),

            _buildSectionTitle('Physical Attributes', Icons.accessibility),
            const SizedBox(height: 20),

            // Height
            CustomDropdown(
              label: 'Height *',
              hint: 'Select your height',
              value: _height,
              items: ReferenceData.heights,
              onChanged: (value) {
                setState(() => _height = value);
                _advanceToNextField('height');
              },
              icon: Icons.height,
            ),
            const SizedBox(height: 20),

            // Weight
            CustomDropdown(
              label: 'Weight',
              hint: 'Select your weight (optional)',
              value: _weight,
              items: ReferenceData.weights,
              onChanged: (value) {
                setState(() => _weight = value);
                _advanceToNextField('weight');
              },
              icon: Icons.monitor_weight,
            ),
            CustomDropdown(
              label: 'Complexion *',
              hint: 'Select complexion',
              value: _complexion,
              items: ReferenceData.complexions,
              onChanged: (value) {
                setState(() => _complexion = value);
                _advanceToNextField('complexion');
              },
              icon: Icons.face_outlined,
            ),
            const SizedBox(height: 20),

            // Body Type
            CustomDropdown(
              label: 'Body Type *',
              hint: 'Select body type',
              value: _bodyType,
              items: ReferenceData.bodyTypes,
              onChanged: (value) {
                setState(() => _bodyType = value);
                _advanceToNextField('bodyType');
              },
              icon: Icons.accessibility_new,
            ),
            const SizedBox(height: 20),

            // Physical Status
            CustomDropdown(
              label: 'Physical Status *',
              hint: 'Select physical status',
              value: _physicalStatus,
              items: ReferenceData.physicalStatuses,
              onChanged: (value) {
                setState(() => _physicalStatus = value);
                _advanceToNextField('physicalStatus');
              },
              icon: Icons.health_and_safety_outlined,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGenderOption({
    required Gender gender,
    required IconData icon,
    required String label,
  }) {
    final isSelected = _gender == gender;
    final isMale = gender == Gender.male;
    final accentColor = isMale ? AppTheme.peacockBlue : AppTheme.kumkumRed;

    return GestureDetector(
      onTap: () => setState(() => _gender = gender),
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        decoration: BoxDecoration(
          color: isSelected ? accentColor.withAlpha(18) : AC.card(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? accentColor : AC.border(context),
            width: isSelected ? 2.5 : 1.2,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: accentColor.withAlpha(30),
                    blurRadius: 14,
                    offset: Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon with circular background
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected
                    ? accentColor.withAlpha(25)
                    : AC.surface2(context),
              ),
              child: Icon(
                icon,
                size: 40,
                color: isSelected ? accentColor : AC.textMuted(context),
              ),
            ),
            SizedBox(height: 10),
            // Role label (Groom / Bride)
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? accentColor : AC.textSub(context),
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 1),
            // Telugu subtitle
            Text(
              isMale ? 'వరుడు (Varudu)' : 'వధువు (Vadhuvu)',
              style: TextStyle(
                fontSize: 10,
                color: isSelected
                    ? accentColor.withAlpha(180)
                    : AppTheme.textLight,
              ),
            ),
            const SizedBox(height: 6),
            // Selection dot indicator
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? accentColor : Colors.transparent,
                border: Border.all(
                  color: isSelected ? accentColor : AC.border(context),
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Icon(Icons.check, size: 14, color: AC.card(context))
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  // ========== STEP 2: BIRTH DETAILS ==========
  Widget _buildBirthDetailsStep() {
    return SingleChildScrollView(
      key: const PageStorageKey<String>('profile_wizard_step_birth'),
      primary: false,
      // Prevent "infinite/unlimited" feeling when content is shorter than viewport.
      physics: const ClampingScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: _wizardStepPadding(context),
      child: Form(
        key: _birthFormKey,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: AC.traditionalBorder(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle(
                'Date of Birth (Suryamanam)',
                Icons.calendar_today_outlined,
              ),
              const SizedBox(height: 20),

              // Date of Birth Picker
              InkWell(
                onTap: _selectDateOfBirth,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AC.surface(context),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AC.surface(context)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_month, color: AppTheme.primaryOrange),
                      const SizedBox(width: 16),
                      Text(
                        DateFormat('dd MMMM yyyy').format(_dateOfBirth),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(color: AC.text(context)),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        '(Age: ${_calculateAge(_dateOfBirth)})',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AC.textSub(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              _buildSectionTitle('Time of Birth', Icons.access_time_outlined),
              const SizedBox(height: 20),

              // Time of Birth - Time Picker
              InkWell(
                onTap: _selectBirthTime,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AC.surface(context),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _timeOfBirth != null
                          ? AppTheme.primaryOrange.withAlpha(30)
                          : AC.border(context),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        color: _timeOfBirth != null
                            ? AppTheme.primaryOrange
                            : AC.textMuted(context),
                      ),
                      SizedBox(width: 16),
                      Text(
                        _timeOfBirth ?? 'Tap to select birth time',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: _timeOfBirth != null
                                  ? AC.text(context)
                                  : AC.textMuted(context),
                            ),
                      ),
                      const SizedBox(width: 16),
                      Icon(Icons.arrow_drop_down, color: AC.textMuted(context)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              _buildSectionTitle('Place of Birth', Icons.location_on_outlined),
              const SizedBox(height: 20),

              _buildPinAutofill(
                sectionTitle: 'PIN Code — auto-fill birth place',
                onApply: _applyBirthPin,
                focusAfterSingleMatch: _placeOfBirthFocus,
              ),
              const SizedBox(height: 20),

              KeyedSubtree(
                key: ValueKey('birth_loc_${_birthPinSlot.applySerial}'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CustomDropdown(
                      label: 'Country *',
                      hint: 'Select country',
                      value: _birthPinSlot.country ?? _placeOfBirthCountry,
                      items: ReferenceData.countries,
                      onChanged: (value) {
                        setState(() {
                          _birthPinSlot.country = value;
                          _placeOfBirthCountry = value;
                          _birthPinSlot.state = null;
                          _placeOfBirthState = null;
                          _birthPinSlot.city = '';
                          _placeOfBirthController.clear();
                        });
                      },
                      icon: Icons.public,
                    ),
                    const SizedBox(height: 20),
                    if ((_birthPinSlot.country ?? _placeOfBirthCountry) ==
                        'India') ...[
                      CustomDropdown(
                        label: 'State *',
                        hint: 'Select state',
                        value: _birthPinSlot.state ?? _placeOfBirthState,
                        items: ReferenceData.indianStates,
                        onChanged: (value) {
                          setState(() {
                            _birthPinSlot.state = value;
                            _birthPinSlot.clearPinCityScope();
                            _placeOfBirthState = value;
                            _birthPinSlot.city = '';
                            _placeOfBirthController.clear();
                          });
                          if (value != null &&
                              _placeOfBirthController.text.trim().isNotEmpty &&
                              _birthTime != null &&
                              _nakshatra == null) {
                            _calculateNakshatra();
                          }
                        },
                        icon: Icons.map_outlined,
                      ),
                      const SizedBox(height: 20),
                    ],
                    if ((_birthPinSlot.country ?? _placeOfBirthCountry) ==
                            'India' &&
                        (_birthPinSlot.state ?? _placeOfBirthState) != null &&
                        (_birthPinSlot.hasPinScopedCities ||
                            ReferenceData.cities.containsKey(
                              _birthPinSlot.state ?? _placeOfBirthState!,
                            )))
                      CustomDropdown(
                        label: 'City/Town of Birth *',
                        hint: 'Select birth place',
                        value: _birthPinSlot.cityDropdownValue,
                        items: indianCityDropdownItems(
                          _birthPinSlot.state ?? _placeOfBirthState,
                          selectedCity: _birthPinSlot.city,
                          pinScopedOptions: _birthPinSlot.hasPinScopedCities
                              ? _birthPinSlot.pinScopedCityOptions
                              : null,
                        ),
                        onChanged: (value) {
                          setState(() {
                            _birthPinSlot.city = value ?? '';
                            _placeOfBirthState = _birthPinSlot.state;
                            syncLocationCityController(
                              _placeOfBirthController,
                              value ?? '',
                            );
                          });
                          if (value != null &&
                              value.isNotEmpty &&
                              _birthTime != null &&
                              _nakshatra == null) {
                            _calculateNakshatra();
                          }
                        },
                        icon: Icons.location_city,
                      )
                    else if ((_birthPinSlot.country ?? _placeOfBirthCountry) !=
                            null &&
                        (_birthPinSlot.country ?? _placeOfBirthCountry) !=
                            'India' &&
                        ReferenceData.citiesByCountry.containsKey(
                          _birthPinSlot.country ?? _placeOfBirthCountry!,
                        ))
                      CustomDropdown(
                        label: 'City/Town of Birth *',
                        hint: 'Select birth place',
                        value: _birthPinSlot.cityDropdownValue,
                        items: internationalCityDropdownItems(
                          _birthPinSlot.country ?? _placeOfBirthCountry,
                          selectedCity: _birthPinSlot.city,
                        ),
                        onChanged: (value) {
                          setState(() {
                            _birthPinSlot.city = value ?? '';
                            syncLocationCityController(
                              _placeOfBirthController,
                              value ?? '',
                            );
                          });
                          if (value != null &&
                              value.isNotEmpty &&
                              _birthTime != null &&
                              _nakshatra == null) {
                            _calculateNakshatra();
                          }
                        },
                        icon: Icons.location_city,
                      ),
                  ],
                ),
              ),
              if ((_birthPinSlot.country ?? _placeOfBirthCountry) != null &&
                  ((_birthPinSlot.country ?? _placeOfBirthCountry) == 'India'
                      ? (_birthPinSlot.state ?? _placeOfBirthState) == null ||
                          !ReferenceData.cities.containsKey(
                            _birthPinSlot.state ?? _placeOfBirthState!,
                          )
                      : !ReferenceData.citiesByCountry.containsKey(
                          _birthPinSlot.country ?? _placeOfBirthCountry!,
                        )))
                TextFormField(
                  inputFormatters: [
                    PhoneNumberGuard(onPhoneDetected: _showInputGuardWarning),
                  ],
                  controller: _placeOfBirthController,
                  focusNode: _placeOfBirthFocus,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  onEditingComplete: () => _advanceToNextField('placeOfBirth'),
                  decoration: InputDecoration(
                    labelText: 'City/Town of Birth *',
                    hintText: _placeOfBirthCountry == 'India'
                        ? (_placeOfBirthState == null
                              ? 'Select state first'
                              : 'Enter birth place')
                        : 'Enter birth place',
                    prefixIcon: Icon(
                      Icons.location_city,
                      color: Color(0xFF757575),
                    ),
                  ),
                  enabled: _placeOfBirthCountry == 'India'
                      ? _placeOfBirthState != null
                      : true,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter birth place';
                    }
                    return null;
                  },
                  onChanged: (value) {
                    // Auto-calculate nakshatra when place is entered and time is already selected
                    if (value.trim().isNotEmpty &&
                        (_placeOfBirthCountry == 'India'
                            ? _placeOfBirthState != null
                            : true) &&
                        _birthTime != null &&
                        _nakshatra == null) {
                      _calculateNakshatra();
                    }
                  },
                ),

              SizedBox(height: 24),

              // Kuja Dosha (Manglik Status)
              CustomDropdown(
                label: 'Kuja Dosha (Manglik Status)',
                hint: 'Select Kuja Dosha status',
                value: _manglikStatus,
                items: ReferenceData.manglikStatuses,
                onChanged: (value) => setState(() => _manglikStatus = value),
                icon: Icons.auto_awesome,
              ),

              const SizedBox(height: 24),

              // Show calculating indicator
              if (_isCalculatingNakshatra) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryGold.withAlpha(20),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.primaryGold.withAlpha(50),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.templeGold,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Calculating Birth Star...',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.templeGold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Birth Star (Nakshatra) Section - Enhanced and more prominent
              if (_timeOfBirth != null &&
                  _placeOfBirthController.text.trim().isNotEmpty) ...[
                const SizedBox(height: 32),

                // Enhanced header with visual appeal
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.primaryGold.withAlpha(20),
                        AppTheme.primaryOrange.withAlpha(15),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppTheme.primaryGold.withAlpha(60),
                      width: 2,
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryOrange,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.auto_awesome,
                              color: AC.card(context),
                              size: 24,
                            ),
                          ),
                          SizedBox(width: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Your Birth Star (Nakshatra)',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(
                                      color: AC.textSub(context),
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Calculated based on your birth details',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: AC.textSub(context)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                SizedBox(height: 20),

                // Show calculated nakshatra info with enhanced design
                if (_nakshatra != null && !_isCalculatingNakshatra) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: _starConfirmed
                          ? AppTheme.sacredGreen.withAlpha(15)
                          : AppTheme.primaryGold.withAlpha(25),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _starConfirmed
                            ? AppTheme.sacredGreen.withAlpha(80)
                            : AppTheme.primaryGold.withAlpha(60),
                        width: _starConfirmed ? 2 : 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color:
                              (_starConfirmed
                                      ? AppTheme.sacredGreen
                                      : AppTheme.primaryGold)
                                  .withAlpha(20),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color:
                                    (_starConfirmed
                                            ? AppTheme.sacredGreen
                                            : AppTheme.templeGold)
                                        .withAlpha(20),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Icon(
                                _starConfirmed
                                    ? Icons.check_circle
                                    : Icons.auto_awesome,
                                color: _starConfirmed
                                    ? AppTheme.sacredGreen
                                    : AppTheme.templeGold,
                                size: 24,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _starConfirmed
                                  ? 'Birth Star Confirmed ✓'
                                  : 'Calculated Birth Star',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: _starConfirmed
                                        ? AppTheme.sacredGreen
                                        : AppTheme.templeGold,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            if (_starConfirmed)
                              TextButton.icon(
                                onPressed: () =>
                                    setState(() => _starConfirmed = false),
                                icon: Icon(Icons.edit, size: 16),
                                label: const Text(
                                  'Edit',
                                  style: TextStyle(fontSize: 12),
                                ),
                                style: TextButton.styleFrom(
                                  foregroundColor: AppTheme.textMedium,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Enhanced star display with larger text
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: AC.card(context).withAlpha(80),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppTheme.primaryGold.withAlpha(30),
                            ),
                          ),
                          child: Column(
                            children: [
                              Column(
                                children: [
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.star,
                                        color: AC.textSub(context),
                                        size: 32,
                                      ),
                                      SizedBox(height: 8),
                                      Text(
                                        'నక్షత్రం',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: AC.textSub(context),
                                              fontWeight: FontWeight.w500,
                                            ),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        _nakshatra ?? '-',
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                              color: AC.textSub(context),
                                            ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.filter_1,
                                        color: AppTheme.primaryOrange,
                                        size: 32,
                                      ),
                                      SizedBox(height: 8),
                                      Text(
                                        'పాదం',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: AC.textSub(context),
                                              fontWeight: FontWeight.w500,
                                            ),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        _pada ?? '-',
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                              color: AppTheme.primaryOrange,
                                            ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.circle_outlined,
                                        color: AppTheme.kumkumRed,
                                        size: 32,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'రాశి',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: AC.textSub(context),
                                              fontWeight: FontWeight.w500,
                                            ),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        _rasi?.split(' (').first ?? '-',
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                              color: AppTheme.kumkumRed,
                                            ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        if (!_starConfirmed) ...[
                          const SizedBox(height: 20),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AC.surface(context),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AC.surface(context)),
                            ),
                            child: Column(
                              children: [
                                Column(
                                  children: [
                                    SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton.icon(
                                        onPressed: _showChangeStarDialog,
                                        icon: Icon(Icons.edit, size: 18),
                                        label: Text('Change Star'),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: AppTheme.textMedium,
                                          side: BorderSide(
                                            color: AC.textMuted(context),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 12,
                                          ),
                                        ),
                                      ),
                                    ),
                                    SizedBox(height: 12),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        onPressed: () => setState(
                                          () => _starConfirmed = true,
                                        ),
                                        icon: Icon(Icons.check, size: 18),
                                        label: const Text('Confirm Star'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppTheme.sacredGreen,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 12,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.info_outline,
                                      color: AC.textSub(context),
                                      size: 16,
                                    ),
                                    SizedBox(height: 8),
                                    Text(
                                      'Please verify with your horoscope before confirming',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: AC.textSub(context),
                                            fontStyle: FontStyle.italic,
                                          ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ] else if (!_isCalculatingNakshatra) ...[
                  // Enhanced calculate button
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AC.surface(context),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AC.surface(context), width: 2),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.star_outline,
                          color: AppTheme.primaryOrange,
                          size: 48,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Ready to Calculate Your Birth Star',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: AppTheme.primaryOrange,
                                fontWeight: FontWeight.w700,
                              ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Based on your birth date, time, and place',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: AC.textSub(context)),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _calculateNakshatra,
                            icon: const Icon(Icons.auto_awesome, size: 24),
                            label: const Text('Calculate My Birth Star'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryOrange,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              textStyle: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _selectDateOfBirth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth,
      firstDate: DateTime(1950),
      lastDate: DateTime.now().subtract(const Duration(days: 6570)), // 18 years
      builder: (context, child) {
        final base = Theme.of(context);
        return Theme(
          data: base.copyWith(
            colorScheme: base.colorScheme.copyWith(
              primary: AppTheme.primaryOrange,
              onPrimary: Colors.white,
              secondary: AppTheme.primaryGold,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );

    if (picked != null) {
      setState(() {
        _dateOfBirth = picked;
      });
      // Recalculate nakshatra if time is already selected
      if (_birthTime != null) {
        _calculateNakshatra();
      }
    }
  }

  // ========== STEP 3: RELIGIOUS DETAILS ==========
  Widget _buildReligiousStep() {
    return SingleChildScrollView(
      key: const PageStorageKey<String>('profile_wizard_step_religious'),
      primary: false,
      // Prevent "infinite/unlimited" feeling when content is shorter than viewport.
      physics: const ClampingScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: _wizardStepPadding(context),
      child: Form(
        key: _religiousFormKey,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: AC.traditionalBorder(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle('Caste Details', Icons.temple_hindu_outlined),
              const SizedBox(height: 20),

              // Sect
              CustomDropdown(
                label: 'Sect *',
                hint: 'Select your sect',
                value: _sect,
                items: ReferenceData.sects,
                onChanged: (value) {
                  setState(() {
                    _sect = value;
                    _subSect = null;
                  });
                },
                icon: Icons.group_outlined,
              ),
              const SizedBox(height: 20),

              // Sub-Sect
              CustomDropdown(
                label: 'Sub-Sect *',
                hint: _sect == null ? 'Select sect first' : 'Select sub-sect',
                value: _subSect,
                items: _sect != null
                    ? ReferenceData.subSectsForSect(_sect!)
                    : [],
                onChanged: (value) => setState(() => _subSect = value),
                icon: Icons.groups_outlined,
                enabled: _sect != null,
              ),
              const SizedBox(height: 20),

              // Gothram
              CustomDropdown(
                label: 'Gothram *',
                hint: 'Select your gothram',
                value: _gothram,
                items: ReferenceData.gothrams,
                onChanged: (value) => setState(() => _gothram = value),
                icon: Icons.family_restroom,
              ),
              const SizedBox(height: 28),

              _buildSectionTitle('Nakshatra & Rasi', Icons.star_outline),
              const SizedBox(height: 20),

              // Nakshatra
              CustomDropdown(
                label: 'Birth Star (Nakshatra) *',
                hint: 'Select your nakshatra',
                value: _nakshatra,
                items: ReferenceData.nakshatras,
                onChanged: (value) {
                  setState(() => _nakshatra = value);
                  _calculateStar();
                },
                icon: Icons.star,
              ),
              const SizedBox(height: 20),

              // Pada
              CustomDropdown(
                label: 'Pada *',
                hint: 'Select pada',
                value: _pada,
                items: ReferenceData.padas,
                onChanged: (value) {
                  setState(() => _pada = value);
                  _calculateStar();
                },
                icon: Icons.looks_4_outlined,
              ),
              const SizedBox(height: 20),

              // Rasi (Auto-calculated)
              CustomDropdown(
                label: 'Rasi (Moon Sign) *',
                hint: 'Auto-calculated from Nakshatra',
                value: _rasi,
                items: ReferenceData.rasis,
                onChanged: (value) {
                  setState(() {
                    _rasi = value;
                    _showStarConflict =
                        _rasi !=
                        ReferenceData.getRasiForNakshatra(_nakshatra ?? '');
                  });
                },
                icon: Icons.brightness_3,
              ),

              if (_showStarConflict) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.kumkumRed.withAlpha(15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.kumkumRed.withAlpha(40)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: AppTheme.kumkumRed,
                        size: 20,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Rasi differs from calculated value. Please verify.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.kumkumRed,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // Star Confirmation
              CheckboxListTile(
                value: _starConfirmed,
                onChanged: (value) =>
                    setState(() => _starConfirmed = value ?? false),
                title: const Text('I confirm my birth star is correct'),
                subtitle: const Text(
                  'Check if you have verified from your horoscope',
                ),
                activeColor: AppTheme.primaryOrange,
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ========== STEP 4: EDUCATION & CAREER ==========
  Widget _buildEducationStep() {
    return SingleChildScrollView(
      key: const PageStorageKey<String>('profile_wizard_step_education'),
      primary: false,
      // Prevent "infinite/unlimited" feeling when content is shorter than viewport.
      physics: const ClampingScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: _wizardStepPadding(context),
      child: Form(
        key: _educationFormKey,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: AC.traditionalBorder(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Encouraging Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primaryGold.withAlpha(20),
                      AppTheme.primaryOrange.withAlpha(15),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppTheme.primaryGold.withAlpha(50),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryOrange,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.emoji_events,
                        color: AC.card(context),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Showcase Your Achievements! 🎓',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: AC.textSub(context),
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Share your educational background and career journey',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: AC.text(context)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 28),

              _buildSectionTitle('Education Details', Icons.school_outlined),
              const SizedBox(height: 8),
              Text(
                'Tell us about your educational achievements',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AC.textSub(context),
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 20),

              // Education Level
              CustomDropdown(
                label: 'Highest Qualification *',
                hint: 'Select your highest qualification',
                value: _education,
                items: ReferenceData.educationLevels,
                onChanged: (value) {
                  setState(() {
                    _education = value;
                    _specialization = null;
                  });
                },
                icon: Icons.school,
                customInputController: _educationOtherController,
                customInputLabel: 'Specify Education',
                customInputHint: 'Enter your qualification',
              ),
              if (_education != null) ...[
                SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.sacredGreen.withAlpha(20),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 16,
                        color: AppTheme.sacredGreen,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Great choice! $_education is an excellent qualification.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.sacredGreen,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),

              // Specialization - Show only relevant specializations for selected education
              CustomDropdown(
                label: 'Specialization',
                hint: _education != null
                    ? 'Select your field of specialization (optional)'
                    : 'Select education first',
                value: _specialization,
                items: _education != null
                    ? ReferenceData.specializationsFor(_education!)
                    : ['Select education first'],
                onChanged: _education != null
                    ? (String? value) => setState(() => _specialization = value)
                    : (_) {}, // Empty function when disabled
                enabled: _education != null,
                icon: Icons.psychology,
                customInputController: _specializationOtherController,
                customInputLabel: 'Specify Specialization',
                customInputHint: 'Enter your specialization',
              ),
              const SizedBox(height: 4),
              Text(
                'Optional: Helps find matches with similar interests',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AC.textMuted(context),
                  fontSize: 11,
                ),
              ),
              SizedBox(height: 20),

              // Education Status
              CustomDropdown(
                label: 'Education Status',
                hint: 'Select your current status (optional)',
                value: _educationStatus,
                items: ['Pursuing', 'Completed'],
                onChanged: (value) => setState(() => _educationStatus = value),
                icon: Icons.trending_up,
              ),
              const SizedBox(height: 4),
              Text(
                'Optional: Indicate if you\'re currently studying or have completed',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AC.textMuted(context),
                  fontSize: 11,
                ),
              ),
              SizedBox(height: 20),

              // University/Institution Name
              TextFormField(
                inputFormatters: [
                  PhoneNumberGuard(onPhoneDetected: _showInputGuardWarning),
                ],
                controller: _universityNameController,
                focusNode: _universityNameFocus,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                onEditingComplete: () => _advanceToNextField('universityName'),
                decoration: InputDecoration(
                  labelText: 'University/Institution Name',
                  hintText: 'Enter your alma mater (optional)',
                  prefixIcon: Icon(Icons.school, color: Color(0xFF757575)),
                  helperText: 'Optional: Share where you studied',
                ),
              ),
              const SizedBox(height: 20),

              const SizedBox(height: 24),
              Divider(color: AC.surface(context)),
              SizedBox(height: 24),

              // Education Location Section
              _buildSectionTitle(
                'Where Did You Study?',
                Icons.location_on_outlined,
              ),
              const SizedBox(height: 8),
              Text(
                'Optional: Help others find matches from similar educational backgrounds',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AC.textSub(context),
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 20),

              _buildPinAutofill(
                sectionTitle: 'PIN Code — auto-fill study location',
                onApply: _applyEducationLocationPin,
                focusAfterSingleMatch: _educationLocationFocus,
              ),
              const SizedBox(height: 20),

              KeyedSubtree(
                key: ValueKey('edu_loc_${_educationPinSlot.applySerial}'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CustomDropdown(
                      label: 'Country',
                      hint: 'Select country (optional)',
                      value:
                          _educationPinSlot.country ?? _educationLocationCountry,
                      items: ReferenceData.countries,
                      onChanged: (value) {
                        setState(() {
                          _educationPinSlot.country = value ?? 'India';
                          _educationLocationCountry = _educationPinSlot.country;
                          _educationPinSlot.state = null;
                          _educationLocationState = null;
                          _educationPinSlot.city = '';
                          _educationLocationCityController.clear();
                        });
                      },
                      icon: Icons.public,
                    ),
                    const SizedBox(height: 20),
                    if ((_educationPinSlot.country ??
                            _educationLocationCountry) ==
                        'India')
                      CustomDropdown(
                        label: 'State',
                        hint: 'Select state (optional)',
                        value:
                            _educationPinSlot.state ?? _educationLocationState,
                        items: ReferenceData.indianStates,
                        onChanged: (value) {
                          setState(() {
                            _educationPinSlot.state = value;
                            _educationPinSlot.clearPinCityScope();
                            _educationLocationState = value;
                            _educationPinSlot.city = '';
                            _educationLocationCityController.clear();
                          });
                        },
                        icon: Icons.map_outlined,
                      ),
                    const SizedBox(height: 20),
                    if ((_educationPinSlot.country ??
                                _educationLocationCountry) ==
                            'India' &&
                        (_educationPinSlot.state ??
                                _educationLocationState) !=
                            null &&
                        (_educationPinSlot.hasPinScopedCities ||
                            ReferenceData.cities.containsKey(
                              _educationPinSlot.state ??
                                  _educationLocationState!,
                            )))
                      CustomDropdown(
                        key: ValueKey(
                          'edu_city_${_educationPinSlot.applySerial}',
                        ),
                        label: 'City',
                        hint: 'Select city (optional)',
                        value: _educationPinSlot.cityDropdownValue,
                        items: indianCityDropdownItems(
                          _educationPinSlot.state ?? _educationLocationState,
                          selectedCity: _educationPinSlot.city,
                          pinScopedOptions: _educationPinSlot.hasPinScopedCities
                              ? _educationPinSlot.pinScopedCityOptions
                              : null,
                        ),
                        onChanged: (value) {
                          setState(() {
                            _educationPinSlot.city = value ?? '';
                            syncLocationCityController(
                              _educationLocationCityController,
                              value ?? '',
                            );
                          });
                        },
                        icon: Icons.location_city,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              if ((_educationPinSlot.country ?? _educationLocationCountry) !=
                  'India')
                TextFormField(
                  inputFormatters: [
                    PhoneNumberGuard(onPhoneDetected: _showInputGuardWarning),
                  ],
                  controller: TextEditingController(
                    text: _educationLocationState ?? '',
                  ),
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'State/Province *',
                    hintText: 'Enter state or province',
                    prefixIcon: Icon(Icons.map_outlined),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _educationLocationState = value.trim().isEmpty
                          ? null
                          : value.trim();
                    });
                  },
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter state or province';
                    }
                    return null;
                  },
                ),
              const SizedBox(height: 20),

              if ((_educationPinSlot.country ?? _educationLocationCountry) ==
                      'India' &&
                  (_educationPinSlot.state ?? _educationLocationState) !=
                      null &&
                  !ReferenceData.cities.containsKey(
                    _educationPinSlot.state ?? _educationLocationState!,
                  ))
                TextFormField(
                  inputFormatters: [
                    PhoneNumberGuard(onPhoneDetected: _showInputGuardWarning),
                  ],
                  controller: _educationLocationCityController,
                  focusNode: _educationLocationFocus,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'City',
                    hintText: 'Enter city',
                    prefixIcon: Icon(Icons.location_city),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _educationPinSlot.city = value.trim();
                    });
                  },
                )
              else if ((_educationPinSlot.country ??
                      _educationLocationCountry) !=
                  null)
                TextFormField(
                  inputFormatters: [
                    PhoneNumberGuard(onPhoneDetected: _showInputGuardWarning),
                  ],
                  controller: _educationLocationCityController,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: 'City',
                    hintText: 'Enter city (optional)',
                    prefixIcon: Icon(Icons.location_city),
                  ),
                ),
              const SizedBox(height: 20),

              // Additional Qualifications
              TextFormField(
                inputFormatters: [
                  PhoneNumberGuard(onPhoneDetected: _showInputGuardWarning),
                ],
                controller: _additionalQualificationsController,
                textCapitalization: TextCapitalization.words,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Additional Qualifications',
                  hintText:
                      'Certifications, courses, or other achievements (optional)',
                  prefixIcon: Icon(Icons.workspace_premium),
                  helperText: 'Optional: Showcase your extra qualifications',
                ),
              ),
              const SizedBox(height: 20),

              // Qualification Notes
              TextFormField(
                inputFormatters: [
                  PhoneNumberGuard(onPhoneDetected: _showInputGuardWarning),
                ],
                controller: _qualificationNotesController,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Additional Notes',
                  hintText: 'Any special achievements or honors (optional)',
                  prefixIcon: Icon(Icons.note_outlined),
                  helperText: 'Optional: Share any notable achievements',
                ),
              ),
              const SizedBox(height: 28),
              Divider(color: AC.surface(context)),
              SizedBox(height: 28),

              // Career Section with encouraging header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.textMedium.withAlpha(15),
                      AppTheme.primaryOrange.withAlpha(10),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AC.textSub(context).withAlpha(30),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AC.textSub(context),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.work,
                        color: AC.card(context),
                        size: 24,
                      ),
                    ),
                    SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Your Professional Journey 💼',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AC.textSub(context),
                              ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Share your career details to find compatible matches',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AC.text(context)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(height: 24),

              // Occupation
              CustomDropdown(
                label: 'Occupation *',
                hint: 'Select occupation',
                value: _occupation,
                items: ReferenceData.occupations,
                onChanged: (value) {
                  setState(() {
                    _occupation = value;
                    if (value == ReferenceData.ownBusinessOccupation) {
                      _companyNameController.clear();
                      _employmentType = null;
                    } else {
                      _businessDescriptionController.clear();
                    }
                  });
                },
                icon: Icons.work,
                customInputController: _occupationOtherController,
                customInputLabel: 'Specify Occupation',
                customInputHint: 'Enter your occupation',
              ),
              if (_isOwnBusinessOccupation) ...[
                const SizedBox(height: 16),
                TextFormField(
                  inputFormatters: [
                    PhoneNumberGuard(onPhoneDetected: _showInputGuardWarning),
                  ],
                  controller: _businessDescriptionController,
                  focusNode: _businessDescriptionFocus,
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: 4,
                  minLines: 2,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    labelText: 'Describe your business *',
                    hintText:
                        'e.g. retail store, consulting practice, family firm…',
                    alignLabelWithHint: true,
                    prefixIcon: Icon(
                      Icons.storefront_outlined,
                      color: AC.textSub(context),
                    ),
                    helperText:
                        'Employment type and company fields are hidden for own business',
                  ),
                ),
              ],
              const SizedBox(height: 20),

              if (!_isOwnBusinessOccupation) ...[
                // Employment Type
                CustomDropdown(
                  label: 'Employment Type',
                  hint: 'Select your employment type (optional)',
                  value: _employmentType,
                  items: ReferenceData.employmentTypes,
                  onChanged: (value) => setState(() => _employmentType = value),
                  icon: Icons.business_center_outlined,
                ),
                const SizedBox(height: 4),
                Text(
                  'Optional: Helps others understand your work situation',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AC.textMuted(context),
                    fontSize: 11,
                  ),
                ),
                SizedBox(height: 20),

                // Company Name
                TextFormField(
                  inputFormatters: [
                    PhoneNumberGuard(onPhoneDetected: _showInputGuardWarning),
                  ],
                  controller: _companyNameController,
                  focusNode: _companyNameFocus,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  onEditingComplete: () => _advanceToNextField('companyName'),
                  decoration: InputDecoration(
                    labelText: 'Company/Organization',
                    hintText: 'Where do you work? (optional)',
                    prefixIcon: Icon(Icons.business, color: Color(0xFF757575)),
                    helperText: 'Optional: Share your workplace',
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // ── Annual Income / Salary ────────────────────────────────────
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Free-text entry field
                  TextFormField(
                    controller: _incomeController,
                    focusNode: _annualIncomeFocus,
                    textInputAction: TextInputAction.next,
                    onChanged: (v) {
                      // When user types, clear any quick-select chip selection
                      if (_incomeRange != null) {
                        setState(() => _incomeRange = null);
                      }
                    },
                    onEditingComplete: () =>
                        _advanceToNextField('annualIncome'),
                    decoration: InputDecoration(
                      labelText: 'Annual Income / Salary (optional)',
                      hintText: 'e.g. ₹12 LPA, USD 80,000, ₹50,000/month',
                      prefixIcon: const Icon(
                        Icons.currency_rupee,
                        color: Color(0xFF757575),
                      ),
                      helperText:
                          'Type your exact salary or select a range below',
                      suffixIcon: _incomeController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () => setState(() {
                                _incomeController.clear();
                                _incomeRange = null;
                              }),
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Quick-select suggestion chips (common ranges)
                  Text(
                    'Or pick a range:',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AC.textMuted(context),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      // Show a curated subset for quick picks; full list via dropdown
                      for (final range in [
                        'Not Disclosed',
                        '₹3 – 5 LPA',
                        '₹5 – 8 LPA',
                        '₹8 – 12 LPA',
                        '₹12 – 18 LPA',
                        '₹18 – 25 LPA',
                        '₹25 – 35 LPA',
                        '₹35 – 50 LPA',
                        '₹50 – 75 LPA',
                        '₹75 LPA – 1 Cr',
                        'Above ₹2 Cr',
                        'USD 50,000 – 75,000',
                        'USD 75,000 – 1,00,000',
                        'USD 1,00,000 – 1,50,000',
                        'AED 10,000 – 20,000 / month',
                      ])
                        ChoiceChip(
                          label: Text(
                            range,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: _incomeRange == range
                                  ? Colors.white
                                  : AC.textSub(context),
                            ),
                          ),
                          selected: _incomeRange == range,
                          selectedColor: AppTheme.primaryOrange,
                          backgroundColor: AC.surface(context),
                          side: BorderSide(
                            color: _incomeRange == range
                                ? AppTheme.primaryOrange
                                : AC.border(context),
                          ),
                          onSelected: (selected) => setState(() {
                            _incomeRange = selected ? range : null;
                            // Clear free-text when chip is selected
                            if (selected) _incomeController.clear();
                          }),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 0,
                          ),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ],
              ),
              SizedBox(height: 28),
              Divider(color: AC.surface(context)),
              SizedBox(height: 28),

              // Current Location Section
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.sacredGreen.withAlpha(10),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppTheme.sacredGreen.withAlpha(30),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.sacredGreen,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.location_on,
                        color: AC.card(context),
                        size: 24,
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Where Are You Located? 📍',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.sacredGreen,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Required: Helps find matches in your preferred location',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: AC.text(context)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              _buildPinAutofill(
                sectionTitle: 'PIN Code — auto-fill current location',
                onApply: _applyResidencePin,
                focusAfterSingleMatch: _currentCityFocus,
              ),
              const SizedBox(height: 20),

              KeyedSubtree(
                key: ValueKey('residence_loc_${_residencePinSlot.applySerial}'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CustomDropdown(
                      label: 'Country *',
                      hint: 'Select country',
                      value: _residencePinSlot.country ?? _country,
                      items: ReferenceData.countries,
                      onChanged: (value) {
                        _trackManualLocationEntry();
                        setState(() {
                          _residencePinSlot.country = value ?? 'India';
                          _country = _residencePinSlot.country ?? 'India';
                          _residencePinSlot.clearPinCityScope();
                          _residencePinSlot.state = null;
                          _state = null;
                          _residencePinSlot.city = '';
                          _cityController.clear();
                        });
                      },
                      icon: Icons.public,
                    ),
                    const SizedBox(height: 20),
                    if ((_residencePinSlot.country ?? _country) == 'India')
                      CustomDropdown(
                        label: 'State *',
                        hint: 'Select state',
                        value: _residencePinSlot.state ?? _state,
                        items: ReferenceData.indianStates,
                        onChanged: (value) {
                          _trackManualLocationEntry();
                          setState(() {
                            _residencePinSlot.state = value;
                            _residencePinSlot.clearPinCityScope();
                            _state = value;
                            _residencePinSlot.city = '';
                            _cityController.clear();
                          });
                        },
                        icon: Icons.map_outlined,
                      ),
                    const SizedBox(height: 20),
                    if ((_residencePinSlot.country ?? _country) == 'India' &&
                        (_residencePinSlot.state ?? _state) != null &&
                        (_residencePinSlot.hasPinScopedCities ||
                            ReferenceData.cities.containsKey(
                              _residencePinSlot.state ?? _state!,
                            )))
                      CustomDropdown(
                        key: ValueKey(
                          'residence_city_${_residencePinSlot.applySerial}',
                        ),
                        label: 'City/Town *',
                        hint: 'Select your city or town',
                        value: _residencePinSlot.cityDropdownValue,
                        items: indianCityDropdownItems(
                          _residencePinSlot.state ?? _state,
                          selectedCity: _residencePinSlot.city,
                          pinScopedOptions: _residencePinSlot.hasPinScopedCities
                              ? _residencePinSlot.pinScopedCityOptions
                              : null,
                        ),
                        onChanged: (value) {
                          _trackManualLocationEntry();
                          setState(() {
                            _residencePinSlot.city = value ?? '';
                            syncLocationCityController(
                              _cityController,
                              value ?? '',
                            );
                          });
                        },
                        icon: Icons.location_city,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              if ((_residencePinSlot.country ?? _country) != 'India')
                TextFormField(
                  inputFormatters: [
                    PhoneNumberGuard(onPhoneDetected: _showInputGuardWarning),
                  ],
                  controller: TextEditingController(text: _state ?? ''),
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'State/Province *',
                    hintText: 'Enter state or province',
                    prefixIcon: Icon(Icons.map_outlined),
                  ),
                  onChanged: (value) {
                    _trackManualLocationEntry();
                    setState(() {
                      _state = value.trim().isEmpty ? null : value.trim();
                    });
                  },
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter state or province';
                    }
                    return null;
                  },
                ),
              const SizedBox(height: 20),

              if ((_residencePinSlot.country ?? _country) == 'India' &&
                  (_residencePinSlot.state ?? _state) != null &&
                  !ReferenceData.cities.containsKey(
                    _residencePinSlot.state ?? _state!,
                  ))
                TextFormField(
                  inputFormatters: [
                    PhoneNumberGuard(onPhoneDetected: _showInputGuardWarning),
                  ],
                  controller: _cityController,
                  focusNode: _currentCityFocus,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'City/Town *',
                    hintText: 'Enter city or town',
                    prefixIcon: Icon(Icons.location_city),
                  ),
                  onChanged: (_) => _trackManualLocationEntry(),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter city or town';
                    }
                    return null;
                  },
                )
              else if ((_residencePinSlot.country ?? _country) != null &&
                  (_residencePinSlot.country ?? _country) != 'India')
                // For non-India countries: Show text field
                TextFormField(
                  inputFormatters: [
                    PhoneNumberGuard(onPhoneDetected: _showInputGuardWarning),
                  ],
                  controller: _cityController,
                  focusNode: _currentCityFocus,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'City/Town *',
                    hintText: 'Enter city or town',
                    prefixIcon: Icon(Icons.location_city),
                  ),
                  onChanged: (_) => _trackManualLocationEntry(),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter city or town';
                    }
                    return null;
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ========== STEP 5: FAMILY DETAILS ==========
  Widget _buildFamilyStep() {
    return SingleChildScrollView(
      key: const PageStorageKey<String>('profile_wizard_step_family'),
      primary: false,
      // Prevent "infinite/unlimited" feeling when content is shorter than viewport.
      physics: const ClampingScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: _wizardStepPadding(context),
      child: Form(
        key: _familyFormKey,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: AC.traditionalBorder(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle('Marital Status', Icons.favorite_outline),
              const SizedBox(height: 20),

              // Marital Status
              CustomDropdown(
                label: 'Marital Status *',
                hint: 'Select marital status',
                value: _maritalStatus,
                items: ReferenceData.maritalStatuses,
                onChanged: (value) => setState(() => _maritalStatus = value),
                icon: Icons.favorite,
              ),
              const SizedBox(height: 28),

              _buildSectionTitle('Family Information', Icons.family_restroom),
              const SizedBox(height: 20),

              // Family Type
              CustomDropdown(
                label: 'Family Type *',
                hint: 'Select family type',
                value: _familyType,
                items: ReferenceData.familyTypes,
                onChanged: (value) => setState(() => _familyType = value),
                icon: Icons.home,
              ),
              const SizedBox(height: 20),

              // Family Status
              CustomDropdown(
                label: 'Family Status *',
                hint: 'Select family status',
                value: _familyStatus,
                items: ReferenceData.familyStatuses,
                onChanged: (value) => setState(() => _familyStatus = value),
                icon: Icons.account_balance,
              ),
              const SizedBox(height: 20),

              // Family Values
              CustomDropdown(
                label: 'Family Values *',
                hint: 'Select family values',
                value: _familyValues,
                items: ReferenceData.familyValues,
                onChanged: (value) => setState(() => _familyValues = value),
                icon: Icons.psychology_outlined,
              ),
              const SizedBox(height: 28),

              _buildSectionTitle("Parents' Details", Icons.people_outline),
              const SizedBox(height: 20),

              // Father's Name (Required)
              TextFormField(
                inputFormatters: [
                  PhoneNumberGuard(onPhoneDetected: _showInputGuardWarning),
                ],
                controller: _fatherNameController,
                focusNode: _fatherNameFocus,
                scrollPadding: const EdgeInsets.only(bottom: 160),
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                onEditingComplete: () => _advanceToNextField('fatherName'),
                decoration: InputDecoration(
                  labelText: "Father's Name *",
                  hintText: 'Enter father\'s full name',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: AppTheme.primaryOrange,
                      width: 2,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter father\'s name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // Father's Status
              CustomDropdown(
                label: "Father's Status *",
                hint: 'Select status',
                value: _fatherOccupation,
                items: ReferenceData.fatherOccupations,
                onChanged: (value) {
                  setState(() => _fatherOccupation = value);
                  _advanceToNextField('fatherOccupation');
                },
                icon: Icons.man,
              ),
              const SizedBox(height: 14),

              // Father's Occupation Note (optional free text)
              _NoteField(
                controller: _fatherNoteController,
                label: "Father's Additional Note (Optional)",
                hint:
                    'e.g. Retired IAS officer, runs family business, actively involved in social service…',
                onGuardWarning: _showInputGuardWarning,
                noNumbers: false, // Changed to false to allow normal editing
                maxWords: 100, // Increased from 3 to 100 words
              ),
              const SizedBox(height: 20),

              // Mother's Name (Required)
              TextFormField(
                inputFormatters: [
                  PhoneNumberGuard(onPhoneDetected: _showInputGuardWarning),
                ],
                controller: _motherNameController,
                focusNode: _motherNameFocus,
                scrollPadding: const EdgeInsets.only(bottom: 160),
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                onEditingComplete: () => _advanceToNextField('motherName'),
                decoration: InputDecoration(
                  labelText: "Mother's Name *",
                  hintText: 'Enter mother\'s full name',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: AppTheme.primaryOrange,
                      width: 2,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter mother\'s name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // Mother's Status
              CustomDropdown(
                label: "Mother's Status *",
                hint: 'Select status',
                value: _motherOccupation,
                items: ReferenceData.motherOccupations,
                onChanged: (value) {
                  setState(() => _motherOccupation = value);
                  _advanceToNextField('motherOccupation');
                },
                icon: Icons.woman,
              ),
              const SizedBox(height: 14),

              // Mother's Occupation Note (optional free text)
              _NoteField(
                controller: _motherNoteController,
                label: "Mother's Additional Note (Optional)",
                hint:
                    'e.g. Housewife, actively involved in community service, manages family affairs…',
                onGuardWarning: _showInputGuardWarning,
                noNumbers: false, // Changed to false to allow normal editing
                maxWords: 100, // Increased from 3 to 100 words
              ),
              SizedBox(height: 28),

              // Reference Section for Backend Verification (Optional)
              _buildSectionTitle(
                'Quick Reference (Optional)',
                Icons.verified_user_outlined,
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primaryGold.withAlpha(15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.primaryGold.withAlpha(40)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: AppTheme.templeGold,
                      size: 18,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Optional: These details help establish quick family connections between matches. You can skip if you prefer privacy.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AC.textSub(context),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Mother's Maiden Surname (Optional)
              TextFormField(
                inputFormatters: [
                  PhoneNumberGuard(onPhoneDetected: _showInputGuardWarning),
                ],
                controller: _motherSurnameController,
                focusNode: _motherSurnameFocus,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                onEditingComplete: () => _advanceToNextField('motherSurname'),
                decoration: const InputDecoration(
                  labelText: "Mother's Surname (Maiden Name)",
                  hintText: "Enter mother's family surname before marriage",
                  prefixIcon: Icon(Icons.person_outline),
                  helperText: 'Optional - Example: Sharma, Reddy, Rao, etc.',
                ),
              ),
              const SizedBox(height: 20),

              // Family Origin Location (Optional)
              _buildSectionTitle(
                'Family Origin (Ancestral Place)',
                Icons.location_history,
              ),
              const SizedBox(height: 20),

              _buildPinAutofill(
                sectionTitle: 'PIN Code — auto-fill family origin',
                onApply: _applyFamilyOriginPin,
                focusAfterSingleMatch: _familyOriginCityFocus,
              ),
              const SizedBox(height: 20),

              KeyedSubtree(
                key: ValueKey('family_loc_${_familyOriginPinSlot.applySerial}'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CustomDropdown(
                      label: 'Country',
                      hint: 'Select country',
                      value:
                          _familyOriginPinSlot.country ?? _familyOriginCountry,
                      items: ReferenceData.countries,
                      onChanged: (value) {
                          setState(() {
                            _familyOriginPinSlot.country = value ?? 'India';
                            _familyOriginCountry = _familyOriginPinSlot.country;
                            _familyOriginPinSlot.clearPinCityScope();
                            _familyOriginPinSlot.state = null;
                            _familyOriginState = null;
                            _familyOriginPinSlot.city = '';
                            _familyOriginCityController.clear();
                          });
                      },
                      icon: Icons.public,
                    ),
                    const SizedBox(height: 20),
                    if ((_familyOriginPinSlot.country ?? _familyOriginCountry) ==
                        'India')
                      CustomDropdown(
                        label: 'State',
                        hint: 'Select state',
                        value:
                            _familyOriginPinSlot.state ?? _familyOriginState,
                        items: ReferenceData.indianStates,
                        onChanged: (value) {
                          setState(() {
                            _familyOriginPinSlot.state = value;
                            _familyOriginPinSlot.clearPinCityScope();
                            _familyOriginState = value;
                            _familyOriginPinSlot.city = '';
                            _familyOriginCityController.clear();
                          });
                        },
                        icon: Icons.map_outlined,
                      )
                    else
                      TextFormField(
                        inputFormatters: [
                          PhoneNumberGuard(
                            onPhoneDetected: _showInputGuardWarning,
                          ),
                        ],
                        controller: TextEditingController(
                          text: _familyOriginState ?? '',
                        ),
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'State/Province',
                          hintText: 'Enter state or province',
                          prefixIcon: Icon(Icons.map_outlined),
                        ),
                        onChanged: (value) {
                          setState(() {
                            final t = value.trim();
                            _familyOriginState = t.isEmpty ? null : t;
                            _familyOriginPinSlot.state = _familyOriginState;
                          });
                        },
                      ),
                    const SizedBox(height: 20),
                    if ((_familyOriginPinSlot.country ?? _familyOriginCountry) ==
                            'India' &&
                        (_familyOriginPinSlot.state ?? _familyOriginState) !=
                            null &&
                        (_familyOriginPinSlot.hasPinScopedCities ||
                            ReferenceData.cities.containsKey(
                              _familyOriginPinSlot.state ??
                                  _familyOriginState!,
                            )))
                      CustomDropdown(
                        key: ValueKey(
                          'family_city_${_familyOriginPinSlot.applySerial}',
                        ),
                        label: 'City/Town',
                        hint: 'Select city or town',
                        value: _familyOriginPinSlot.cityDropdownValue,
                        items: indianCityDropdownItems(
                          _familyOriginPinSlot.state ?? _familyOriginState,
                          selectedCity: _familyOriginPinSlot.city,
                          pinScopedOptions:
                              _familyOriginPinSlot.hasPinScopedCities
                                  ? _familyOriginPinSlot.pinScopedCityOptions
                                  : null,
                        ),
                        onChanged: (value) {
                          setState(() {
                            _familyOriginPinSlot.city = value ?? '';
                            syncLocationCityController(
                              _familyOriginCityController,
                              value ?? '',
                            );
                          });
                        },
                        icon: Icons.location_city,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              if ((_familyOriginPinSlot.country ?? _familyOriginCountry) ==
                      'India' &&
                  (_familyOriginPinSlot.state ?? _familyOriginState) != null &&
                  !ReferenceData.cities.containsKey(
                    _familyOriginPinSlot.state ?? _familyOriginState!,
                  ))
                TextFormField(
                  inputFormatters: [
                    PhoneNumberGuard(onPhoneDetected: _showInputGuardWarning),
                  ],
                  controller: _familyOriginCityController,
                  focusNode: _familyOriginCityFocus,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'City/Town',
                    hintText: 'Enter city or town',
                    prefixIcon: Icon(Icons.location_city),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _familyOriginPinSlot.city = value.trim();
                    });
                  },
                )
              else if (_familyOriginCountry != null &&
                  _familyOriginCountry != 'India' &&
                  ReferenceData.citiesByCountry.containsKey(
                    _familyOriginCountry!,
                  ))
                CustomDropdown(
                  key: ValueKey(
                    'family_city_intl_${_familyOriginPinSlot.applySerial}',
                  ),
                  label: 'City/Town',
                  hint: 'Select city or town',
                  value: _familyOriginPinSlot.cityDropdownValue,
                  items:
                      ReferenceData.citiesByCountry[_familyOriginCountry!] ??
                      const <String>[],
                  onChanged: (value) {
                    setState(() {
                      _familyOriginPinSlot.city = value ?? '';
                      syncLocationCityController(
                        _familyOriginCityController,
                        value ?? '',
                      );
                    });
                  },
                  icon: Icons.location_city,
                )
              else if (_familyOriginCountry != null)
                TextFormField(
                  inputFormatters: [
                    PhoneNumberGuard(onPhoneDetected: _showInputGuardWarning),
                  ],
                  controller: _familyOriginCityController,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: 'City/Town',
                    hintText: _familyOriginCountry == 'India'
                        ? (_familyOriginState == null
                              ? 'Select state first'
                              : 'Enter city or town')
                        : 'Enter city or town',
                    prefixIcon: Icon(Icons.location_city),
                    helperText:
                        'Optional - Original place where family comes from',
                  ),
                  enabled: _familyOriginCountry == 'India'
                      ? _familyOriginState != null
                      : true,
                ),
              SizedBox(height: 20),

              // Known Reference 1 (Optional)
              TextFormField(
                inputFormatters: [
                  PhoneNumberGuard(onPhoneDetected: _showInputGuardWarning),
                ],
                controller: _knownReferenceController,
                focusNode: _knownReferenceFocus,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                onEditingComplete: () => _advanceToNextField('knownReference'),
                decoration: const InputDecoration(
                  labelText: 'Reference 1 (Community Elder/Person)',
                  hintText: 'Name of someone who can vouch for family',
                  prefixIcon: Icon(Icons.person_pin),
                  helperText:
                      'Optional - A respected person who knows your family',
                ),
              ),
              const SizedBox(height: 20),

              // Known Reference 2 (Optional)
              TextFormField(
                inputFormatters: [
                  PhoneNumberGuard(onPhoneDetected: _showInputGuardWarning),
                ],
                controller: _knownReference2Controller,
                focusNode: _knownReference2Focus,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                onEditingComplete: () => _advanceToNextField('knownReference2'),
                decoration: const InputDecoration(
                  labelText: 'Reference 2 (Community Elder/Person)',
                  hintText: 'Name of another person who can vouch',
                  prefixIcon: Icon(Icons.people_outline),
                  helperText: 'Optional - Another trusted person in community',
                ),
              ),
              const SizedBox(height: 28),

              _buildSectionTitle('Siblings', Icons.group_outlined),
              const SizedBox(height: 20),

              Column(
                children: [
                  _buildCounterField(
                    label: 'Brothers',
                    value: _brothers,
                    onChanged: (val) => setState(() => _brothers = val),
                  ),
                  const SizedBox(height: 16),
                  _buildCounterField(
                    label: 'Married',
                    value: _brothersMarried,
                    max: _brothers,
                    onChanged: (val) => setState(() => _brothersMarried = val),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              Column(
                children: [
                  _buildCounterField(
                    label: 'Sisters',
                    value: _sisters,
                    onChanged: (val) => setState(() => _sisters = val),
                  ),
                  const SizedBox(height: 16),
                  _buildCounterField(
                    label: 'Married',
                    value: _sistersMarried,
                    max: _sisters,
                    onChanged: (val) => setState(() => _sistersMarried = val),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // About Family Section
              _buildSectionTitle('About Your Family', Icons.family_restroom),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primaryGold.withAlpha(15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.primaryGold.withAlpha(40)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline,
                      color: AppTheme.templeGold,
                      size: 18,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Share any additional information about your family that you would like others to know.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AC.textSub(context),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Anything to say about your family
              TextFormField(
                inputFormatters: [
                  PhoneNumberGuard(onPhoneDetected: _showInputGuardWarning),
                ],
                controller: _aboutFamilyController,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Anything to say about your family',
                  hintText:
                      'Share information about your family background, values, traditions, or anything else you would like others to know (optional)',
                  prefixIcon: Icon(Icons.edit_note),
                  alignLabelWithHint: true,
                  helperText:
                      'Optional - This helps others understand your family better',
                ),
              ),
              const SizedBox(height: 24),

              // Native Place Location
              _buildSectionTitle('Native Place', Icons.home_work_outlined),
              const SizedBox(height: 20),

              _buildPinAutofill(
                sectionTitle: 'PIN Code — auto-fill native place',
                onApply: _applyNativePlacePin,
              ),
              const SizedBox(height: 20),

              KeyedSubtree(
                key: ValueKey('native_loc_${_nativePlacePinSlot.applySerial}'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CustomDropdown(
                      label: 'Country *',
                      hint: 'Select country',
                      value: _nativePlacePinSlot.country ?? _nativePlaceCountry,
                      items: ReferenceData.countries,
                      onChanged: (value) {
                        setState(() {
                          _nativePlacePinSlot.country = value ?? 'India';
                          _nativePlaceCountry = _nativePlacePinSlot.country;
                          _nativePlacePinSlot.clearPinCityScope();
                          _nativePlacePinSlot.state = null;
                          _nativePlaceState = null;
                          _nativePlacePinSlot.city = '';
                          _nativePlaceCityController.clear();
                        });
                      },
                      icon: Icons.public,
                    ),
                    const SizedBox(height: 20),
                    if ((_nativePlacePinSlot.country ?? _nativePlaceCountry) ==
                        'India')
                      CustomDropdown(
                        label: 'State *',
                        hint: 'Select state',
                        value: _nativePlacePinSlot.state ?? _nativePlaceState,
                        items: ReferenceData.indianStates,
                        onChanged: (value) {
                          setState(() {
                            _nativePlacePinSlot.state = value;
                            _nativePlacePinSlot.clearPinCityScope();
                            _nativePlaceState = value;
                            _nativePlacePinSlot.city = '';
                            _nativePlaceCityController.clear();
                          });
                        },
                        icon: Icons.map_outlined,
                      ),
                    const SizedBox(height: 20),
                    if ((_nativePlacePinSlot.country ?? _nativePlaceCountry) ==
                            'India' &&
                        (_nativePlacePinSlot.state ?? _nativePlaceState) !=
                            null &&
                        (_nativePlacePinSlot.hasPinScopedCities ||
                            ReferenceData.cities.containsKey(
                              _nativePlacePinSlot.state ?? _nativePlaceState!,
                            )))
                      CustomDropdown(
                        key: ValueKey(
                          'native_city_${_nativePlacePinSlot.applySerial}',
                        ),
                        label: 'City/Town *',
                        hint: 'Select city or town',
                        value: _nativePlacePinSlot.cityDropdownValue,
                        items: indianCityDropdownItems(
                          _nativePlacePinSlot.state ?? _nativePlaceState,
                          selectedCity: _nativePlacePinSlot.city,
                          pinScopedOptions: _nativePlacePinSlot.hasPinScopedCities
                              ? _nativePlacePinSlot.pinScopedCityOptions
                              : null,
                        ),
                        onChanged: (value) {
                          setState(() {
                            _nativePlacePinSlot.city = value ?? '';
                            syncLocationCityController(
                              _nativePlaceCityController,
                              value ?? '',
                            );
                          });
                        },
                        icon: Icons.location_city,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              if ((_nativePlacePinSlot.country ?? _nativePlaceCountry) != 'India')
                TextFormField(
                  inputFormatters: [
                    PhoneNumberGuard(onPhoneDetected: _showInputGuardWarning),
                  ],
                  controller: TextEditingController(
                    text: _nativePlaceState ?? '',
                  ),
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'State/Province *',
                    hintText: 'Enter state or province',
                    prefixIcon: Icon(Icons.map_outlined),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _nativePlaceState = value.trim().isEmpty
                          ? null
                          : value.trim();
                    });
                  },
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter state/province';
                    }
                    return null;
                  },
                ),
              const SizedBox(height: 20),

              if ((_nativePlacePinSlot.country ?? _nativePlaceCountry) ==
                      'India' &&
                  (_nativePlacePinSlot.state ?? _nativePlaceState) != null &&
                  !ReferenceData.cities.containsKey(
                    _nativePlacePinSlot.state ?? _nativePlaceState!,
                  ))
                TextFormField(
                  inputFormatters: [
                    PhoneNumberGuard(onPhoneDetected: _showInputGuardWarning),
                  ],
                  controller: _nativePlaceCityController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'City/Town *',
                    hintText: 'Enter city or town',
                    prefixIcon: Icon(Icons.location_city),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _nativePlacePinSlot.city = value.trim();
                    });
                  },
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter city or town';
                    }
                    return null;
                  },
                )
              else if (_nativePlaceCountry != null &&
                  _nativePlaceCountry != 'India' &&
                  ReferenceData.citiesByCountry.containsKey(
                    _nativePlaceCountry!,
                  ))
                CustomDropdown(
                  key: ValueKey(
                    'native_city_intl_${_nativePlacePinSlot.applySerial}',
                  ),
                  label: 'City/Town *',
                  hint: 'Select city or town',
                  value: _nativePlacePinSlot.cityDropdownValue,
                  items:
                      ReferenceData.citiesByCountry[_nativePlaceCountry!] ??
                      const <String>[],
                  onChanged: (value) {
                    setState(() {
                      _nativePlacePinSlot.city = value ?? '';
                      syncLocationCityController(
                        _nativePlaceCityController,
                        value ?? '',
                      );
                    });
                  },
                  icon: Icons.location_city,
                )
              else if (_nativePlaceCountry != null &&
                  !((_nativePlacePinSlot.country ?? _nativePlaceCountry) ==
                          'India' &&
                      (_nativePlacePinSlot.state ?? _nativePlaceState) !=
                          null &&
                      (_nativePlacePinSlot.hasPinScopedCities ||
                          ReferenceData.cities.containsKey(
                            _nativePlacePinSlot.state ?? _nativePlaceState!,
                          ))))
                TextFormField(
                  inputFormatters: [
                    PhoneNumberGuard(onPhoneDetected: _showInputGuardWarning),
                  ],
                  controller: _nativePlaceCityController,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: 'City/Town *',
                    hintText: _nativePlaceCountry == 'India'
                        ? (_nativePlaceState == null
                              ? 'Select state first'
                              : 'Enter city or town')
                        : 'Enter city or town',
                    prefixIcon: const Icon(Icons.location_city),
                  ),
                  enabled: _nativePlaceCountry == 'India'
                      ? _nativePlaceState != null
                      : true,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter city/town';
                    }
                    return null;
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCounterField({
    required String label,
    required int value,
    int max = 10,
    required ValueChanged<int> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AC.surface(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AC.surface(context)),
      ),
      child: Column(
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: value > 0 ? () => onChanged(value - 1) : null,
                icon: const Icon(Icons.remove_circle_outline),
                color: AppTheme.primaryOrange,
                iconSize: 28,
              ),
              Container(
                width: 36,
                alignment: Alignment.center,
                child: Text(
                  value.toString(),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppTheme.primaryOrange,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                onPressed: value < max ? () => onChanged(value + 1) : null,
                icon: const Icon(Icons.add_circle_outline),
                color: AppTheme.primaryOrange,
                iconSize: 28,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ========== STEP 6: LIFESTYLE & INTERESTS ==========
  Widget _buildLifestyleStep() {
    return SingleChildScrollView(
      key: const PageStorageKey<String>('profile_wizard_step_lifestyle'),
      primary: false,
      // Prevent "infinite/unlimited" feeling when content is shorter than viewport.
      physics: const ClampingScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: _wizardStepPadding(context),
      child: Form(
        key: _lifestyleFormKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Profile Photo Section
            Container(
              padding: const EdgeInsets.all(24),
              decoration: AC.traditionalBorder(context),
              child: Column(
                children: [
                  _buildSectionTitle(
                    'Profile Photo',
                    Icons.camera_alt_outlined,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add a clear photo to get better matches',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 20),
                  ProfilePhotoPicker(
                    currentImagePath: _profilePicturePath,
                    onImageSelected: (path) async {
                      // ProfilePhotoPicker uploads via Cloudinary (same as My Profile).
                      // and returns the final https:// URL. Just store it.
                      setState(() {
                        _profilePicturePath =
                            path; // null = removed, URL = uploaded
                      });
                    },
                    size: 140,
                    isPrivate: _isPhotoPrivate,
                    onPrivacyChanged: (isPrivate) {
                      setState(() => _isPhotoPrivate = isPrivate);
                    },
                  ),
                  SizedBox(height: 16),
                  // Privacy info
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AC.surface(context),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 18,
                          color: AC.card(context),
                        ),
                        SizedBox(height: 8),
                        Text(
                          _isPhotoPrivate
                              ? 'Hidden — visible only after you accept a photo-view request.'
                              : 'Public — visible to members who may open your profile.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AC.textSub(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Partner Preferences Section (First)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: AC.traditionalBorder(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionTitle(
                    'Partner Preferences',
                    Icons.favorite_outline,
                  ),
                  const SizedBox(height: 12),

                  // Auto Generate Partner Preferences Button
                  OutlinedButton.icon(
                    onPressed: _autoGeneratePartnerPreferences,
                    icon: const Icon(Icons.auto_awesome, size: 18),
                    label: const Text('Auto Generate Partner Preferences'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.peacockBlue,
                      side: const BorderSide(color: AppTheme.peacockBlue),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Partner Preferences (Text Description)
                  TextFormField(
                    inputFormatters: [
                      PhoneNumberGuard(onPhoneDetected: _showInputGuardWarning),
                    ],
                    controller: _partnerPreferencesController,
                    maxLines: 4,
                    maxLength: 500,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Partner Preferences *',
                      hintText:
                          'Describe your ideal partner and what qualities you value...',
                      alignLabelWithHint: true,
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please describe your partner preferences';
                      }
                      if (value.trim().length < 30) {
                        return 'Please write at least 30 characters';
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: 24),

                  // Detailed Partner Preferences Section
                  _buildSectionTitle(
                    'Detailed Partner Preferences (Optional)',
                    Icons.favorite_border,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Set specific preferences to help us find better matches for you',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: AC.textSub(context)),
                  ),
                  const SizedBox(height: 16),

                  // Age Range
                  Column(
                    children: [
                      CustomDropdown(
                        label: 'Min Age',
                        hint: 'Any',
                        value: _partnerAgeMin?.toString(),
                        items: [
                          'Any',
                          ...ReferenceData.partnerAgeOptions.map(
                            (a) => a.toString(),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _partnerAgeMin = value == 'Any' || value == null
                                ? null
                                : int.tryParse(value);
                          });
                        },
                        icon: Icons.calendar_today,
                      ),
                      const SizedBox(height: 12),
                      CustomDropdown(
                        label: 'Max Age',
                        hint: 'Any',
                        value: _partnerAgeMax?.toString(),
                        items: [
                          'Any',
                          ...ReferenceData.partnerAgeOptions.map(
                            (a) => a.toString(),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _partnerAgeMax = value == 'Any' || value == null
                                ? null
                                : int.tryParse(value);
                          });
                        },
                        icon: Icons.calendar_today,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Height Range
                  Column(
                    children: [
                      CustomDropdown(
                        label: 'Min Height',
                        hint: 'Any',
                        value: _partnerHeightMin,
                        items: ['Any', ...ReferenceData.heights],
                        onChanged: (value) {
                          setState(() {
                            _partnerHeightMin = value == 'Any' || value == null
                                ? null
                                : value;
                          });
                        },
                        icon: Icons.height,
                      ),
                      const SizedBox(height: 12),
                      CustomDropdown(
                        label: 'Max Height',
                        hint: 'Any',
                        value: _partnerHeightMax,
                        items: ['Any', ...ReferenceData.heights],
                        onChanged: (value) {
                          setState(() {
                            _partnerHeightMax = value == 'Any' || value == null
                                ? null
                                : value;
                          });
                        },
                        icon: Icons.height,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Education Preference
                  _buildSectionTitle(
                    'Preferred Education',
                    Icons.school_outlined,
                  ),
                  const SizedBox(height: 8),
                  MultiSelectChip(
                    items: ReferenceData.educationLevels,
                    selectedItems: _selectedPartnerEducation,
                    onSelectionChanged: (selected) {
                      setState(() => _selectedPartnerEducation = selected);
                    },
                  ),
                  const SizedBox(height: 16),

                  // Occupation Preference
                  _buildSectionTitle(
                    'Preferred Occupation',
                    Icons.work_outline,
                  ),
                  const SizedBox(height: 8),
                  MultiSelectChip(
                    items: ReferenceData.occupations,
                    selectedItems: _selectedPartnerOccupation,
                    onSelectionChanged: (selected) {
                      setState(() => _selectedPartnerOccupation = selected);
                    },
                  ),
                  const SizedBox(height: 16),

                  // Income Preference
                  CustomDropdown(
                    label: 'Minimum Income',
                    hint: 'Any',
                    value: _partnerIncomeMin,
                    items: ['Any', ...ReferenceData.incomeRanges],
                    onChanged: (value) {
                      setState(() {
                        _partnerIncomeMin = value == 'Any' || value == null
                            ? null
                            : value;
                      });
                    },
                    icon: Icons.attach_money,
                  ),
                  const SizedBox(height: 16),

                  // Marital Status Preference
                  _buildSectionTitle(
                    'Preferred Marital Status',
                    Icons.favorite,
                  ),
                  const SizedBox(height: 8),
                  MultiSelectChip(
                    items: ReferenceData.maritalStatuses,
                    selectedItems: _selectedPartnerMaritalStatus,
                    onSelectionChanged: (selected) {
                      setState(() => _selectedPartnerMaritalStatus = selected);
                    },
                  ),
                  const SizedBox(height: 16),

                  // Location Preference
                  _buildSectionTitle(
                    'Preferred Locations',
                    Icons.location_on_outlined,
                  ),
                  const SizedBox(height: 8),
                  MultiSelectChip(
                    items: ReferenceData.partnerLocationPreferences,
                    selectedItems: _selectedPartnerLocations,
                    onSelectionChanged: (selected) {
                      setState(() => _selectedPartnerLocations = selected);
                    },
                  ),
                  const SizedBox(height: 16),

                  // Manglik Preference
                  CustomDropdown(
                    label: 'Manglik Preference',
                    hint: 'No Preference',
                    value: _partnerManglikPreference == null
                        ? 'No Preference'
                        : (_partnerManglikPreference == true
                              ? 'Accepts Manglik'
                              : 'Does Not Accept Manglik'),
                    items: [
                      'No Preference',
                      'Accepts Manglik',
                      'Does Not Accept Manglik',
                    ],
                    onChanged: (value) {
                      setState(() {
                        if (value == 'No Preference' || value == null) {
                          _partnerManglikPreference = null;
                        } else {
                          _partnerManglikPreference =
                              value == 'Accepts Manglik';
                        }
                      });
                    },
                    icon: Icons.star_outline,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Food & Lifestyle Section
            Container(
              padding: const EdgeInsets.all(24),
              decoration: AC.traditionalBorder(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionTitle(
                    'Food & Lifestyle',
                    Icons.restaurant_outlined,
                  ),
                  const SizedBox(height: 20),

                  // Food Habit
                  CustomDropdown(
                    label: 'Food Habit *',
                    hint: 'Select food habit',
                    value: _foodHabit,
                    items: ReferenceData.foodHabits,
                    onChanged: (value) => setState(() => _foodHabit = value),
                    icon: Icons.restaurant,
                  ),
                  const SizedBox(height: 20),

                  // Smoking
                  CustomDropdown(
                    label: 'Smoking *',
                    hint: 'Select option',
                    value: _smokingHabit,
                    items: ReferenceData.smokingHabits,
                    onChanged: (value) => setState(() => _smokingHabit = value),
                    icon: Icons.smoking_rooms,
                  ),
                  const SizedBox(height: 20),

                  // Drinking
                  CustomDropdown(
                    label: 'Drinking *',
                    hint: 'Select option',
                    value: _drinkingHabit,
                    items: ReferenceData.drinkingHabits,
                    onChanged: (value) =>
                        setState(() => _drinkingHabit = value),
                    icon: Icons.local_bar,
                  ),
                  const SizedBox(height: 28),

                  _buildSectionTitle('Languages Spoken', Icons.translate),
                  const SizedBox(height: 16),

                  MultiSelectChip(
                    items: ReferenceData.languages,
                    selectedItems: _selectedLanguages,
                    onSelectionChanged: (selected) {
                      setState(() => _selectedLanguages = selected);
                    },
                  ),
                  const SizedBox(height: 28),

                  _buildSectionTitle('Hobbies & Interests', Icons.interests),
                  const SizedBox(height: 16),

                  MultiSelectChip(
                    items: ReferenceData.hobbies,
                    selectedItems: _selectedHobbies,
                    onSelectionChanged: (selected) {
                      setState(() => _selectedHobbies = selected);
                    },
                  ),
                  const SizedBox(height: 28),

                  _buildSectionTitle('About Yourself', Icons.edit_note),
                  const SizedBox(height: 12),

                  // Auto Generate Button
                  OutlinedButton.icon(
                    onPressed: _autoGenerateAboutMe,
                    icon: const Icon(Icons.auto_awesome, size: 18),
                    label: const Text('Auto Generate from Profile'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primaryOrange,
                      side: const BorderSide(color: AppTheme.primaryOrange),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // About Me
                  TextFormField(
                    inputFormatters: [
                      PhoneNumberGuard(onPhoneDetected: _showInputGuardWarning),
                    ],
                    controller: _aboutMeController,
                    maxLines: 4,
                    maxLength: 500,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'About Me *',
                      hintText:
                          'Write something about yourself, your values, and what you are looking for...',
                      alignLabelWithHint: true,
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please write something about yourself';
                      }
                      if (value.trim().length < 50) {
                        return 'Please write at least 50 characters';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AC.surface(context),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: AC.textSub(context)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: AC.textSub(context),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _NoteField  ──  free-text note box with live counter + input guard
//
//  Standard mode  (noNumbers: false)
//    • 150-character hard limit
//    • NoteFieldGuard — blocks phone numbers and contact-sharing patterns
//    • Counter shows "X / 150"
//
//  Parent-note mode  (noNumbers: true, maxWords: 3)
//    • AlphaOnlyGuard — no digits, no number words
//    • 3-word hard limit (enforced per keystroke)
//    • Counter shows "X / 3 words"
// ─────────────────────────────────────────────────────────────────────────────

class _NoteField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final void Function(String) onGuardWarning;

  /// When true, blocks all digits and number words, and enforces [maxWords].
  final bool noNumbers;

  /// Maximum allowed words. Only applied when [noNumbers] is true.
  /// Defaults to 100 for parent fields.
  final int maxWords;

  const _NoteField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.onGuardWarning,
    this.noNumbers = false,
    this.maxWords = 100, // Increased default from 3 to 100
  });

  @override
  State<_NoteField> createState() => _NoteFieldState();
}

class _NoteFieldState extends State<_NoteField> {
  static const int _maxChars = 500; // Increased from 150 to 500 characters

  // Count non-empty words in a string
  int _wordCount(String text) => text.trim().isEmpty
      ? 0
      : text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.controller.text;
    final charCount = text.length;
    final wordCount = _wordCount(text);

    // ── Counter display & colour ────────────────────────────────────────────
    final String counterText;
    final Color counterColor;
    final bool showWarningIcon;

    if (widget.noNumbers) {
      // Word-count mode
      final remaining = widget.maxWords - wordCount;
      showWarningIcon = remaining == 0;
      counterText = '$wordCount / ${widget.maxWords} words';
      counterColor = remaining == 0
          ? AppTheme.kumkumRed
          : remaining == 1
          ? AppTheme.primaryOrange
          : AppTheme.textMedium;
    } else {
      // Char-count mode
      final remaining = _maxChars - charCount;
      showWarningIcon = remaining <= 10;
      counterText = '$charCount / $_maxChars';
      counterColor = remaining <= 10
          ? AppTheme.kumkumRed
          : remaining <= 30
          ? AppTheme.primaryOrange
          : AppTheme.textMedium;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: widget.controller,
          minLines: 4, // Increased from 3 to 4 for better editing
          maxLines: 6, // Increased from 3 to 6 to allow more content
          maxLength: _maxChars,
          buildCounter:
              (_, {required currentLength, required isFocused, maxLength}) =>
                  null,
          textCapitalization: TextCapitalization.sentences,
          style: TextStyle(
            fontSize: 16,
          ), // Increased font size for better readability
          inputFormatters: [
            if (widget.noNumbers)
              // Blocks digits, number words, and enforces maxWords
              _ParentNoteGuard(
                maxWords: widget.maxWords,
                onBlocked: widget.onGuardWarning,
              )
            else
              NoteFieldGuard(onBlocked: widget.onGuardWarning),
          ],
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.hint,
            hintStyle: TextStyle(
              fontSize: 14,
              color: AppTheme.textLight.withAlpha(160),
            ), // Increased hint font size
            alignLabelWithHint: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ), // Increased border radius
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: AppTheme.primaryOrange,
                width: 2,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppTheme.textLight.withAlpha(100)),
            ),
            prefixIcon: const Padding(
              padding: EdgeInsets.only(bottom: 40),
              child: Icon(
                Icons.edit_note,
                color: AppTheme.textMedium,
                size: 20,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ), // Increased padding
          ),
        ),
        // Custom counter row
        Padding(
          padding: const EdgeInsets.only(top: 4, right: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (showWarningIcon)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(
                    Icons.warning_amber_rounded,
                    size: 13,
                    color: AppTheme.kumkumRed,
                  ),
                ),
              Text(
                counterText,
                style: TextStyle(
                  fontSize: 11,
                  color: counterColor,
                  fontWeight:
                      (widget.noNumbers
                          ? wordCount >= widget.maxWords - 1
                          : charCount >= _maxChars - 30)
                      ? FontWeight.w600
                      : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Parent Note Guard (for Father/Mother additional notes)
//
// Used for parent occupation notes where we want to allow normal text editing
// while preventing contact information sharing:
//
//    • No phone numbers (Indian format)
//    • No email addresses
//    • No contact-sharing keywords
//    • Maximum [maxWords] space-separated words (default 100)
// ─────────────────────────────────────────────────────────────────────────────

class _ParentNoteGuard extends TextInputFormatter {
  final int maxWords;
  final void Function(String)? onBlocked;

  // Only block actual phone numbers and obvious contact info, not all digits
  static const _phonePattern = r'\b(?:\+91|0)?[6-9]\d{9}\b';
  static const _emailPattern =
      r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b';

  const _ParentNoteGuard({this.maxWords = 100, this.onBlocked});

  int _wordCount(String text) => text.trim().isEmpty
      ? 0
      : text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;

    // Only block phone numbers (not all digits)
    if (RegExp(_phonePattern).hasMatch(text)) {
      onBlocked?.call('⚠ Phone numbers are not allowed in this field.');
      return oldValue;
    }

    // Only block email addresses
    if (RegExp(_emailPattern, caseSensitive: false).hasMatch(text)) {
      onBlocked?.call('⚠ Email addresses are not allowed in this field.');
      return oldValue;
    }

    // Block obvious contact keywords
    final lower = text.toLowerCase();
    final contactKeywords = [
      'call me',
      'phone',
      'mobile',
      'contact',
      'whatsapp',
      'email',
      'gmail',
      'yahoo',
      'outlook',
      'hotmail',
      'number',
      'dial',
      'ring',
      'message',
      'sms',
      'text me',
      'reach me',
      'get in touch',
    ];

    for (final keyword in contactKeywords) {
      if (lower.contains(keyword)) {
        onBlocked?.call('⚠ Contact information is not allowed in this field.');
        return oldValue;
      }
    }

    // Enforce word limit
    final words = _wordCount(text);
    if (words > maxWords) {
      onBlocked?.call('⚠ Maximum $maxWords words allowed in this field.');
      return oldValue;
    }

    return newValue;
  }
}
