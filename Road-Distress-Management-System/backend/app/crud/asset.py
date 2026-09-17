"""CRUD operations for the M3 Asset Management ProjectAsset entity."""

from typing import List, Optional
from sqlalchemy.orm import Session
from app.models.asset import ProjectAsset


def create_asset(
    db: Session,
    project_id: int,
    uploaded_by_id: int,
    filename: str,
    filepath: str,
    content_type: Optional[str],
    file_size: int,
    category: str,
    description: Optional[str],
) -> ProjectAsset:
    asset = ProjectAsset(
        project_id=project_id,
        uploaded_by_id=uploaded_by_id,
        filename=filename,
        filepath=filepath,
        content_type=content_type,
        file_size=file_size,
        category=category,
        description=description,
    )
    db.add(asset)
    db.commit()
    db.refresh(asset)
    return asset


def list_assets_for_project(db: Session, project_id: int) -> List[ProjectAsset]:
    return (
        db.query(ProjectAsset)
        .filter(ProjectAsset.project_id == project_id)
        .order_by(ProjectAsset.id.desc())
        .all()
    )


def get_asset(db: Session, asset_id: int) -> Optional[ProjectAsset]:
    return db.get(ProjectAsset, asset_id)


def delete_asset(db: Session, asset_id: int) -> None:
    asset = db.get(ProjectAsset, asset_id)
    if asset is None:
        return
    db.delete(asset)
    db.commit()
