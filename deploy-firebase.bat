@echo off
echo 🔥 FIREBASE DEPLOYMENT SCRIPT
echo.

REM Check if in correct directory
if not exist "firestore.rules" (
    echo ❌ Error: firestore.rules not found!
    echo Please run this script from the project root directory
    pause
    exit /b 1
)

echo ✅ Found firestore.rules - continuing...
echo.

REM Deploy Firestore Rules
echo 🔥 Deploying Firestore Rules...
firebase deploy --only firestore
if %ERRORLEVEL% neq 0 (
    echo ❌ Firestore Rules deployment failed!
    pause
    exit /b 1
)
echo ✅ Firestore Rules deployed successfully!
echo.

REM Deploy Firestore Indexes
echo 📊 Deploying Firestore Indexes...
firebase deploy --only firestore:indexes
if %ERRORLEVEL% neq 0 (
    echo ❌ Firestore Indexes deployment failed!
    pause
    exit /b 1
)
echo ✅ Firestore Indexes deployed successfully!
echo.

echo 🎉 Firebase deployment completed successfully!
echo 🔗 Project Console: https://console.firebase.google.com/project/manabrahminmatri-de0ad/overview
echo.
echo ✨ All done! Your Firebase backend is ready.
pause
