"""
Road Safety Audit (M2) database models.

A SafetyAudit is a checklist-driven inspection drive within a Project's
chainage range -- distinct from M1's AI crack/pothole detection. Findings
are logged as AuditChecklistItem rows tagged with the chainage they were
observed at; AuditAudioClip rows hold the surveyor's spoken commentary
(raw audio + transcript) recorded during the same drive. Both feed the
two M2 report views: the chainage-wise report and the audio report.
"""

from datetime import datetime
from typing import List, Optional, TYPE_CHECKING
from sqlalchemy import String, DateTime, ForeignKey, Float, Text
from sqlalchemy.sql import func
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.db.database import Base

if TYPE_CHECKING:
    from app.models.user import User
    from app.models.project import Project

AUDIT_CATEGORIES = (
    "signage",
    "road_markings",
    "guardrail",
    "lighting",
    "sight_distance",
    "junction",
    "pedestrian",
    "other",
)
AUDIT_SEVERITIES = ("low", "medium", "high", "critical")


class SafetyAudit(Base):
    __tablename__ = "safety_audits"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    project_id: Mapped[int] = mapped_column(ForeignKey("projects.id"), nullable=False)
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    status: Mapped[str] = mapped_column(String(20), default="in_progress", nullable=False)
    created_by_id: Mapped[int] = mapped_column(ForeignKey("users.id"), nullable=False)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )

    project: Mapped["Project"] = relationship("Project")
    created_by: Mapped["User"] = relationship("User")
    checklist_items: Mapped[List["AuditChecklistItem"]] = relationship(
        "AuditChecklistItem", back_populates="audit", cascade="all, delete-orphan"
    )
    audio_clips: Mapped[List["AuditAudioClip"]] = relationship(
        "AuditAudioClip", back_populates="audit", cascade="all, delete-orphan"
    )


class AuditChecklistItem(Base):
    """A single safety-audit finding (signage, markings, guardrail, ...)
    tagged with the chainage (in km) it was observed at."""
    __tablename__ = "audit_checklist_items"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    audit_id: Mapped[int] = mapped_column(ForeignKey("safety_audits.id"), nullable=False)
    chainage_km: Mapped[float] = mapped_column(Float, nullable=False)
    category: Mapped[str] = mapped_column(String(30), nullable=False)
    severity: Mapped[str] = mapped_column(String(20), default="medium", nullable=False)
    description: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    audit: Mapped["SafetyAudit"] = relationship("SafetyAudit", back_populates="checklist_items")


class AuditAudioClip(Base):
    """Spoken commentary recorded during the audit drive. `transcript` is
    filled in asynchronously by app/services/transcription_service.py."""
    __tablename__ = "audit_audio_clips"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    audit_id: Mapped[int] = mapped_column(ForeignKey("safety_audits.id"), nullable=False)
    chainage_km: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    filename: Mapped[str] = mapped_column(String(255), nullable=False)
    filepath: Mapped[str] = mapped_column(String(512), nullable=False)
    transcript: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    transcript_status: Mapped[str] = mapped_column(String(20), default="pending", nullable=False)
    duration_seconds: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    audit: Mapped["SafetyAudit"] = relationship("SafetyAudit", back_populates="audio_clips")
