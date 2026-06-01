#!/bin/bash
# Flutter App Cleanup Script
# Run this script to clean up the project and optimize it

echo "🧹 Starting Flutter project cleanup..."

# Clean build artifacts
echo "📦 Cleaning build artifacts..."
flutter clean

# Get fresh dependencies
echo "📥 Getting fresh dependencies..."
flutter pub get

# Analyze the project
echo "🔍 Analyzing project..."
flutter analyze

# Fix automatic issues
echo "🔧 Applying automatic fixes..."
dart fix --apply

# Format code
echo "🎨 Formatting code..."
dart format .

# Run tests to ensure nothing broke
echo "🧪 Running tests..."
flutter test

# Build the app to verify everything works
echo "🏗️ Building app..."
flutter build apk --debug

echo "✅ Cleanup complete!"

# Show outdated dependencies
echo "📊 Checking for outdated dependencies..."
flutter pub outdated
