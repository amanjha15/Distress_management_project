"""
Document upload handling for M3 Asset Management -- reports, drawings,
photos and other project files kept alongside a Project for reuse across
modules. Mirrors app/services/audit.py's chunked-write pattern.
"""

import os
import re
import uuid
import logging
from typing import Optional
from fastapi import UploadFile, HTTPException, status
from sqlalchemy.orm import Session

from app.models.asset import ProjectAsset
from app.crud.asset import create_asset, get_asset, delete_asset

logger = logging.getLogger(__name__)

MAX_FILE_SIZE_BYTES = 200 * 1024 * 1024  # 200MB -- scanned drawings/reports can be sizeable

BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
UPLOAD_DIR = os.path.join(BASE_DIR, "uploads", "assets")
os.makedirs(UPLOAD_DIR, exist_ok=True)

ALLOWED_EXTENSIONS = {
    ".pdf", ".doc", ".docx", ".xls", ".xlsx", ".csv",
    ".png", ".jpg", ".jpeg", ".txt",
}


def _sanitize_filename(filename: str) -> str:
    base = os.path.basename(filename)
    sanitized = re.sub(r"[^a-zA-Z0-9_\.\-]", "_", base)
    if not sanitized or sanitized.startswith("."):
        sanitized = f"asset_{uuid.uuid4().hex[:8]}" + os.path.splitext(base)[1]
    return sanitized


async def handle_asset_upload(
    db: Session,
    project_id: int,
    uploaded_by_id: int,
    file: UploadFile,
    category: str,
    description: Optional[str],
) -> ProjectAsset:
    original_filename = file.filename or "document"
    ext = os.path.splitext(original_filename)[1].lower()
    if ext not in ALLOWED_EXTENSIONS:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            f"Invalid document format. Supported formats: {', '.join(sorted(ALLOWED_EXTENSIONS))}",
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
                        "Document exceeds maximum size limit of 200MB.",
                    )
                buffer.write(chunk)
    except HTTPException:
        raise
    except Exception as e:
        if os.path.exists(target_filepath):
            os.remove(target_filepath)
        logger.error(f"Failed to write asset file to disk: {e}")
        raise HTTPException(
            status.HTTP_500_INTERNAL_SERVER_ERROR,
            f"Could not save document to server disk: {str(e)}",
        )

    relative_filepath = os.path.relpath(target_filepath, BASE_DIR).replace("\\", "/")

    try:
        return create_asset(
            db,
            project_id=project_id,
            uploaded_by_id=uploaded_by_id,
            filename=original_filename,
            filepath=relative_filepath,
            content_type=file.content_type,
            file_size=total_bytes,
            category=category,
            description=description,
        )
    except Exception as e:
        if os.path.exists(target_filepath):
            os.remove(target_filepath)
        logger.error(f"Database insertion failed for asset: {e}")
        raise HTTPException(
            status.HTTP_500_INTERNAL_SERVER_ERROR,
            "Failed to register document metadata in the database.",
        )


def remove_asset(db: Session, asset_id: int) -> None:
    """Deletes the asset's DB row and removes its physical file from disk."""
    asset = get_asset(db, asset_id)
    if asset is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, f"Document with ID {asset_id} not found.")

    delete_asset(db, asset_id)

    if asset.filepath:
        full_path = os.path.join(BASE_DIR, asset.filepath)
        if os.path.exists(full_path):
            try:
                os.remove(full_path)
            except Exception as e:
                logger.error(f"Failed to delete asset file {full_path} from disk: {e}")
        else:
            logger.warning(f"Asset file not found on disk during deletion: {full_path}")
