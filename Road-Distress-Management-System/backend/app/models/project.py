"""
Project database models for the multi-module platform extension.

A Project is the top-level container a survey/audit/etc. happens under --
everything from M1 (Crack Detection) onward operates within a Project. Admin
users see all projects; Employee users only see projects they're a member of
(via ProjectMember), matching "Admin sees everything, User sees the portion
they work under" from the workflow design.
"""

from datetime import datetime
from typing import List, Optional, TYPE_CHECKING
from sqlalchemy import String, DateTime, ForeignKey, UniqueConstraint
from sqlalchemy.sql import func
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.db.database import Base

if TYPE_CHECKING:
    from app.models.user import User


class Project(Base):
    __tablename__ = "projects"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    description: Mapped[Optional[str]] = mapped_column(String(2000), nullable=True)

    # Survey/road metadata -- mirrors the fields already shown on the
    # existing Mission Setup (Survey) screen, now attached to a persistent
    # Project rather than being a one-off, unsaved form.
    highway_name: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    highway_number: Mapped[Optional[str]] = mapped_column(String(50), nullable=True)
    starting_chainage: Mapped[Optional[str]] = mapped_column(String(50), nullable=True)
    ending_chainage: Mapped[Optional[str]] = mapped_column(String(50), nullable=True)
    state: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)

    owner_id: Mapped[int] = mapped_column(ForeignKey("users.id"), nullable=False)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )

    owner: Mapped["User"] = relationship("User", foreign_keys=[owner_id])
    members: Mapped[List["ProjectMember"]] = relationship(
        "ProjectMember", back_populates="project", cascade="all, delete-orphan"
    )


class ProjectMember(Base):
    """Which employees are assigned to (and therefore can see) a Project."""
    __tablename__ = "project_members"
    __table_args__ = (UniqueConstraint("project_id", "user_id", name="uq_project_member"),)

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    project_id: Mapped[int] = mapped_column(ForeignKey("projects.id"), nullable=False)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), nullable=False)
    added_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    project: Mapped["Project"] = relationship("Project", back_populates="members")
    user: Mapped["User"] = relationship("User")
