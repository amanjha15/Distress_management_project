"""Chainage-wise report generation for M2 Road Safety Audits -- the
"completely different from the Excel report" output the workflow asked for:
findings bucketed into fixed-interval chainage segments along the project's
highway range, rather than a flat detection log."""

import re
from typing import List, Optional
from sqlalchemy.orm import Session

from app.models.audit import SafetyAudit, AUDIT_SEVERITIES
from app.crud.audit import list_checklist_items
from app.schemas.audit import ChainageReportBucket, AuditChecklistItemResponse

DEFAULT_INTERVAL_KM = 0.5
MAX_BUCKETS = 500


def parse_chainage(value: Optional[str]) -> Optional[float]:
    """Parses "Km 118+250" / "118.25" style chainage strings into km floats
    -- mirrors the mobile app's Survey screen `_parseChainage`."""
    if not value:
        return None
    cleaned = re.sub(r"[^0-9+.]", "", value.lower())
    if not cleaned:
        return None
    if "+" in cleaned:
        parts = cleaned.split("+")
        if len(parts) != 2:
            return None
        try:
            km = float(parts[0]) if parts[0] else 0.0
            m = float(parts[1]) if parts[1] else 0.0
            return km + m / 1000
        except ValueError:
            return None
    try:
        return float(cleaned)
    except ValueError:
        return None


def build_chainage_buckets(
    db: Session, audit: SafetyAudit, interval_km: float = DEFAULT_INTERVAL_KM
) -> List[ChainageReportBucket]:
    items = list_checklist_items(db, audit.id)

    project = audit.project
    start_km = parse_chainage(project.starting_chainage) if project else None
    end_km = parse_chainage(project.ending_chainage) if project else None

    if start_km is None or end_km is None or end_km <= start_km:
        # Fall back to the observed range of logged findings when the
        # project's chainage fields are missing or unparseable.
        if items:
            start_km = min(i.chainage_km for i in items)
            end_km = max(i.chainage_km for i in items) + interval_km
        else:
            start_km, end_km = 0.0, interval_km

    buckets: List[ChainageReportBucket] = []
    cursor = start_km
    while cursor < end_km and len(buckets) < MAX_BUCKETS:
        bucket_end = min(cursor + interval_km, end_km)
        is_last = bucket_end >= end_km
        bucket_items = [
            i for i in items
            if cursor <= i.chainage_km < bucket_end or (is_last and i.chainage_km == bucket_end)
        ]
        severity_counts = {s: 0 for s in AUDIT_SEVERITIES}
        for i in bucket_items:
            severity_counts[i.severity] = severity_counts.get(i.severity, 0) + 1
        buckets.append(
            ChainageReportBucket(
                start_km=round(cursor, 3),
                end_km=round(bucket_end, 3),
                severity_counts=severity_counts,
                items=[AuditChecklistItemResponse.model_validate(i) for i in bucket_items],
            )
        )
        cursor = bucket_end

    return buckets
