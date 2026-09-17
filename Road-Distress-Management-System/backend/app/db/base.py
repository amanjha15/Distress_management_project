"""
Unified base imports directory.
Imports Base and all SQLAlchemy models to ensure metadata registration.
"""

from app.db.database import Base  # noqa
from app.models.user import User  # noqa
from app.models.distress import RoadDistress  # noqa
from app.models.video import UploadedVideo  # noqa
from app.models.maintenance import MaintenanceTask  # noqa
from app.models.report import Report  # noqa
from app.models.project import Project, ProjectMember  # noqa
from app.models.auth import OtpCode, AuthToken  # noqa
from app.models.audit import SafetyAudit, AuditChecklistItem, AuditAudioClip  # noqa
from app.models.asset import ProjectAsset  # noqa
