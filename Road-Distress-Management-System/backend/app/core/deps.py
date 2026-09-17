"""
Auth dependencies: resolve the current user from a Bearer session token
(issued by /auth/verify-otp), and gate admin-only routes.
"""

from fastapi import Depends, Header, HTTPException, status
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models.user import User
from app.services.otp_service import resolve_token


def get_current_user(
    authorization: str | None = Header(default=None),
    db: Session = Depends(get_db),
) -> User:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Not authenticated")
    token = authorization.split(" ", 1)[1].strip()
    user_id = resolve_token(db, token)
    if user_id is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Session expired or invalid, please log in again")
    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "User no longer exists")
    return user


def require_admin(user: User = Depends(get_current_user)) -> User:
    if user.role != "admin":
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Admin access required")
    return user
