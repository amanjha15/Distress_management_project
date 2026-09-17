"""Pydantic schemas for the M3 Asset Management ProjectAsset entity."""

from datetime import datetime
from typing import Optional
from pydantic import BaseModel, ConfigDict


class ProjectAssetResponse(BaseModel):
    id: int
    project_id: int
    uploaded_by_id: int
    filename: str
    url: str
    content_type: Optional[str]
    file_size: int
    category: str
    description: Optional[str]
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)
