from pymongo import MongoClient
from pymongo.errors import PyMongoError
import sys
import json

try:
    client = MongoClient(
        "mongodb://localhost:27017",
        connectTimeoutMS=3000,
        serverSelectionTimeoutMS=5000,
        socketTimeoutMS=5000,
        directConnection=True,
    )

    client.admin.command("ping")
    print(json.dumps({"ok": 1}))
    sys.exit(0)

except PyMongoError as e:
    print(json.dumps({
        "ok": 0,
        "error": str(e)
    }, ensure_ascii=False), file=sys.stderr)
    sys.exit(1)