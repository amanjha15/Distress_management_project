"""
M2 Road Safety Audit routes -- checklist findings + audio commentary tied to
a Project, plus the two report views (chainage-wise, audio). Every route is
scoped by the same Admin/Employee project access rule as /projects (see
app/crud/project.py's user_can_access_project).
"""

from typing import List, Optional
from fastapi import APIRouter, BackgroundTasks, Depends, File, Form, HTTPException, UploadFile, status
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.core.deps import get_current_user
from app.models.user import User
from app.crud.project import get_project, user_can_access_project
from app.crud.audit import (
    get_audit,
    list_audits_for_project,
    create_audit,
    create_checklist_item,
    list_checklist_items,
    list_audio_clips,
    get_audio_clip,
    checklist_count,
    audio_count,
)
from app.schemas.audit import (
    SafetyAuditCreate,
    SafetyAuditResponse,
    AuditChecklistItemCreate,
    AuditChecklistItemResponse,
    AuditAudioClipResponse,
    ChainageReportResponse,
    AudioReportResponse,
)
from app.services.audit import handle_audio_upload, remove_audio_clip
from app.services.audit_report import build_chainage_buckets, DEFAULT_INTERVAL_KM
from app.services.transcription_service import run_transcription_job

router = APIRouter()


def _audit_response(db: Session, audit) -> SafetyAuditResponse:
    return SafetyAuditResponse(
        id=audit.id,
        project_id=audit.project_id,
        title=audit.title,
        status=audit.status,
        created_by_id=audit.created_by_id,
        created_at=audit.created_at,
        updated_at=audit.updated_at,
        checklist_item_count=checklist_count(db, audit.id),
        audio_clip_count=audio_count(db, audit.id),
    )


def _audio_clip_response(clip) -> AuditAudioClipResponse:
    return AuditAudioClipResponse(
        id=clip.id,
        audit_id=clip.audit_id,
        chainage_km=clip.chainage_km,
        filename=clip.filename,
        url=f"/{clip.filepath}",
        transcript=clip.transcript,
        transcript_status=clip.transcript_status,
        duration_seconds=clip.duration_seconds,
        created_at=clip.created_at,
    )


def _require_project_access(db: Session, project_id: int, user: User):
    project = get_project(db, project_id)
    if project is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Project not found")
    if not user_can_access_project(db, user, project):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "You don't have access to this project")
    return project


def _require_audit_access(db: Session, audit_id: int, user: User):
    audit = get_audit(db, audit_id)
    if audit is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Audit not found")
    if not user_can_access_project(db, user, audit.project):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "You don't have access to this audit")
    return audit


@router.get("/", response_model=List[SafetyAuditResponse])
def list_audits(
    project_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> List[SafetyAuditResponse]:
    _require_project_access(db, project_id, user)
    audits = list_audits_for_project(db, project_id)
    return [_audit_response(db, a) for a in audits]


@router.post("/", response_model=SafetyAuditResponse, status_code=status.HTTP_201_CREATED)
def create_audit_route(
    project_id: int,
    audit_in: SafetyAuditCreate,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> SafetyAuditResponse:
    _require_project_access(db, project_id, user)
    audit = create_audit(db, project_id=project_id, title=audit_in.title, created_by=user)
    return _audit_response(db, audit)


@router.get("/{audit_id}", response_model=SafetyAuditResponse)
def get_audit_route(
    audit_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> SafetyAuditResponse:
    audit = _require_audit_access(db, audit_id, user)
    return _audit_response(db, audit)


@router.get("/{audit_id}/checklist-items", response_model=List[AuditChecklistItemResponse])
def list_checklist_items_route(
    audit_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> List[AuditChecklistItemResponse]:
    _require_audit_access(db, audit_id, user)
    return list_checklist_items(db, audit_id)


@router.post(
    "/{audit_id}/checklist-items",
    response_model=AuditChecklistItemResponse,
    status_code=status.HTTP_201_CREATED,
)
def create_checklist_item_route(
    audit_id: int,
    item_in: AuditChecklistItemCreate,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> AuditChecklistItemResponse:
    _require_audit_access(db, audit_id, user)
    return create_checklist_item(db, audit_id, item_in)


@router.get("/{audit_id}/audio", response_model=List[AuditAudioClipResponse])
def list_audio_route(
    audit_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> List[AuditAudioClipResponse]:
    _require_audit_access(db, audit_id, user)
    return [_audio_clip_response(c) for c in list_audio_clips(db, audit_id)]


@router.post(
    "/{audit_id}/audio",
    response_model=AuditAudioClipResponse,
    status_code=status.HTTP_201_CREATED,
)
async def upload_audio_route(
    audit_id: int,
    background_tasks: BackgroundTasks,
    file: UploadFile = File(...),
    chainage_km: Optional[float] = Form(None),
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> AuditAudioClipResponse:
    _require_audit_access(db, audit_id, user)
    clip = await handle_audio_upload(db, audit_id=audit_id, file=file, chainage_km=chainage_km)
    background_tasks.add_task(run_transcription_job, clip.id)
    return _audio_clip_response(clip)


@router.delete("/{audit_id}/audio/{clip_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_audio_route(
    audit_id: int,
    clip_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> None:
    _require_audit_access(db, audit_id, user)
    clip = get_audio_clip(db, clip_id)
    if clip is None or clip.audit_id != audit_id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Audio clip not found")
    remove_audio_clip(db, clip_id)


@router.get("/{audit_id}/report/chainage", response_model=ChainageReportResponse)
def chainage_report_route(
    audit_id: int,
    interval_km: float = DEFAULT_INTERVAL_KM,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> ChainageReportResponse:
    audit = _require_audit_access(db, audit_id, user)
    buckets = build_chainage_buckets(db, audit, interval_km=interval_km)
    return ChainageReportResponse(audit=_audit_response(db, audit), interval_km=interval_km, buckets=buckets)


@router.get("/{audit_id}/report/audio", response_model=AudioReportResponse)
def audio_report_route(
    audit_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> AudioReportResponse:
    audit = _require_audit_access(db, audit_id, user)
    clips = [_audio_clip_response(c) for c in list_audio_clips(db, audit_id)]
    return AudioReportResponse(audit=_audit_response(db, audit), clips=clips)
