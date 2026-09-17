"""
OTP generation/verification and "sending" for Email + OTP login.

Dev mode (default): the OTP is logged to the backend console and returned
in the /auth/request-otp response body under `dev_otp` -- there's no SMTP
configured yet, and this lets the whole login flow be built and tested
locally right now without needing real email credentials.

To switch to real email delivery later: implement send_via_smtp() below
(host/port/credentials from app.core.config.settings, matching the same
env-var pattern the rest of the app uses) and set OTP_DEV_MODE=false in
.env -- nothing else about the flow changes.
"""

import logging
import os
import random
import secrets
import string
from datetime import datetime, timedelta, timezone

from sqlalchemy.orm import Session

from app.models.auth import OtpCode, AuthToken

logger = logging.getLogger(__name__)

OTP_LENGTH = 6
OTP_TTL_MINUTES = 10
TOKEN_TTL_DAYS = 30

OTP_DEV_MODE = os.getenv("OTP_DEV_MODE", "true").lower() != "false"


def _generate_code() -> str:
    return "".join(random.choices(string.digits, k=OTP_LENGTH))


def request_otp(db: Session, email: str) -> str | None:
    """
    Creates a new OTP row for this email and "sends" it. Returns the code
    only in dev mode (so the API response / logs can surface it for local
    testing) -- in real-email mode this returns None, since the code should
    only ever reach the user's inbox.
    """
    code = _generate_code()
    expires_at = datetime.now(timezone.utc) + timedelta(minutes=OTP_TTL_MINUTES)
    db.add(OtpCode(email=email.lower().strip(), code=code, expires_at=expires_at))
    db.commit()

    if OTP_DEV_MODE:
        logger.info(f"[DEV MODE] OTP for {email}: {code} (expires in {OTP_TTL_MINUTES} min)")
        return code

    send_via_smtp(email, code)
    return None


def send_via_smtp(email: str, code: str) -> None:
    """Not implemented yet -- see module docstring. Placeholder for real delivery."""
    raise NotImplementedError(
        "Real SMTP sending isn't configured yet. Set OTP_DEV_MODE=true in .env "
        "(the default) to keep using console/dev-response OTP delivery for now."
    )


def verify_otp(db: Session, email: str, code: str) -> bool:
    """Marks the most recent matching, unused, unexpired OTP as used. True if valid."""
    email = email.lower().strip()
    now = datetime.now(timezone.utc)
    otp = (
        db.query(OtpCode)
        .filter(OtpCode.email == email, OtpCode.code == code, OtpCode.used == False)  # noqa: E712
        .order_by(OtpCode.id.desc())
        .first()
    )
    if otp is None:
        return False
    otp_expires_at = otp.expires_at if otp.expires_at.tzinfo else otp.expires_at.replace(tzinfo=timezone.utc)
    if otp_expires_at < now:
        return False
    otp.used = True
    db.commit()
    return True


def issue_token(db: Session, user_id: int) -> str:
    token = secrets.token_hex(32)
    expires_at = datetime.now(timezone.utc) + timedelta(days=TOKEN_TTL_DAYS)
    db.add(AuthToken(token=token, user_id=user_id, expires_at=expires_at))
    db.commit()
    return token


def resolve_token(db: Session, token: str) -> int | None:
    """Returns the user_id for a valid, unexpired token, else None."""
    row = db.query(AuthToken).filter(AuthToken.token == token).first()
    if row is None:
        return None
    expires_at = row.expires_at if row.expires_at.tzinfo else row.expires_at.replace(tzinfo=timezone.utc)
    if expires_at < datetime.now(timezone.utc):
        return None
    return row.user_id
