#!/usr/bin/env bash
set -euo pipefail

TEAM_ID="${TEAM_ID:-3SF92B92JF}"
CONTAINER_ID="${CONTAINER_ID:-iCloud.com.leeberty.CoupleCalendar}"
ENVIRONMENT="${1:-development}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEMA_FILE="${SCHEMA_FILE:-$ROOT_DIR/CloudKit/ShareCalSchema.ckdb}"

if [[ "$ENVIRONMENT" != "development" && "$ENVIRONMENT" != "production" ]]; then
  echo "Usage: $0 [development|production]" >&2
  exit 64
fi

if [[ "$ENVIRONMENT" == "production" ]]; then
  {
    echo "cktool import-schema cannot import directly into the Production environment."
    echo "Import the Development schema first:"
    echo "  $0 development"
    echo "Then open CloudKit Console > Development > Deploy Schema Changes... to deploy to Production."
  } >&2
  exit 64
fi

if [[ ! -f "$SCHEMA_FILE" ]]; then
  echo "CloudKit schema file not found: $SCHEMA_FILE" >&2
  exit 66
fi

schema_block() {
  local record_type="$1"
  awk -v record_type="$record_type" '
    $0 ~ "^[[:space:]]*RECORD TYPE " record_type "[[:space:]]*\\(" {
      in_record = 1
      next
    }
    in_record && $0 ~ "^[[:space:]]*\\);" {
      exit
    }
    in_record {
      print
    }
  ' "$SCHEMA_FILE"
}

require_schema_field() {
  local record_type="$1"
  local field_name="$2"
  local block
  block="$(schema_block "$record_type")"

  if [[ -z "$block" ]]; then
    echo "CloudKit schema is missing record type: $record_type" >&2
    exit 65
  fi

  if ! grep -Eq "^[[:space:]]*\"?${field_name}\"?[[:space:]]+" <<<"$block"; then
    echo "CloudKit schema is missing $record_type.$field_name" >&2
    exit 65
  fi
}

for field in ___recordID schemaVersion createdAt ownerMemberID pairingID; do
  require_schema_field "CoupleSpace" "$field"
done

for field in ___recordID ownerMemberID mirrorKey sourceCalendarID sourceCalendarTitle occurrenceStartDate startDate endDate isAllDay timeZoneIdentifier title location notes urlString calendarColorHex visibilityRawValue deletedAt; do
  require_schema_field "EventMirror" "$field"
done

for field in ___recordID creatorMemberID inviteeMemberID title startDate endDate isAllDay location notes statusRawValue createdAt updatedAt createdLocalEventID; do
  require_schema_field "EventInvitation" "$field"
done

for field in ___recordID requesterMemberID ownerMemberID requestedStartDate requestedEndDate statusRawValue createdAt updatedAt; do
  require_schema_field "CalendarAccessRequest" "$field"
done

for field in ___recordID ownerMemberID pairingID displayName updatedAt; do
  require_schema_field "MemberProfile" "$field"
done

for field in ___recordID eventMirrorID authorMemberID body createdAt editedAt deletedAt isRead; do
  require_schema_field "EventComment" "$field"
done

for field in ___recordID cloudkit.thumbnailImageData cloudkit.title cloudkit.type; do
  require_schema_field '"cloudkit.share"' "$field"
done

set +e
output="$(xcrun cktool import-schema \
  --team-id "$TEAM_ID" \
  --container-id "$CONTAINER_ID" \
  --environment "$ENVIRONMENT" \
  --validate \
  --file "$SCHEMA_FILE" 2>&1)"
status=$?
set -e

if [[ $status -ne 0 ]]; then
  echo "$output" >&2
  if [[ "$output" == *"No management token found"* ]]; then
    echo >&2
    echo "CloudKit schema import requires a management token for team $TEAM_ID." >&2
    echo "Save one with:" >&2
    echo "  xcrun cktool save-token --type management --method keychain" >&2
    echo "or run with CLOUDKIT_MANAGEMENT_TOKEN set, then retry:" >&2
    echo "  $0 $ENVIRONMENT" >&2
  fi
  exit "$status"
fi

echo "$output"
