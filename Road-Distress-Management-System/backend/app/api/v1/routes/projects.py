"""
Project routes. Every module (M1 Crack Detection, M2 Road Safety Audit, M3
Asset Management, M4 Predictive Analysis) operates within a Project -- this
is the "Choose what they want" homepage's data source, scoped by role
(Admin sees everything, Employee sees only projects they're assigned to).
"""

from typing import List
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.core.deps import get_current_user
from app.models.user import User
from app.schemas.project import ProjectCreate, ProjectResponse
from app.crud.project import (
    get_visible_projects,
    get_project,
    create_project,
    user_can_access_project,
    to_response_dict,
)

router = APIRouter()


@router.get("/", response_model=List[ProjectResponse])
def list_projects(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> List[ProjectResponse]:
    projects = get_visible_projects(db, user)
    return [to_response_dict(db, p) for p in projects]


@router.post("/", response_model=ProjectResponse, status_code=status.HTTP_201_CREATED)
def create_project_route(
    project_in: ProjectCreate,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> ProjectResponse:
    project = create_project(db, project_in, owner=user)
    return to_response_dict(db, project)


@router.get("/{project_id}", response_model=ProjectResponse)
def get_project_route(
    project_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> ProjectResponse:
    project = get_project(db, project_id)
    if project is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Project not found")
    if not user_can_access_project(db, user, project):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "You don't have access to this project")
    return to_response_dict(db, project)
