"""
Audio upload handling for M2 Road Safety Audit clips. Mirrors
app/services/video.py's chunked-write/sanitize-filename pattern.
"""

import os
import re
import uuid
import logging
from typing import Optional
from fastapi import UploadFile, HTTPException, status
from sqlalchemy.orm import Session

from app.models.audit import AuditAudioClip
from app.crud.audit import create_audio_clip, get_audio_clip, delete_audio_clip

logger = logging.getLogger(__name__)

MAX_FILE_SIZE_BYTES = 100 * 1024 * 1024  # 100MB -- audio commentary, not video

BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
UPLOAD_DIR = os.path.join(BASE_DIR, "uploads", "audio")
os.makedirs(UPLOAD_DIR, exist_ok=True)

ALLOWED_EXTENSIONS = {".mp3", ".wav", ".m4a", ".aac", ".ogg", ".webm"}


def _sanitize_filename(filename: str) -> str:
    base = os.path.basename(filename)
    sanitized = re.sub(r"[^a-zA-Z0-9_\.\-]", "_", base)
    if not sanitized or sanitized.startswith("."):
        sanitized = f"audio_{uuid.uuid4().hex[:8]}" + os.path.splitext(base)[1]
    return sanitized


async def handle_audio_upload(
    db: Session,
    audit_id: int,
    file: UploadFile,
    chainage_km: Optional[float],
) -> AuditAudioClip:
    original_filename = file.filename or "commentary.webm"
    ext = os.path.splitext(original_filename)[1].lower()
    if ext not in ALLOWED_EXTENSIONS:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            f"Invalid audio format. Supported formats: {', '.join(sorted(ALLOWED_EXTENSIONS))}",
        )

    sanitized = _sanitize_filename(original_filename)
    unique_filename = f"{uuid.uuid4().hex}_{sanitized}"
    target_filepath = os.path.join(UPLOAD_DIR, unique_filename)
    os.makedirs(UPLOAD_DIR, exist_ok=True)

    total_bytes = 0
    try:
        with open(target_filepath, "wb") as buffer:
            while True:
                chunk = await file.read(1024 * 1024)
                if not chunk:
                    break
                total_bytes += len(chunk)
                if total_bytes > MAX_FILE_SIZE_BYTES:
                    buffer.close()
                    if os.path.exists(target_filepath):
                        os.remove(target_filepath)
                    raise HTTPException(
                        status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                        "Audio file exceeds maximum size limit of 100MB.",
                    )
                buffer.write(chunk)
    except HTTPException:
        raise
    except Exception as e:
        if os.path.exists(target_filepath):
            os.remove(target_filepath)
        logger.error(f"Failed to write audio file to disk: {e}")
        raise HTTPException(
            status.HTTP_500_INTERNAL_SERVER_ERROR,
            f"Could not save audio file to server disk: {str(e)}",
        )

    relative_filepath = os.path.relpath(target_filepath, BASE_DIR).replace("\\", "/")

    try:
        return create_audio_clip(
            db,
            audit_id=audit_id,
            filename=original_filename,
            filepath=relative_filepath,
            chainage_km=chainage_km,
        )
    except Exception as e:
        if os.path.exists(target_filepath):
            os.remove(target_filepath)
        logger.error(f"Database insertion failed for audio clip: {e}")
        raise HTTPException(
            status.HTTP_500_INTERNAL_SERVER_ERROR,
            "Failed to register audio clip metadata in the database.",
        )


def remove_audio_clip(db: Session, clip_id: int) -> None:
    """Deletes the audio clip's DB row and removes its physical file from disk."""
    clip = get_audio_clip(db, clip_id)
    if clip is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, f"Audio clip with ID {clip_id} not found.")

    delete_audio_clip(db, clip_id)

    if clip.filepath:
        full_path = os.path.join(BASE_DIR, clip.filepath)
        if os.path.exists(full_path):
            try:
                os.remove(full_path)
            except Exception as e:
                logger.error(f"Failed to delete audio file {full_path} from disk: {e}")
        else:
            logger.warning(f"Audio file not found on disk during deletion: {full_path}")
