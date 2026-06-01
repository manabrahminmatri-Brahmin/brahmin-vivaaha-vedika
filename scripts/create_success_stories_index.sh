#!/bin/bash

# Create Firestore composite index for success stories
# This script creates the required index for the success_stories collection

echo "🔥 Creating Firestore composite index for success_stories collection..."

# Using Firebase CLI to create the index
firebase firestore:indexes:create firestore_indexes.success_stories.json

echo "✅ Index creation initiated. The index will be created in a few minutes."
echo "📋 Index details:"
echo "   Collection: success_stories"
echo "   Fields: visible (ASC), married_at (DESC)"
echo "   Scope: Collection"
echo ""
echo "⏱️  Monitor the index creation status in Firebase Console:"
echo "   https://console.firebase.google.com/project/YOUR_PROJECT_ID/firestore/indexes"
