"""
Model loader service responsible for managing weights loading and YOLO instance singleton.
Falls back to a simulated inference interface on missing files or dependencies.

The road/signage checkpoints in backend/models/ are YOLOX checkpoints (confirmed by
inspecting their state_dict keys and the standalone backend/models/webcam_test_combined.py
reference script), not Ultralytics YOLO checkpoints -- loading them via ultralytics.YOLO()
always fails regardless of file extension or ultralytics version. Real loading below uses
YOLOX's own get_exp()/load_state_dict() pattern instead. The exact architecture for each
checkpoint was determined by inspecting tensor shapes directly (no original exp config
file was available):
  - road_best.pth:    stem out_channels=48 (width=0.75), 6 CSP bottleneck blocks in
                      dark3/dark4 (depth=0.67) -> matches YOLOX-M defaults exactly.
                      head.cls_preds output channels = 4 -> num_classes=4.
  - signage_best.pth:  stem out_channels=32 (width=0.5), 3 CSP bottleneck blocks in
                      dark3/dark4 (depth=0.33) -> matches YOLOX-S defaults exactly.
                      head.cls_preds output channels = 3 -> num_classes=3.
A strict (non-relaxed) state_dict load was verified to succeed with zero missing/
unexpected keys for both models under these exact parameters.
"""

import os
import logging
import random
from typing import Any, List, Optional

logger = logging.getLogger(__name__)

# Try to import YOLOX, the framework the actual road/signage checkpoints were trained with.
try:
    import torch
    from yolox.exp import get_exp
    from yolox.data.data_augment import ValTransform
    from yolox.utils import postprocess
    YOLOX_AVAILABLE = True
except ImportError:
    YOLOX_AVAILABLE = False

# NMS matches the value tuned and used in backend/models/webcam_test_combined.py
# (the live-camera reference script); YOLOX's own Exp default (nmsthre=0.65) is
# tuned for mAP evaluation, not display/production.
YOLOX_NMS_THRESH = 0.45

# Confidence threshold for the OFFLINE video pipeline specifically -- deliberately
# higher than the live-camera script's 0.3. That value makes sense for a live feed
# a human is watching in real time and can visually discount weak guesses from; it
# doesn't make sense here, where every detection above threshold becomes a
# permanent, unreviewed database row shown as fact in Road Distresses/reports.
# Raising this cuts the weakest/most uncertain false positives (e.g. a 0.51
# "unknown" or a 0.61 guess in an implausible location) -- it does NOT fix
# genuinely wrong detections the model is confident about (e.g. a tree canopy
# mislabeled "SIGN BOARD" at 0.94); that reflects the trained model's real
# accuracy ceiling on this kind of footage, not something a threshold can hide.
YOLOX_CONF_THRESH = 0.6


class MockBoxItem:
    """
    Simulates a single detection box item returned by YOLO.
    """
    def __init__(self, xyxy: List[float], conf: float, cls: int):
        self._xyxy = xyxy
        self._conf = conf
        self._cls = cls

    @property
    def xyxy(self) -> Any:
        # Mimics a tensor list structure supporting .tolist()
        class XYXYList(list):
            def tolist(self):
                return self
        return XYXYList([self._xyxy])

    @property
    def conf(self) -> Any:
        # Mimics a tensor scalar item structure supporting .item()
        class ConfItem(float):
            def item(self):
                return float(self)
            def __getitem__(self, idx):
                return self
        return ConfItem(self._conf)

    @property
    def cls(self) -> Any:
        # Mimics a tensor scalar item structure supporting .item()
        class ClsItem(float):
            def item(self):
                return float(self)
            def __getitem__(self, idx):
                return self
        return ClsItem(self._cls)


class MockBoxes:
    """
    Simulates a list of boxes matching the .boxes property of a YOLO result.
    """
    def __init__(self, items: List[MockBoxItem]):
        self.items = items

    def __len__(self) -> int:
        return len(self.items)

    def __iter__(self):
        return iter(self.items)

    def __getitem__(self, idx: int) -> MockBoxItem:
        return self.items[idx]

    @property
    def xyxy(self) -> Any:
        class XYXYOuterList(list):
            def tolist(self):
                return self
        return XYXYOuterList([item._xyxy for item in self.items])

    @property
    def conf(self) -> List[float]:
        return [item._conf for item in self.items]

    @property
    def cls(self) -> List[int]:
        return [item._cls for item in self.items]


class MockResult:
    """
    Simulates a YOLO inference output result object.
    """
    def __init__(self, boxes: MockBoxes):
        self.boxes = boxes


class MockYOLO:
    """
    Mimics the YOLO model executor in the absence of weights or dependencies.
    """
    def __init__(self, model_path: str):
        self.model_path = model_path
        logger.info(f"MockYOLO initialized mimicking path: {model_path}")

    def __call__(self, frame: Any, **kwargs) -> List[MockResult]:
        """
        Executes mock inference. Returns a list containing a single MockResult
        holding between 0 and 3 randomized bounding boxes.
        """
        # Read frame height/width to scale coordinate values (defaulting to 1280x720)
        h, w = 720, 1280
        if hasattr(frame, "shape"):
            h, w = frame.shape[:2]

        is_signage = "signage" in str(self.model_path).lower()
        num_detections = random.randint(0, 3)
        box_items = []

        for _ in range(num_detections):
            # Generate random bounding boxes that fall within the image boundary
            x1 = random.uniform(50.0, w * 0.6)
            y1 = random.uniform(50.0, h * 0.6)
            x2 = min(x1 + random.uniform(40.0, 250.0), float(w - 10.0))
            y2 = min(y1 + random.uniform(40.0, 200.0), float(h - 10.0))
            conf = random.uniform(0.45, 0.98)

            # Support class indexes matching road distress or signage
            cls_id = random.choice([0, 1, 2, 3])

            box_items.append(MockBoxItem(xyxy=[x1, y1, x2, y2], conf=conf, cls=cls_id))

        return [MockResult(MockBoxes(box_items))]


class YoloxModel:
    """
    Callable wrapper around a loaded YOLOXDetector, presenting the
    same interface RoadDetector/SignDetector/DetectorManager already expect from a
    model (callable returning a list with one result exposing `.boxes`, each box
    exposing `.xyxy`, `.conf`, `.cls`) -- so no other file needs to know this is YOLOX.
    """
    def __init__(self, detector: Any):
        self.detector = detector

    def __call__(self, frame: Any, **kwargs) -> List[MockResult]:
        # Run YOLOXDetector.detect on the BGR frame
        detections = self.detector.detect(frame)
        
        box_items = []
        for det in detections:
            # Reconstruct the integer class ID for YOLO shim directly (no offset here)
            cls_id = det["class_id"]
            box_items.append(MockBoxItem(xyxy=det["box"], conf=det["confidence"], cls=cls_id))
            
        return [MockResult(MockBoxes(box_items))]


class ModelLoader:
    """
    Singleton class managing lazy loading of the AI models.
    """
    _instance = None
    _road_model = None
    _signage_model = None

    def __new__(cls, *args, **kwargs):
        if not cls._instance:
            cls._instance = super(ModelLoader, cls).__new__(cls)
        return cls._instance

    def unload(self) -> None:
        """Release the loaded models so their memory can be reused -- see
        the matching call in LiveCameraManager._ensure_models_loaded()."""
        self._road_model = None
        self._signage_model = None

    def _unload_live_pipeline_if_idle(self) -> None:
        # The live-camera pipeline loads its own separate copies of these
        # same two checkpoints at 256x256 vs this pipeline's 640x640.
        # Release them first so both aren't resident at once -- but only if
        # no live session is actively running, so an in-progress live feed
        # isn't forced to reload mid-session.
        from app.services.live.live_camera_service import LiveCameraManager
        live_manager = LiveCameraManager.instance()
        if not live_manager.is_running():
            live_manager.unload_models()

    def load_road_model(self) -> Any:
        """
        Lazy loads the road distress detection model (YOLOX-M, 4 classes) using YOLOXDetector.
        """
        if self._road_model is not None:
            return self._road_model

        self._unload_live_pipeline_if_idle()

        base_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
        # Loaded via YOLOXDetector -> torch.load() below, which is extension-
        # agnostic (the ".pt"-only requirement was specific to ultralytics.YOLO(),
        # which this file no longer uses -- see the module docstring). Points
        # directly at the canonical road_best.pth so only one copy of the
        # (~190MB) checkpoint needs to exist on disk / in Git LFS.
        full_model_path = os.path.join(base_dir, "models", "road_best.pth")

        from app.services.live.yolox_engine import YOLOXDetector
        if os.path.exists(full_model_path) and YOLOX_AVAILABLE:
            try:
                logger.info("Loading road YOLOX model via shared YOLOXDetector...")
                detector = YOLOXDetector(
                    exp_file="",
                    ckpt_file="",
                    model_source="road",
                    conf_thresh=YOLOX_CONF_THRESH,
                    nms_thresh=YOLOX_NMS_THRESH,
                    # Matches the model's actual training resolution (pavement_yolox_m_exp.py:
                    # input_size=test_size=(640,640)) -- unlike the live camera pipeline
                    # (live_config.py TEST_SIZE=256), the offline upload pipeline has no
                    # real-time framerate constraint, so there's no reason to trade accuracy
                    # for speed here.
                    test_size=640,
                    fallback_ckpt=full_model_path,
                    fallback_exp_name="yolox-m",
                    fallback_num_classes=4,
                    # Confirmed against the real pavement_train.yaml used to train
                    # road_best.pth (nc: 4, names: 0=longitudinal_crack, 1=transverse_crack,
                    # 2=alligator_crack, 3=pothole) -- not a guess.
                    fallback_class_names=["longitudinal_crack", "transverse_crack", "alligator_crack", "pothole"]
                )
                self._road_model = YoloxModel(detector)
            except Exception as e:
                logger.warning(f"Error loading road YOLOX model. Falling back to MockYOLO: {e}")
                self._road_model = MockYOLO(full_model_path)
        else:
            logger.warning(f"Road model file not found at {full_model_path}. Creating MockYOLO model.")
            self._road_model = MockYOLO(full_model_path)

        return self._road_model

    def load_signage_model(self) -> Any:
        """
        Lazy loads the signage detection model (YOLOX-S, 3 classes) using YOLOXDetector.
        """
        if self._signage_model is not None:
            return self._signage_model

        self._unload_live_pipeline_if_idle()

        base_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
        # See load_road_model() above: extension-agnostic loading via
        # YOLOXDetector -> torch.load(), so this points directly at the
        # canonical signage_best.pth (no duplicate ".pt" copy needed).
        full_model_path = os.path.join(base_dir, "models", "signage_best.pth")

        from app.services.live.yolox_engine import YOLOXDetector
        if os.path.exists(full_model_path) and YOLOX_AVAILABLE:
            try:
                logger.info("Loading signage YOLOX model via shared YOLOXDetector...")
                detector = YOLOXDetector(
                    exp_file="",
                    ckpt_file="",
                    model_source="signage",
                    conf_thresh=YOLOX_CONF_THRESH,
                    nms_thresh=YOLOX_NMS_THRESH,
                    # See load_road_model() above: matches signage_yolox_s_exp.py's
                    # actual training resolution (640x640), not the live-camera-only
                    # speed tradeoff.
                    test_size=640,
                    fallback_ckpt=full_model_path,
                    fallback_exp_name="yolox-s",
                    fallback_num_classes=3,
                    # Confirmed via signage_yolox_s_exp.py's own header comment
                    # ("signage detection: TRAFFIC SIGN, SIGN BOARD, POLES") -- not a guess.
                    fallback_class_names=["TRAFFIC SIGN", "SIGN BOARD", "POLES"]
                )
                self._signage_model = YoloxModel(detector)
            except Exception as e:
                logger.warning(f"Error loading signage YOLOX model. Falling back to MockYOLO: {e}")
                self._signage_model = MockYOLO(full_model_path)
        else:
            logger.warning(f"Signage model file not found at {full_model_path}. Creating MockYOLO model.")
            self._signage_model = MockYOLO(full_model_path)

        return self._signage_model

    def load_model(self, model_path: str = None) -> Any:
        """
        Compat layer returning the dual-model DetectorManager instance.
        """
        from app.services.ai.detector_manager import DetectorManager
        return DetectorManager()
