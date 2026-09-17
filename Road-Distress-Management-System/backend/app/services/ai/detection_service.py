"""
AI Detection pipeline orchestration service.
Triggers frame extraction, runs inference, and writes detected anomaly logs to the database.
"""

import time
import logging
from datetime import datetime, timezone

from app.db.session import SessionLocal
from app.crud.video import update_video
from app.schemas.video import UploadedVideoUpdate
from app.services.ai.frame_extractor import extract_frames
from app.services.ai.inference_service import run_inference

logger = logging.getLogger(__name__)


def process_video_pipeline(video_id: int) -> None:
    """
    Asynchronous background task coordinating the video processing pipeline.
    
    Workflow:
      1. Sets the video status to 'processing' and logs start time.
      2. Performs video frame extraction using OpenCV.
      3. Performs anomaly detection inference on extracted frames.
      4. Saves all positive detections to PostgreSQL.
      5. Updates video status to 'completed' and stores performance duration metrics.
      6. Catches pipeline failures and marks video status as 'failed'.
    """
    logger.info(f"Initiating background detection pipeline for Video ID: {video_id}")
    
    # Establish a localized session to prevent threading/async request context leaks
    db = SessionLocal()
    start_time = time.time()
    
    try:
        # 1. Update video record status to 'processing'
        video_update = UploadedVideoUpdate(
            processing_status="processing",
            processing_started_at=datetime.now(timezone.utc)
        )
        db_video = update_video(db, video_id=video_id, video_in=video_update)
        if not db_video:
            logger.error(f"Failed to locate video ID {video_id} during pipeline init.")
            return

        # 2. Extract frames at standard interval (extract every 30th frame)
        logger.info(f"Extracting frames for video path: {db_video.filepath}")
        frames = extract_frames(video_path=db_video.filepath, video_id=video_id, frame_interval=30, in_memory=True)

        # 3 & 4. Execute object detection on frames and log to database
        from app.services.ai.tracker import RoadDistressTracker
        tracker = RoadDistressTracker(db)
        total_detections_count = 0

        for frame_info in frames:
            try:
                detections = run_inference(
                    frame_info["frame_path"],
                    video_id=video_id,
                    frame_number=frame_info["frame_number"]
                )
                
                for det in detections:
                    db_distress = tracker.track_detection(
                        detection=det,
                        frame_number=frame_info["frame_number"],
                        timestamp=frame_info["timestamp"],
                        video_id=video_id
                    )
                    if db_distress:
                        total_detections_count += 1
            except Exception as fe:
                # Log single frame failure but proceed with other frames to avoid total loss
                logger.warning(f"Error processing frame {frame_info.get('frame_path')}: {fe}")
                continue

        # 5. Calculate final performance statistics and update video to completed
        duration = round(time.time() - start_time, 2)
        video_update = UploadedVideoUpdate(
            processing_status="completed",
            processing_completed_at=datetime.now(timezone.utc),
            processing_duration=duration
        )
        update_video(db, video_id=video_id, video_in=video_update)
        
        logger.info(
            f"Successfully processed video {video_id} in {duration}s. "
            f"Logged {total_detections_count} total distress anomalies."
        )

    except Exception as e:
        # 6. Catch total execution failures and transition video to failed state
        duration = round(time.time() - start_time, 2)
        logger.error(f"Fatal error in video processing pipeline: {e}", exc_info=True)
        try:
            video_update = UploadedVideoUpdate(
                processing_status="failed",
                processing_completed_at=datetime.now(timezone.utc),
                processing_duration=duration
            )
            update_video(db, video_id=video_id, video_in=video_update)
        except Exception as db_err:
            logger.critical(f"Failed to record pipeline failure status in database: {db_err}")
    finally:
        db.close()
