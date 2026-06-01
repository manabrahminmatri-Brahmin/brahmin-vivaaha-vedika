@echo off
echo ============================================
echo Fast APK Build - Mana Vivaaha Vedika
echo ============================================
echo.

:: Clean only build artifacts (not cache)
echo Cleaning build artifacts...
call flutter clean

:: Get dependencies
echo Getting dependencies...
call flutter pub get

:: Build with optimizations
echo Building release APK with optimizations...
call flutter build apk --release --target-platform android-arm64 --split-debug-info=build/symbols --obfuscate

echo.
echo ============================================
echo Build complete! Check build\app\outputs\flutter-apk\
echo ============================================
pause
