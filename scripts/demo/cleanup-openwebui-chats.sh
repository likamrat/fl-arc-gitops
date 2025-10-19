#!/bin/bash
# cleanup-openwebui-chats.sh
# Delete all Open WebUI chat history directly from the database

set -e

NAMESPACE="foundry-system"

echo "🗑️  Cleaning up Open WebUI chat history..."

# Get the Open WebUI pod name
OPENWEBUI_POD=$(kubectl get pod -n $NAMESPACE -l app.kubernetes.io/component=open-webui -o jsonpath='{.items[0].metadata.name}')

if [ -z "$OPENWEBUI_POD" ]; then
    echo "❌ Error: Could not find Open WebUI pod"
    exit 1
fi

echo "📍 Found Open WebUI pod: $OPENWEBUI_POD"

# Delete chats from SQLite database
echo "🔧 Deleting all chats from database..."
kubectl exec -n $NAMESPACE $OPENWEBUI_POD -- python3 -c '
import sqlite3
import os

db_path = "/app/backend/data/webui.db"
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

# Get count before deletion
cursor.execute("SELECT COUNT(*) FROM chat")
count_before = cursor.fetchone()[0]
print(f"Found {count_before} chats")

# Delete all chats
cursor.execute("DELETE FROM chat")
conn.commit()

# Get count after deletion
cursor.execute("SELECT COUNT(*) FROM chat")
count_after = cursor.fetchone()[0]

# Vacuum to reclaim space
cursor.execute("VACUUM")
conn.commit()

conn.close()
print(f"Deleted {count_before - count_after} chats")
'

echo "✅ Chat history cleanup complete!"
echo ""
echo "💡 Tip: Refresh your Open WebUI browser tab to see the changes"
