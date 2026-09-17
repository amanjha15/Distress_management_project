"""
M3 Asset Management routes -- document/report/drawing attachments tied to
a Project, so generated reports and other files can be managed and reused
across modules. Scoped by the same Admin/Employee project access rule as
/projects (see app/crud/project.py's user_can_access_project).
"""

from typing import List, Optional
from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, status
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.core.deps import get_current_user
from app.models.user import User
from app.crud.project import get_project, user_can_access_project
from app.crud.asset import list_assets_for_project, get_asset
from app.schemas.asset import ProjectAssetResponse
from app.services.asset import handle_asset_upload, remove_asset

router = APIRouter()


def _asset_response(asset) -> ProjectAssetResponse:
    return ProjectAssetResponse(
        id=asset.id,
        project_id=asset.project_id,
        uploaded_by_id=asset.uploaded_by_id,
        filename=asset.filename,
        url=f"/{asset.filepath}",
        content_type=asset.content_type,
        file_size=asset.file_size,
        category=asset.category,
        description=asset.description,
        created_at=asset.created_at,
    )


def _require_project_access(db: Session, project_id: int, user: User):
    project = get_project(db, project_id)
    if project is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Project not found")
    if not user_can_access_project(db, user, project):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "You don't have access to this project")
    return project


@router.get("/", response_model=List[ProjectAssetResponse])
def list_assets_route(
    project_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> List[ProjectAssetResponse]:
    _require_project_access(db, project_id, user)
    return [_asset_response(a) for a in list_assets_for_project(db, project_id)]


@router.post("/", response_model=ProjectAssetResponse, status_code=status.HTTP_201_CREATED)
async def upload_asset_route(
    project_id: int,
    file: UploadFile = File(...),
    category: str = Form("other"),
    description: Optional[str] = Form(None),
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> ProjectAssetResponse:
    _require_project_access(db, project_id, user)
    asset = await handle_asset_upload(
        db,
        project_id=project_id,
        uploaded_by_id=user.id,
        file=file,
        category=category,
        description=description,
    )
    return _asset_response(asset)


@router.delete("/{asset_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_asset_route(
    asset_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> None:
    asset = get_asset(db, asset_id)
    if asset is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Document not found")
    _require_project_access(db, asset.project_id, user)
    remove_asset(db, asset_id)
