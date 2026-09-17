"""CRUD operations for the M2 Road Safety Audit entities."""

from typing import List, Optional
from sqlalchemy.orm import Session
from app.models.audit import SafetyAudit, AuditChecklistItem, AuditAudioClip
from app.models.user import User
from app.schemas.audit import AuditChecklistItemCreate


def get_audit(db: Session, audit_id: int) -> Optional[SafetyAudit]:
    return db.get(SafetyAudit, audit_id)


def list_audits_for_project(db: Session, project_id: int) -> List[SafetyAudit]:
    return (
        db.query(SafetyAudit)
        .filter(SafetyAudit.project_id == project_id)
        .order_by(SafetyAudit.id.desc())
        .all()
    )


def create_audit(db: Session, project_id: int, title: str, created_by: User) -> SafetyAudit:
    audit = SafetyAudit(project_id=project_id, title=title, created_by_id=created_by.id)
    db.add(audit)
    db.commit()
    db.refresh(audit)
    return audit


def create_checklist_item(db: Session, audit_id: int, item_in: AuditChecklistItemCreate) -> AuditChecklistItem:
    item = AuditChecklistItem(
        audit_id=audit_id,
        chainage_km=item_in.chainage_km,
        category=item_in.category,
        severity=item_in.severity,
        description=item_in.description,
    )
    db.add(item)
    db.commit()
    db.refresh(item)
    return item


def list_checklist_items(db: Session, audit_id: int) -> List[AuditChecklistItem]:
    return (
        db.query(AuditChecklistItem)
        .filter(AuditChecklistItem.audit_id == audit_id)
        .order_by(AuditChecklistItem.chainage_km.asc())
        .all()
    )


def create_audio_clip(
    db: Session,
    audit_id: int,
    filename: str,
    filepath: str,
    chainage_km: Optional[float],
) -> AuditAudioClip:
    clip = AuditAudioClip(
        audit_id=audit_id,
        filename=filename,
        filepath=filepath,
        chainage_km=chainage_km,
        transcript_status="pending",
    )
    db.add(clip)
    db.commit()
    db.refresh(clip)
    return clip


def list_audio_clips(db: Session, audit_id: int) -> List[AuditAudioClip]:
    return (
        db.query(AuditAudioClip)
        .filter(AuditAudioClip.audit_id == audit_id)
        .order_by(AuditAudioClip.id.asc())
        .all()
    )


def get_audio_clip(db: Session, clip_id: int) -> Optional[AuditAudioClip]:
    return db.get(AuditAudioClip, clip_id)


def update_audio_transcript(db: Session, clip_id: int, transcript: Optional[str], status: str) -> None:
    clip = db.get(AuditAudioClip, clip_id)
    if clip is None:
        return
    clip.transcript = transcript
    clip.transcript_status = status
    db.commit()


def delete_audio_clip(db: Session, clip_id: int) -> None:
    clip = db.get(AuditAudioClip, clip_id)
    if clip is None:
        return
    db.delete(clip)
    db.commit()


def checklist_count(db: Session, audit_id: int) -> int:
    return db.query(AuditChecklistItem).filter(AuditChecklistItem.audit_id == audit_id).count()


def audio_count(db: Session, audit_id: int) -> int:
    return db.query(AuditAudioClip).filter(AuditAudioClip.audit_id == audit_id).count()
