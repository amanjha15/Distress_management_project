"""
Frame extraction service utilizing OpenCV to extract individual frames from surveillance video files.
"""

import os
import cv2
import logging
from typing import List, Dict, Any

logger = logging.getLogger(__name__)


def extract_frames(video_path: str, video_id: int, frame_interval: int = 30, in_memory: bool = False) -> List[Dict[str, Any]]:
    """
    OpenCV frame extractor. Reads a video file and saves every Nth frame to disk, or keeps them in memory.
    
    Args:
        video_path (str): Relative or absolute path to the video file.
        video_id (int): Database ID of the video record (used in folder pathing).
        frame_interval (int): Capture interval count (e.g. 30 extracts every 30th frame).
        in_memory (bool): If True, returns image array directly in frame_path without writing to disk.

    Returns:
        List[Dict[str, Any]]: List of dicts representing extracted frames:
            - 'frame_path': path relative to backend root directory (or numpy array if in_memory=True)
            - 'frame_number': index integer of the frame
            - 'timestamp': timestamp offset in seconds from start of video
    """
    base_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
    
    # Target frame storage directory
    frames_dir = os.path.join(base_dir, "uploads", "frames", str(video_id))
    if not in_memory:
        os.makedirs(frames_dir, exist_ok=True)

    # Determine absolute path to video file
    full_video_path = os.path.join(base_dir, video_path)
    if not os.path.exists(full_video_path):
        # Fallback if path is already absolute
        full_video_path = video_path

    if not os.path.exists(full_video_path):
        raise FileNotFoundError(f"Video file not found at: {full_video_path}")

    cap = cv2.VideoCapture(full_video_path)
    if not cap.isOpened():
        raise ValueError(f"Could not open video file using OpenCV: {full_video_path}")

    # Determine frames per second (FPS) to compute correct video timestamps
    fps = cap.get(cv2.CAP_PROP_FPS)
    if fps <= 0:
        logger.warning(f"Invalid video FPS ({fps}) detected. Defaulting calculation to 30.0 FPS.")
        fps = 30.0

    # Container-reported frame count, purely for the early-stop diagnostic
    # below -- not treated as ground truth (this metadata is sometimes
    # inaccurate, e.g. for variable-frame-rate recordings), just a sanity
    # check against how many frames cv2 actually manages to read.
    expected_frame_count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))

    extracted_frames = []
    frame_count = 0

    try:
        while True:
            ret, frame = cap.read()
            if not ret:
                break

            if frame_count % frame_interval == 0:
                if in_memory:
                    frame_data = frame.copy()
                else:
                    frame_filename = f"frame_{frame_count:06d}.jpg"
                    frame_filepath = os.path.join(frames_dir, frame_filename)
                    # Write frame to disk
                    cv2.imwrite(frame_filepath, frame)
                    # Store relative filepath for backend schema updates
                    frame_data = os.path.relpath(frame_filepath, base_dir).replace("\\", "/")

                timestamp = round(frame_count / fps, 3)

                extracted_frames.append({
                    "frame_path": frame_data,
                    "frame_number": frame_count,
                    "timestamp": timestamp
                })

            frame_count += 1
    finally:
        cap.release()

    logger.info(f"Extracted {len(extracted_frames)} frames from video {video_id} (Total read frames: {frame_count}).")

    # cv2.VideoCapture.read() can silently start returning False partway
    # through a real-world file (corrupt GOP boundary, a codec/container
    # quirk common in phone/dashcam recordings) well before the actual end
    # of the video -- it looks identical to a normal end-of-file, so this
    # is the only signal that distinguishes "video genuinely had this many
    # frames" from "cv2 gave up partway through and silently under-processed
    # the rest, missing whatever distresses were in the untouched portion".
    if expected_frame_count > 0 and frame_count < expected_frame_count * 0.9:
        logger.warning(
            f"Video {video_id}: cv2 only read {frame_count} of an expected "
            f"~{expected_frame_count} frames (container metadata) -- likely "
            f"stopped early due to a decode issue partway through the file, "
            f"not because the video actually ended. Distresses in the "
            f"unread portion (frames {frame_count}-{expected_frame_count}) "
            f"were never analyzed."
        )

    return extracted_frames


def get_frame_count(video_path: str) -> int:
    """
    Cheap metadata-only read (opens, reads one property, releases -- never
    decodes an actual frame) for progress-percentage denominators. Not
    treated as exact ground truth: container-reported frame counts are
    sometimes inaccurate (e.g. variable-frame-rate recordings), same
    caveat extract_frames()'s own early-stop warning documents.
    """
    base_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
    full_video_path = os.path.join(base_dir, video_path)
    if not os.path.exists(full_video_path):
        full_video_path = video_path
    cap = cv2.VideoCapture(full_video_path)
    try:
        return int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    finally:
        cap.release()


def iter_frames(video_path: str, video_id: int, frame_interval: int = 1):
    """
    Streaming counterpart to extract_frames(): yields one
    {"frame_path": ndarray, "frame_number": int, "timestamp": float} dict
    at a time instead of decoding and holding every sampled frame of the
    whole video in memory simultaneously before returning. Every current
    caller (pipeline_manager.process_video) only ever processes frames one
    at a time in order, so this is a drop-in, detection-behavior-preserving
    replacement for extract_frames(..., in_memory=True) -- same per-frame
    dict shape, same sampling via frame_interval -- that caps peak memory
    at roughly one frame's worth instead of O(video length). A 1-minute
    1080p video at 30fps with frame_interval=1 is ~1800 frames; holding
    them all as ~6MB arrays at once (the old behavior) is 10GB+, which is
    what was actually OOM-killing video uploads, not model size.
    """
    base_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
    full_video_path = os.path.join(base_dir, video_path)
    if not os.path.exists(full_video_path):
        full_video_path = video_path
    if not os.path.exists(full_video_path):
        raise FileNotFoundError(f"Video file not found at: {full_video_path}")

    cap = cv2.VideoCapture(full_video_path)
    if not cap.isOpened():
        raise ValueError(f"Could not open video file using OpenCV: {full_video_path}")

    fps = cap.get(cv2.CAP_PROP_FPS)
    if fps <= 0:
        logger.warning(f"Invalid video FPS ({fps}) detected. Defaulting calculation to 30.0 FPS.")
        fps = 30.0

    frame_count = 0
    yielded = 0
    try:
        while True:
            ret, frame = cap.read()
            if not ret:
                break
            if frame_count % frame_interval == 0:
                yield {
                    "frame_path": frame,
                    "frame_number": frame_count,
                    "timestamp": round(frame_count / fps, 3),
                }
                yielded += 1
            frame_count += 1
    finally:
        cap.release()

    logger.info(f"Streamed {yielded} frames from video {video_id} (Total read frames: {frame_count}).")
