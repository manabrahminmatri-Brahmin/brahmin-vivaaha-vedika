import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';

/// HTTPS callables — region must match Gen-1 deployment in `functions/index.js`.
FirebaseFunctions get appFirebaseFunctions =>
    FirebaseFunctions.instanceFor(app: Firebase.app(), region: 'asia-south1');
