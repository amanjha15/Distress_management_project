"""
Main entry point for the Road Distress Management System backend.
Initializes FastAPI, configures CORS, and registers versioned API endpoints.
"""

from fastapi import FastAPI, APIRouter
from fastapi.middleware.cors import CORSMiddleware
from app.core.config import settings
from app.api.v1.routes import (
    auth,
    distress,
    gis,
    reports,
    maintenance,
    upload,
    users,
    videos,
    detection,
    live,
    projects,
    audits,
)

# Initialize FastAPI application
app = FastAPI(
    title=settings.PROJECT_NAME,
    openapi_url=f"{settings.API_V1_STR}/openapi.json",
    version="1.0.0"
)

# CORS middleware configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


from fastapi import Depends, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import text, inspect
from app.db.session import get_db, SessionLocal
import logging

# Application loggers (pipeline_manager, model_loader, etc.) call logger.info()
# extensively for per-stage/per-frame progress. Without this, Python's root
# logger defaults to WARNING with no handler, so only warnings/errors reach
# the console (via the logging module's stderr "handler of last resort") and
# all pipeline progress is silently swallowed -- making a slow-but-working
# video processing job indistinguishable from a stuck one in the terminal.
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s [%(name)s] %(message)s")

logger = logging.getLogger(__name__)


@app.on_event("startup")
def startup_event() -> None:
    """
    FastAPI startup hook to validate connection to PostgreSQL and auto-run dynamic migrations.
    """
    logger.info("Validating database connection on startup...")
    try:
        db = SessionLocal()
        db.execute(text("SELECT 1"))
        logger.info("Database connection validated successfully.")
        
        # Self-healing migration for processed_filepath column
        try:
            db.execute(text("SELECT processed_filepath FROM uploaded_videos LIMIT 1"))
            logger.info("Database Schema Check: processed_filepath column already exists.")
        except Exception:
            db.rollback()
            try:
                db.execute(text("ALTER TABLE uploaded_videos ADD COLUMN processed_filepath VARCHAR(512)"))
                db.commit()
                logger.info("Database Schema Migration: Added processed_filepath column to uploaded_videos table.")
            except Exception as alt_err:
                logger.warning(f"ALTER TABLE query for processed_filepath failed: {alt_err}")

        # Self-healing migration for processed_video_path column
        try:
            db.execute(text("SELECT processed_video_path FROM uploaded_videos LIMIT 1"))
            logger.info("Database Schema Check: processed_video_path column already exists.")
        except Exception:
            db.rollback()
            try:
                db.execute(text("ALTER TABLE uploaded_videos ADD COLUMN processed_video_path VARCHAR(512)"))
                db.commit()
                logger.info("Database Schema Migration: Added processed_video_path column to uploaded_videos table.")
            except Exception as alt_err:
                logger.warning(f"ALTER TABLE query for processed_video_path failed: {alt_err}")

        # Self-healing migration for road_distresses.detection_image_path to TEXT type
        try:
            db.execute(text("ALTER TABLE road_distresses ALTER COLUMN detection_image_path TYPE TEXT"))
            db.commit()
            logger.info("Database Schema Migration: Altered road_distresses.detection_image_path column to TEXT type.")
        except Exception as alt_col_err:
            db.rollback()
            logger.warning(f"ALTER COLUMN query for detection_image_path failed: {alt_col_err}")

        # Self-healing migration for uploaded_videos.progress column
        try:
            db.execute(text("SELECT progress FROM uploaded_videos LIMIT 1"))
            logger.info("Database Schema Check: progress column already exists.")
        except Exception:
            db.rollback()
            try:
                db.execute(text("ALTER TABLE uploaded_videos ADD COLUMN progress INTEGER DEFAULT 0"))
                db.commit()
                logger.info("Database Schema Migration: Added progress column to uploaded_videos table.")
            except Exception as e_progress:
                logger.warning(f"ALTER TABLE query for progress column failed: {e_progress}")

        # Self-healing migration for uploaded_videos.processing_stage column
        try:
            db.execute(text("SELECT processing_stage FROM uploaded_videos LIMIT 1"))
            logger.info("Database Schema Check: processing_stage column already exists.")
        except Exception:
            db.rollback()
            try:
                db.execute(text("ALTER TABLE uploaded_videos ADD COLUMN processing_stage VARCHAR(100) DEFAULT 'Idle'"))
                db.commit()
                logger.info("Database Schema Migration: Added processing_stage column to uploaded_videos table.")
            except Exception as e_stage:
                logger.warning(f"ALTER TABLE query for processing_stage column failed: {e_stage}")

        # Self-healing migration for road_distresses.model_source column
        try:
            db.execute(text("SELECT model_source FROM road_distresses LIMIT 1"))
            logger.info("Database Schema Check: model_source column already exists.")
        except Exception:
            db.rollback()
            try:
                db.execute(text("ALTER TABLE road_distresses ADD COLUMN model_source VARCHAR(50) DEFAULT 'road'"))
                db.commit()
                logger.info("Database Schema Migration: Added model_source column to road_distresses table.")
            except Exception as e_model_source:
                logger.warning(f"ALTER TABLE query for model_source failed: {e_model_source}")

        # Ensure all tables exist
        from app.db.base import Base
        Base.metadata.create_all(bind=db.bind)

        # Auto-seed Demo Data for Video 20 if missing
        from app.models.video import UploadedVideo
        from app.models.distress import RoadDistress
        from app.models.user import User
        from app.core.security import get_password_hash
        from datetime import datetime

        # Seed admin user
        admin_user = db.query(User).filter(User.id == 1).first()
        if not admin_user:
            admin_user = User(
                id=1,
                email="admin@roaddistress.org",
                full_name="Monitoring Engineer (ME)",
                hashed_password=get_password_hash("AdminSecurePassword123!"),
                role="admin"
            )
            db.add(admin_user)
            db.commit()
        else:
            admin_user.full_name = "Monitoring Engineer (ME)"
            # Self-healing: earlier versions of this seed wrote a literal
            # placeholder string instead of a real password hash, silently
            # locking the documented admin login out of every fresh deploy
            # that already ran this once. Repair it in place if found.
            if admin_user.hashed_password == "hashed_placeholder_admin":
                admin_user.hashed_password = get_password_hash("AdminSecurePassword123!")
            db.commit()

        video_20 = db.query(UploadedVideo).filter(UploadedVideo.id == 20).first()
        if not video_20:
            logger.info("Auto-seeding Video 20 demo record...")
            video_rel_raw = "uploads/videos/99613c95ecb2483994062e8d72cef840_Client_Test_Video.mp4"
            video_rel_proc = "uploads/processed/20/processed_video.mp4"
            video_20 = UploadedVideo(
                id=20,
                filename="Highway_Distress_Inspection_Feed.mp4",
                filepath=video_rel_raw,
                processed_filepath=video_rel_proc,
                processed_video_path=video_rel_proc,
                processing_status="completed",
                progress=100,
                processing_stage="Completed",
                processing_duration=48.5,
                upload_timestamp=datetime.now(),
                created_at=datetime.now(),
                updated_at=datetime.now(),
                uploader_id=1
            )
            db.add(video_20)
            db.commit()

        distress_count = db.query(RoadDistress).filter(RoadDistress.video_id == 20).count()
        if distress_count == 0:
            logger.info("Auto-seeding 8 road distress records for Video 20...")
            detections_config = [
                {"timestamp": 4.5, "type": "Pothole", "severity": "high", "lat": 19.0760, "lng": 72.8777, "conf": 0.94},
                {"timestamp": 9.2, "type": "Alligator Cracks", "severity": "critical", "lat": 19.0768, "lng": 72.8785, "conf": 0.96},
                {"timestamp": 14.8, "type": "Rutting", "severity": "medium", "lat": 19.0775, "lng": 72.8792, "conf": 0.89},
                {"timestamp": 20.1, "type": "Edge Break", "severity": "high", "lat": 19.0782, "lng": 72.8801, "conf": 0.91},
                {"timestamp": 26.5, "type": "Pothole", "severity": "critical", "lat": 19.0790, "lng": 72.8810, "conf": 0.95},
                {"timestamp": 33.0, "type": "Longitudinal Crack", "severity": "medium", "lat": 19.0798, "lng": 72.8820, "conf": 0.88},
                {"timestamp": 39.4, "type": "Patching Defect", "severity": "low", "lat": 19.0805, "lng": 72.8829, "conf": 0.86},
                {"timestamp": 46.2, "type": "Pothole", "severity": "high", "lat": 19.0812, "lng": 72.8838, "conf": 0.93},
            ]
            for idx, det in enumerate(detections_config, start=1):
                crop_rel = f"uploads/crops/crop_v20_{idx}.jpg"
                frame_no = int(det["timestamp"] * 30.0)
                record = RoadDistress(
                    video_id=20,
                    distress_type=det["type"],
                    severity=det["severity"],
                    confidence_score=det["conf"],
                    latitude=det["lat"],
                    longitude=det["lng"],
                    detected_at=datetime.now(),
                    status="detected",
                    image_url=crop_rel,
                    frame_number=frame_no,
                    video_timestamp=det["timestamp"],
                    tracking_id=100 + idx
                )
                db.add(record)
            db.commit()

        db.close()
    except Exception as e:
        logger.critical(f"Database connection validation failed: {e}")


@app.get("/health", tags=["Health"])
def health_check(db: Session = Depends(get_db)) -> dict:
    """
    Enhanced health check validating the database connection and verifying tables.
    """
    try:
        # Perform actual database connection validation
        db.execute(text("SELECT 1"))
        
        # Verify table presence
        inspector = inspect(db.bind)
        tables = inspector.get_table_names()
        
        required_tables = ["users", "road_distresses", "uploaded_videos", "maintenance_tasks", "reports"]
        for table in required_tables:
            if table not in tables:
                raise HTTPException(
                    status_code=500,
                    detail=f"Database table verification failed. Missing table: {table}"
                )
        
        return {
            "status": "healthy",
            "database": "connected",
            "tables": required_tables
        }
    except Exception as e:
        if isinstance(e, HTTPException):
            raise e
        raise HTTPException(
            status_code=503,
            detail=f"Database connection is unhealthy: {str(e)}"
        )


# Centralized router registry for API v1 routes
from app.api.routes import health

api_router = APIRouter()
api_router.include_router(health.router, tags=["Health"])
api_router.include_router(auth.router, prefix="/auth", tags=["Authentication"])
api_router.include_router(distress.router, prefix="/distress", tags=["Road Distress Monitoring"])
api_router.include_router(gis.router, prefix="/gis", tags=["GIS Map Integration"])
api_router.include_router(reports.router, prefix="/reports", tags=["Reporting & Analytics"])
api_router.include_router(maintenance.router, prefix="/maintenance", tags=["Maintenance Scheduling"])
api_router.include_router(users.router, prefix="/users", tags=["Users"])
api_router.include_router(videos.router, prefix="/videos", tags=["Video Management"])
api_router.include_router(upload.router, prefix="/upload", tags=["Media Upload & Processing"])
api_router.include_router(detection.router, prefix="/detection", tags=["AI Distress Detection"])
api_router.include_router(live.router, prefix="/live", tags=["Live Camera Detection"])
api_router.include_router(projects.router, prefix="/projects", tags=["Projects (Module Platform)"])
api_router.include_router(audits.router, prefix="/audits", tags=["M2 Road Safety Audit"])

# Bind centralized API version 1 router to application
app.include_router(api_router, prefix=settings.API_V1_STR)

import os
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse

_uploads_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "uploads")
os.makedirs(_uploads_dir, exist_ok=True)

# NOTE: /download-apk MUST be registered BEFORE app.mount("/uploads") because
# FastAPI's StaticFiles mount acts as a catch-all sub-app and will shadow any
# routes registered after it at the same router level.
@app.get("/download-apk", tags=["APK Download"])
@app.get("/app-release.apk", tags=["APK Download"])
def download_apk():
    """
    Download the Road Distress Monitoring System Android APK installer.
    """
    apk_path = os.path.join(_uploads_dir, "RoadDistress.apk")
    if os.path.exists(apk_path):
        return FileResponse(
            path=apk_path,
            filename="RoadDistress_v1.0.0.apk",
            media_type="application/vnd.android.package-archive"
        )
    raise HTTPException(status_code=404, detail="APK build file not found.")

# Serve uploads/ (video frames, detection snapshots, live-camera snapshots) so the
# frontend can reference them directly, e.g. /uploads/detections/live/<file>.jpg
# IMPORTANT: This mount must come LAST — after all @app.get() routes are registered.
app.mount("/uploads", StaticFiles(directory=_uploads_dir), name="uploads")


