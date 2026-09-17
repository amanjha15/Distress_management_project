"""
Authentication routes for the Road Distress Management System.

Real Email + OTP login (request-otp / verify-otp) is what the frontend
actually uses now, replacing the old hardcoded mock login. The original
password-based /login and /register are kept as-is (register is still how
an account gets created in the first place; OTP only handles the *login*
step for an existing account, per the "Login [Email + OTP]" design -- it
doesn't auto-create accounts for arbitrary emails).
"""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from pydantic import BaseModel
from app.db.session import get_db
from app.crud.user import get_user_by_email, create_user
from app.schemas.user import UserResponse, UserCreate
from app.core.security import verify_password
from app.core.deps import get_current_user
from app.models.user import User
from app.services.otp_service import request_otp, verify_otp, issue_token, OTP_DEV_MODE

router = APIRouter()


class LoginRequest(BaseModel):
    """
    Request model for user authentication.
    """
    email: str
    password: str


@router.post("/login", response_model=UserResponse)
def login(request: LoginRequest, db: Session = Depends(get_db)) -> UserResponse:
    """
    Authenticate user using email and password.
    """
    user = get_user_by_email(db, email=request.email)
    if not user or not verify_password(request.password, user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password"
        )
    return user


@router.post("/register", response_model=UserResponse, status_code=status.HTTP_201_CREATED)
def register(user_in: UserCreate, db: Session = Depends(get_db)) -> UserResponse:
    """
    Register a new inspector or user in the database.
    """
    user = get_user_by_email(db, email=user_in.email)
    if user:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="A user with this email already exists"
        )
    return create_user(db, user_in=user_in)


class RequestOtpRequest(BaseModel):
    email: str


class RequestOtpResponse(BaseModel):
    sent: bool
    dev_otp: str | None = None  # only populated in OTP_DEV_MODE -- see otp_service docstring


@router.post("/request-otp", response_model=RequestOtpResponse)
def request_otp_route(req: RequestOtpRequest, db: Session = Depends(get_db)) -> RequestOtpResponse:
    """
    Step 1 of Email + OTP login: send a 6-digit code to an *existing*
    account's email. Doesn't reveal whether the email exists to avoid
    leaking account existence -- always returns sent=true, but no OTP row
    is actually created for an unknown email, so verify-otp will simply
    never succeed for it.
    """
    user = get_user_by_email(db, email=req.email)
    if user is None:
        return RequestOtpResponse(sent=True, dev_otp=None)
    dev_otp = request_otp(db, req.email)
    return RequestOtpResponse(sent=True, dev_otp=dev_otp)


class VerifyOtpRequest(BaseModel):
    email: str
    code: str


class VerifyOtpResponse(BaseModel):
    token: str
    user: UserResponse


@router.post("/verify-otp", response_model=VerifyOtpResponse)
def verify_otp_route(req: VerifyOtpRequest, db: Session = Depends(get_db)) -> VerifyOtpResponse:
    """Step 2: verify the code and issue a bearer session token."""
    user = get_user_by_email(db, email=req.email)
    if user is None or not verify_otp(db, req.email, req.code):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid or expired code")
    token = issue_token(db, user.id)
    return VerifyOtpResponse(token=token, user=UserResponse.model_validate(user))


@router.get("/me", response_model=UserResponse)
def me(user: User = Depends(get_current_user)) -> UserResponse:
    """Resolve the current session token to the logged-in user -- used to
    restore a session on app launch without asking the user to log in
    again every time."""
    return UserResponse.model_validate(user)
