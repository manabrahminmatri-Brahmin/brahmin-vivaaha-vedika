# 🔥 FIREBASE DEPLOYMENT SCRIPT FOR POWERSHELL
# This script deploys Firestore rules and indexes

Write-Host "🚀 Starting Firebase Deployment..." -ForegroundColor Green

# Check if Firebase CLI is installed
try {
    firebase --version | Out-Null
    Write-Host "✅ Firebase CLI found" -ForegroundColor Green
} catch {
    Write-Host "❌ Firebase CLI not found. Please install it first:" -ForegroundColor Red
    Write-Host "npm install -g firebase-tools" -ForegroundColor Yellow
    exit 1
}

# Change to project directory
Set-Location "C:\Users\attil\Documents\rahmin_Vivaaha Vedika"
Write-Host "📁 Changed to project directory" -ForegroundColor Green

# Deploy Firestore Rules
Write-Host "🔥 Deploying Firestore Rules..." -ForegroundColor Yellow
firebase deploy --only firestore

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Firestore Rules deployed successfully!" -ForegroundColor Green
} else {
    Write-Host "❌ Firestore Rules deployment failed!" -ForegroundColor Red
    exit 1
}

# Deploy Firestore Indexes
Write-Host "📊 Deploying Firestore Indexes..." -ForegroundColor Yellow
firebase deploy --only firestore:indexes

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Firestore Indexes deployed successfully!" -ForegroundColor Green
} else {
    Write-Host "❌ Firestore Indexes deployment failed!" -ForegroundColor Red
    exit 1
}

Write-Host "🎉 Firebase deployment completed successfully!" -ForegroundColor Green
Write-Host "🔗 Project Console: https://console.firebase.google.com/project/manabrahminmatri-de0ad/overview" -ForegroundColor Cyan

# Optional: Deploy everything (uncomment if needed)
# Write-Host "🚀 Deploying all Firebase resources..." -ForegroundColor Yellow
# firebase deploy

Write-Host "✨ All done! Your Firebase backend is ready." -ForegroundColor Magenta
