"""Pydantic schemas for the M2 Road Safety Audit entities."""

from datetime import datetime
from typing import Dict, List, Optional
from pydantic import BaseModel, ConfigDict, Field


class SafetyAuditCreate(BaseModel):
    title: str = Field(..., max_length=255)


class SafetyAuditResponse(BaseModel):
    id: int
    project_id: int
    title: str
    status: str
    created_by_id: int
    created_at: datetime
    updated_at: datetime
    checklist_item_count: int = 0
    audio_clip_count: int = 0

    model_config = ConfigDict(from_attributes=True)


class AuditChecklistItemCreate(BaseModel):
    chainage_km: float
    category: str = Field(..., max_length=30)
    severity: str = Field("medium", max_length=20)
    description: str = Field(..., max_length=2000)


class AuditChecklistItemResponse(BaseModel):
    id: int
    audit_id: int
    chainage_km: float
    category: str
    severity: str
    description: str
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class AuditAudioClipResponse(BaseModel):
    id: int
    audit_id: int
    chainage_km: Optional[float]
    filename: str
    url: str
    transcript: Optional[str]
    transcript_status: str
    duration_seconds: Optional[float]
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class ChainageReportBucket(BaseModel):
    start_km: float
    end_km: float
    severity_counts: Dict[str, int]
    items: List[AuditChecklistItemResponse]


class ChainageReportResponse(BaseModel):
    audit: SafetyAuditResponse
    interval_km: float
    buckets: List[ChainageReportBucket]


class AudioReportResponse(BaseModel):
    audit: SafetyAuditResponse
    clips: List[AuditAudioClipResponse]
