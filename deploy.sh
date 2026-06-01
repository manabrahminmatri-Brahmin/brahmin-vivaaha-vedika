#!/bin/bash
# ============================================================
# deploy.sh
# Run this ONCE from your project root (where firebase.json is)
# Uses NEW Firebase params (replaces deprecated functions:config:set)
# ============================================================

echo "🔐 Setting Cloudinary credentials in functions/.env..."

# Create .env file in functions folder
cat > functions/.env << EOF
CLOUDINARY_CLOUD_NAME=dibgihscr
CLOUDINARY_API_KEY=633211926855186
CLOUDINARY_API_SECRET=YOUR_ACTUAL_API_SECRET_HERE
EOF

echo "✅ .env file created in functions/.env"
echo "⚠️  IMPORTANT: Replace YOUR_ACTUAL_API_SECRET_HERE with your real API secret!"

echo "📦 Installing function dependencies..."
cd functions && npm install && cd ..

echo "🚀 Deploying Firebase Functions..."
firebase deploy --only functions

echo "✅ Done! Your Cloud Functions are live."
echo ""
echo "Functions deployed:"
echo "  • getCloudinarySignature"
echo "  • deleteCloudinaryPhoto"
