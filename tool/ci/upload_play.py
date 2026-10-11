#!/usr/bin/env python3
"""Upload an AAB to Play Console without changesNotSentForReview.

r0adkll/upload-google-play always sends that query param (default false).
Play accounts that auto-send for review reject the param entirely.
"""

import json
import os
import sys

from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload

SCOPE = "https://www.googleapis.com/auth/androidpublisher"


def require(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        sys.exit(f"missing env {name}")
    return value


def main() -> None:
    creds = service_account.Credentials.from_service_account_info(
        json.loads(require("PLAY_SERVICE_ACCOUNT_JSON")),
        scopes=[SCOPE],
    )
    package = require("PLAY_PACKAGE")
    track = require("PLAY_TRACK")
    status = os.environ.get("PLAY_STATUS", "completed").strip() or "completed"
    aab = require("PLAY_AAB")
    name = os.environ.get("PLAY_RELEASE_NAME", "").strip() or None

    if not os.path.isfile(aab):
        sys.exit(f"AAB not found: {aab}")

    publisher = build("androidpublisher", "v3", credentials=creds, cache_discovery=False)
    edit_id = publisher.edits().insert(packageName=package, body={}).execute()["id"]
    print(f"edit {edit_id}")

    uploaded = (
        publisher.edits()
        .bundles()
        .upload(
            packageName=package,
            editId=edit_id,
            media_body=MediaFileUpload(aab, mimetype="application/octet-stream", resumable=True),
        )
        .execute()
    )
    version_code = str(uploaded["versionCode"])
    print(f"uploaded versionCode={version_code}")

    release = {
        "status": status,
        "versionCodes": [version_code],
    }
    if name:
        release["name"] = name

    publisher.edits().tracks().update(
        packageName=package,
        editId=edit_id,
        track=track,
        body={"track": track, "releases": [release]},
    ).execute()
    print(f"assigned {track} status={status}")

    # Do not pass changesNotSentForReview — Play forbids it when review is automatic.
    committed = publisher.edits().commit(packageName=package, editId=edit_id).execute()
    print(f"committed edit {committed.get('id', edit_id)}")


if __name__ == "__main__":
    main()
