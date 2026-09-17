"""
LiveCameraManager: background service running dual YOLOX inference on a USB
camera and exposing results to the API layer.

Responsibilities:
  - Own the cv2.VideoCapture loop in a daemon thread (start/stop safe).
  - Replicate the validated cadence from webcam_test_combined.py:
    inference every Nth frame, signage every 2nd inference, cached boxes
    drawn on every frame so the display never flickers.
  - Keep the latest annotated frame JPEG-encoded in memory (MJPEG source).
  - Maintain a bounded event feed + counters for the WebSocket/status API.
  - Persist detections to road_distresses with per-class throttling so a
    live camera cannot flood the database, saving an annotated snapshot
    per persisted detection.
"""

import os
import time
import random
import logging
import threading
from collections import deque
from datetime import datetime
from typing import Any, Dict, List, Optional

import cv2

from app.services.live import live_config as cfg

logger = logging.getLogger(__name__)


def _severity_for(detection: Dict[str, Any]) -> str:
    """Pavement severity from confidence; signage is always informational."""
    if detection["model_source"] == "signage":
        return "low"
    conf = detection["confidence"]
    if conf >= 0.9:
        return "critical"
    if conf >= 0.8:
        return "high"
    if conf >= 0.5:
        return "medium"
    return "low"


def _color_for(detection: Dict[str, Any]):
    if detection["model_source"] == "signage":
        return cfg.SIGNAGE_COLORS.get(detection["class_name"], cfg.DEFAULT_COLOR)
    return cfg.PAVEMENT_COLORS.get(detection["class_name"], cfg.DEFAULT_COLOR)


def _draw(frame, detections: List[Dict[str, Any]]):
    for det in detections:
        x1, y1, x2, y2 = [int(v) for v in det["box"]]
        color = _color_for(det)
        label = f'{det["class_name"]} {det["confidence"]:.2f}'
        cv2.rectangle(frame, (x1, y1), (x2, y2), color, 2)
        cv2.putText(frame, label, (x1, max(15, y1 - 8)),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.6, color, 2)
    return frame


class LiveCameraManager:
    """Singleton managing the live capture/inference loop."""

    _instance: Optional["LiveCameraManager"] = None
    _instance_lock = threading.Lock()

    def __init__(self):
        self._capture_thread: Optional[threading.Thread] = None
        self._inference_thread: Optional[threading.Thread] = None
        self._cap: Optional[cv2.VideoCapture] = None
        self._running = threading.Event()
        self._lock = threading.Lock()          # guards latest frame + stats
        self._latest_jpeg: Optional[bytes] = None
        self._events: deque = deque(maxlen=200)
        self._event_seq = 0
        self._last_persist: Dict[str, float] = {}
        self._error: Optional[str] = None
        self._pavement = None
        self._signage = None
        self._pavement_info: Optional[Dict[str, Any]] = None
        self._signage_info: Optional[Dict[str, Any]] = None
        self.stats: Dict[str, Any] = self._blank_stats()
        self.base_lat = cfg.DEFAULT_LATITUDE
        self.base_lon = cfg.DEFAULT_LONGITUDE

        # Buffers for shared frame and detections
        self._latest_raw_frame: Optional[Any] = None
        self._raw_frame_count = 0
        self._latest_road_detections: List[Dict[str, Any]] = []
        self._latest_sign_detections: List[Dict[str, Any]] = []

    @classmethod
    def instance(cls) -> "LiveCameraManager":
        with cls._instance_lock:
            if cls._instance is None:
                cls._instance = LiveCameraManager()
            return cls._instance

    # ------------------------------------------------------------------ #
    # Lifecycle
    # ------------------------------------------------------------------ #
    def _ensure_models_loaded(self) -> None:
        """Lazy-loads both YOLOX models on first start (local or remote)."""
        from app.services.live.yolox_engine import YOLOXDetector

        if self._pavement is None or self._signage is None:
            # The video-upload pipeline (app/services/ai/model_loader.py)
            # loads its own separate copies of these same two checkpoints at
            # 640x640 vs this pipeline's 256x256. Having both loaded at once
            # roughly doubles this process's resident memory -- enough to
            # trigger OOM kills on memory-constrained hosts. Release that
            # pipeline's models first; they'll lazily reload (at a one-time
            # latency cost) the next time a video is processed.
            from app.services.ai.model_loader import ModelLoader
            ModelLoader().unload()

        if self._pavement is None:
            self._pavement = YOLOXDetector(
                cfg.PAVEMENT_EXP_FILE, cfg.PAVEMENT_CKPT, "road",
                cfg.CONF_THRESH, cfg.NMS_THRESH, cfg.TEST_SIZE,
                fallback_ckpt=cfg.FALLBACK_PAVEMENT_CKPT,
                fallback_exp_name=cfg.FALLBACK_PAVEMENT_EXP_NAME,
                fallback_num_classes=cfg.FALLBACK_PAVEMENT_NUM_CLASSES,
                fallback_class_names=cfg.FALLBACK_PAVEMENT_CLASS_NAMES)
        if self._signage is None:
            self._signage = YOLOXDetector(
                cfg.SIGNAGE_EXP_FILE, cfg.SIGNAGE_CKPT, "signage",
                cfg.CONF_THRESH, cfg.NMS_THRESH, cfg.TEST_SIZE,
                fallback_ckpt=cfg.FALLBACK_SIGNAGE_CKPT,
                fallback_exp_name=cfg.FALLBACK_SIGNAGE_EXP_NAME,
                fallback_num_classes=cfg.FALLBACK_SIGNAGE_NUM_CLASSES,
                fallback_class_names=cfg.FALLBACK_SIGNAGE_CLASS_NAMES)

        # Record exactly which files/architecture actually loaded, for /live/status
        # and /live/ws -- so it's visible without reading the server console log.
        self._pavement_info = {
            "source": self._pavement.source,                        # "configured" | "fallback"
            "ckpt_path": self._pavement.ckpt_path,                   # the file actually loaded
            "exp_source": self._pavement.exp_source,                # exp file path, or "built-in:yolox-m"
            "configured_exp_file": self._pavement.configured_exp_file,   # live_test/ path, whether or not it existed
            "configured_ckpt_file": self._pavement.configured_ckpt_file,
            "class_names": self._pavement.class_names,
        }
        self._signage_info = {
            "source": self._signage.source,
            "ckpt_path": self._signage.ckpt_path,
            "exp_source": self._signage.exp_source,
            "configured_exp_file": self._signage.configured_exp_file,
            "configured_ckpt_file": self._signage.configured_ckpt_file,
            "class_names": self._signage.class_names,
        }

    def _reset_session_state(self, source: str, latitude: Optional[float], longitude: Optional[float]) -> None:
        if latitude is not None:
            self.base_lat = latitude
        if longitude is not None:
            self.base_lon = longitude
        self._error = None
        self.stats = self._blank_stats()
        self.stats["source"] = source
        self._last_persist.clear()
        self._latest_raw_frame = None
        self._raw_frame_count = 0
        self._latest_road_detections = []
        self._latest_sign_detections = []

    def start_remote(
        self,
        latitude: Optional[float] = None,
        longitude: Optional[float] = None,
    ) -> Dict[str, Any]:
        """
        Starts the inference loop with no local capture thread -- frames are
        expected to arrive one at a time via push_frame(), called by a
        streaming client (e.g. the phone app's camera feed over WebSocket)
        instead of a local cv2.VideoCapture. Reuses the exact same detection/
        tracking/persistence loop the USB-camera path uses; only the frame
        source differs.
        """
        if self._running.is_set():
            return {"status": "already_running", **self.status()}

        self._ensure_models_loaded()
        self._reset_session_state("remote_stream", latitude, longitude)
        self.stats["camera_index"] = None

        self._running.set()
        self._inference_thread = threading.Thread(
            target=self._inference_loop, daemon=True, name="live-inference")
        self._inference_thread.start()
        logger.info("Live remote-stream inference thread started (awaiting pushed frames)")
        return {"status": "started", **self.status()}

    def push_frame(self, frame) -> None:
        """
        Feeds one already-decoded BGR frame (numpy array) into the running
        remote-stream session -- called per frame received over the phone
        streaming WebSocket. No-op if no session is running (e.g. the client
        pushed a frame after start_remote() failed or before it was called).
        """
        if not self._running.is_set():
            return
        with self._lock:
            self._latest_raw_frame = frame
            self._raw_frame_count += 1
            frame_count = self._raw_frame_count
            current_road = list(self._latest_road_detections)
            current_sign = list(self._latest_sign_detections)

        # Keep /live/stream (MJPEG) valid too even though the phone itself
        # draws its own overlay locally from /live/ws events -- useful for
        # viewing the same session from a second device (e.g. a desk monitor).
        annotated = _draw(frame.copy(), current_road + current_sign)
        ok, buf = cv2.imencode(".jpg", annotated, [cv2.IMWRITE_JPEG_QUALITY, 80])
        with self._lock:
            if ok:
                self._latest_jpeg = buf.tobytes()
            self.stats["frames"] = frame_count

    def start(
        self,
        camera_index: int = cfg.DEFAULT_CAMERA_INDEX,
        latitude: Optional[float] = None,
        longitude: Optional[float] = None,
    ) -> Dict[str, Any]:
        if self._running.is_set():
            return {"status": "already_running", **self.status()}

        self._ensure_models_loaded()

        if latitude is not None:
            self.base_lat = latitude
        if longitude is not None:
            self.base_lon = longitude

        self._error = None
        self.stats = self._blank_stats()
        self.stats["camera_index"] = camera_index
        self._last_persist.clear()

        # Reset capture/detections buffer states
        self._latest_raw_frame = None
        self._raw_frame_count = 0
        self._latest_road_detections = []
        self._latest_sign_detections = []

        self._running.set()

        self._capture_thread = threading.Thread(
            target=self._capture_loop, args=(camera_index,), daemon=True, name="live-capture")
        self._inference_thread = threading.Thread(
            target=self._inference_loop, daemon=True, name="live-inference")

        self._capture_thread.start()
        self._inference_thread.start()
        logger.info(f"Live camera capture and inference threads started on index {camera_index}")
        return {"status": "started", **self.status()}

    def stop(self) -> Dict[str, Any]:
        self._running.clear()
        # Note: We do NOT call self._cap.release() from the main thread here.
        # Calling release() from another thread while the capture thread is in cap.read()
        # can cause deadlocks/hangs in the Windows DirectShow (DSHOW) backend.
        # Instead, the capture loop will exit naturally (checking self._running.is_set())
        # and release the device on its own thread. If the camera is unplugged, cap.read()
        # returns False and exits. The join timeouts below act as guards if it hangs.

        if self._capture_thread is not None:
            self._capture_thread.join(timeout=3.0)
            self._capture_thread = None
        if self._inference_thread is not None:
            self._inference_thread.join(timeout=3.0)
            self._inference_thread = None

        logger.info("Live camera stopped")
        return {"status": "stopped", **self.status()}

    # ------------------------------------------------------------------ #
    # Consumers
    # ------------------------------------------------------------------ #
    def latest_jpeg(self) -> Optional[bytes]:
        with self._lock:
            return self._latest_jpeg

    def is_running(self) -> bool:
        return self._running.is_set()

    def unload_models(self) -> None:
        """Release the loaded YOLOX detectors so their memory can be
        reused. Safe to call even mid-session: any in-flight inference
        loop already holds its own reference to these objects (Python is
        reference-counted), so this only affects the *next* load -- it
        will lazily reload on the next start()/start_remote() call. See
        the matching call in ModelLoader.load_road_model()."""
        self._pavement = None
        self._signage = None
        self._pavement_info = None
        self._signage_info = None

    def status(self) -> Dict[str, Any]:
        with self._lock:
            s = dict(self.stats)
        s["running"] = self.is_running()
        s["error"] = self._error
        s["pavement_model"] = self._pavement_info
        s["signage_model"] = self._signage_info
        return s

    def events_since(self, seq: int) -> List[Dict[str, Any]]:
        with self._lock:
            return [e for e in self._events if e["seq"] > seq]

    # ------------------------------------------------------------------ #
    # Internal loops (Ported to capture and inference threads)
    # ------------------------------------------------------------------ #
    def _blank_stats(self) -> Dict[str, Any]:
        return {
            "camera_index": None, "frames": 0, "inferences": 0,
            "detections_total": 0, "detections_road": 0, "detections_sign": 0,
            "critical_alerts": 0, "persisted": 0,
            "avg_confidence": 0.0, "fps": 0.0, "inference_fps": 0.0, "started_at": None,
        }

    def _capture_loop(self, camera_index: int) -> None:
        backend_flag = cv2.CAP_DSHOW if os.name == "nt" else cv2.CAP_ANY
        cap = cv2.VideoCapture(camera_index, backend_flag)
        cap.set(cv2.CAP_PROP_FRAME_WIDTH, cfg.CAPTURE_WIDTH)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, cfg.CAPTURE_HEIGHT)

        with self._lock:
            self._cap = cap

        if not cap.isOpened():
            with self._lock:
                self._error = f"Could not open camera index {camera_index}"
                self._cap = None
            logger.error(self._error)
            self._running.clear()
            return

        with self._lock:
            self.stats["started_at"] = datetime.utcnow().isoformat()

        frame_count = 0
        t0 = time.time()

        try:
            while self._running.is_set():
                ret, frame = cap.read()
                if not ret:
                    with self._lock:
                        self._error = "Camera frame read failed"
                    break
                frame_count += 1

                # Update the shared raw frame for the inference thread (LATEST frame only)
                with self._lock:
                    self._latest_raw_frame = frame.copy()
                    self._raw_frame_count = frame_count

                # Draw the most recent known boxes on every frame (no flicker)
                with self._lock:
                    current_road = list(self._latest_road_detections)
                    current_sign = list(self._latest_sign_detections)

                annotated = _draw(frame, current_road + current_sign)

                ok, buf = cv2.imencode(".jpg", annotated, [cv2.IMWRITE_JPEG_QUALITY, 80])
                elapsed = max(time.time() - t0, 1e-6)

                with self._lock:
                    if ok:
                        self._latest_jpeg = buf.tobytes()
                    self.stats["frames"] = frame_count
                    self.stats["fps"] = round(frame_count / elapsed, 1)
        finally:
            with self._lock:
                if self._cap is not None:
                    self._cap.release()
                    self._cap = None
            self._running.clear()

    def _inference_loop(self) -> None:
        last_processed_frame_idx = -1
        inference_count = 0
        conf_sum, conf_n = 0.0, 0
        last_road: List[Dict[str, Any]] = []
        last_sign: List[Dict[str, Any]] = []
        t0 = time.time()

        try:
            while self._running.is_set():
                frame_to_process = None
                current_frame_idx = -1

                with self._lock:
                    # Only grab a new frame if it's newer than the last processed frame AND
                    # respects the configured frame skip cadence
                    if self._latest_raw_frame is not None and self._raw_frame_count > last_processed_frame_idx:
                        if self._raw_frame_count - last_processed_frame_idx >= cfg.PROCESS_EVERY_N_FRAMES:
                            frame_to_process = self._latest_raw_frame.copy()
                            current_frame_idx = self._raw_frame_count

                if frame_to_process is None:
                    # Sleep a tiny bit to avoid busy-waiting when no new frame is available
                    time.sleep(0.005)
                    continue

                last_processed_frame_idx = current_frame_idx
                inference_count += 1
                new_detections: List[Dict[str, Any]] = []

                try:
                    # Run pavement detection
                    last_road = self._pavement.detect(frame_to_process)
                    new_detections.extend(last_road)

                    # Run signage detection every N inferences
                    if inference_count % cfg.RUN_SIGNAGE_EVERY_N_INFERENCES == 0:
                        last_sign = self._signage.detect(frame_to_process)
                        new_detections.extend(last_sign)

                    # Store detections to be picked up by the capture thread for drawing
                    with self._lock:
                        self._latest_road_detections = last_road
                        self._latest_sign_detections = last_sign
                except Exception as e:
                    logger.error(f"Live inference error: {e}")

                elapsed = max(time.time() - t0, 1e-6)
                with self._lock:
                    self.stats["inferences"] = inference_count
                    self.stats["inference_fps"] = round(inference_count / elapsed, 1)

                # Handle fresh detections: events, counters, throttled DB writes
                for det in new_detections:
                    severity = _severity_for(det)
                    conf_sum += det["confidence"]
                    conf_n += 1
                    lat = round(self.base_lat + random.uniform(-0.0005, 0.0005), 6)
                    lon = round(self.base_lon + random.uniform(-0.0005, 0.0005), 6)
                    with self._lock:
                        self.stats["detections_total"] += 1
                        if det["model_source"] == "road":
                            self.stats["detections_road"] += 1
                        else:
                            self.stats["detections_sign"] += 1
                        if severity == "critical":
                            self.stats["critical_alerts"] += 1
                        self.stats["avg_confidence"] = round(conf_sum / conf_n, 4)
                        self._event_seq += 1
                        self._events.append({
                            "seq": self._event_seq,
                            "time": datetime.utcnow().isoformat(),
                            "class_name": det["class_name"],
                            "confidence": round(det["confidence"], 4),
                            "severity": severity,
                            "model_source": det["model_source"],
                            "frame": current_frame_idx,
                            "latitude": lat,
                            "longitude": lon,
                            # Box in original-frame pixel coords (x1,y1,x2,y2),
                            # plus the frame size those coords are relative to
                            # -- a client (e.g. the phone app) needs both to
                            # scale the box onto its own preview widget, since
                            # capture resolution is client-controlled.
                            "box": [round(v, 1) for v in det["box"]],
                            "frame_width": frame_to_process.shape[1],
                            "frame_height": frame_to_process.shape[0],
                        })
                    
                    annotated_for_persist = _draw(frame_to_process.copy(), last_road + last_sign)
                    self._maybe_persist(det, severity, annotated_for_persist, current_frame_idx, elapsed, lat, lon)
        finally:
            self._running.clear()

    # ------------------------------------------------------------------ #
    # Throttled persistence
    # ------------------------------------------------------------------ #
    def _maybe_persist(self, det: Dict[str, Any], severity: str,
                       annotated_frame, frame_number: int, elapsed: float, lat: float, lon: float) -> None:
        """
        Save a detection to road_distresses at most once per class per
        PERSIST_MIN_INTERVAL_SEC, and only above PERSIST_CONF_THRESH.
        Writes via the ORM model directly (schema-agnostic to newer
        Pydantic changes on main). Never lets a DB error kill the loop.
        """
        if det["confidence"] < cfg.PERSIST_CONF_THRESH:
            return
        key = f'{det["model_source"]}:{det["class_name"]}'
        now = time.time()
        if now - self._last_persist.get(key, 0.0) < cfg.PERSIST_MIN_INTERVAL_SEC:
            return
        self._last_persist[key] = now

        try:
            from app.db.session import SessionLocal
            from app.models.distress import RoadDistress

            os.makedirs(cfg.SNAPSHOT_DIR, exist_ok=True)
            snap_name = f"live_{int(now)}_{det['class_name'].replace(' ', '_')}.jpg"
            snap_path = os.path.join(cfg.SNAPSHOT_DIR, snap_name)
            cv2.imwrite(snap_path, annotated_frame)
            rel_path = os.path.relpath(snap_path, cfg.BACKEND_ROOT).replace("\\", "/")

            db = SessionLocal()
            try:
                row = RoadDistress(
                    distress_type=det["class_name"],
                    severity=severity,
                    confidence_score=round(det["confidence"], 4),
                    latitude=lat,
                    longitude=lon,
                    image_url=rel_path,
                    status="detected",
                    detected_at=datetime.utcnow(),
                    frame_number=frame_number,
                    video_timestamp=round(elapsed, 3),
                    source_type="live",
                    detection_image_path=rel_path,
                    model_source=det["model_source"],
                )
                db.add(row)
                db.commit()
                with self._lock:
                    self.stats["persisted"] += 1
            finally:
                db.close()
        except Exception as e:
            logger.error(f"Live detection persistence failed: {e}")
