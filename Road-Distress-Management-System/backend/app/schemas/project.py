"""Pydantic schemas for the Project entity."""

from datetime import datetime
from typing import Optional, List
from pydantic import BaseModel, ConfigDict, Field


class ProjectBase(BaseModel):
    name: str = Field(..., max_length=255)
    description: Optional[str] = Field(None, max_length=2000)
    highway_name: Optional[str] = Field(None, max_length=255)
    highway_number: Optional[str] = Field(None, max_length=50)
    starting_chainage: Optional[str] = Field(None, max_length=50)
    ending_chainage: Optional[str] = Field(None, max_length=50)
    state: Optional[str] = Field(None, max_length=100)


class ProjectCreate(ProjectBase):
    member_emails: List[str] = Field(default_factory=list, description="Employees to assign to this project")


class ProjectResponse(ProjectBase):
    id: int
    owner_id: int
    created_at: datetime
    updated_at: datetime
    member_emails: List[str] = Field(default_factory=list)

    model_config = ConfigDict(from_attributes=True)
