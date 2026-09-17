"""
Local speech-to-text for M2 audit audio clips (app/models/audit.py's
AuditAudioClip.transcript). Uses openai-whisper against the torch install
already required for YOLOX inference, running fully offline -- no external
API key, matching the OTP work's "avoid new paid dependencies" spirit.

Falls back gracefully (transcript_status="unavailable"/"failed") if whisper
isn't installed or a specific clip fails to transcribe, rather than blocking
the upload -- mirrors OTP_DEV_MODE's "best-effort, never block the request"
posture in otp_service.py.
"""

import logging
import os
from typing import Optional

logger = logging.getLogger(__name__)

TRANSCRIPTION_ENABLED = os.getenv("TRANSCRIPTION_ENABLED", "true").lower() != "false"
WHISPER_MODEL_NAME = os.getenv("WHISPER_MODEL", "tiny")

_model = None
_ffmpeg_path_configured = False


def _ensure_ffmpeg_on_path() -> None:
    """Whisper shells out to a program literally named `ffmpeg` (`ffmpeg.exe`
    on Windows) to decode audio. imageio-ffmpeg (already a dependency for
    video processing) bundles a portable binary, but under a versioned
    filename like `ffmpeg-win-x86_64-v7.1.exe` -- putting its directory on
    PATH isn't enough, since Windows won't resolve the bare "ffmpeg" command
    to a differently-named file. Copy it once to a plain `ffmpeg.exe` in a
    directory we control and PATH that instead."""
    global _ffmpeg_path_configured
    if _ffmpeg_path_configured:
        return
    try:
        import shutil
        import imageio_ffmpeg

        bin_dir = os.path.join(os.path.dirname(__file__), "..", "..", ".cache", "ffmpeg_bin")
        bin_dir = os.path.abspath(bin_dir)
        os.makedirs(bin_dir, exist_ok=True)
        aliased_exe = os.path.join(bin_dir, "ffmpeg.exe")
        if not os.path.exists(aliased_exe):
            shutil.copy2(imageio_ffmpeg.get_ffmpeg_exe(), aliased_exe)
        if bin_dir not in os.environ.get("PATH", ""):
            os.environ["PATH"] = bin_dir + os.pathsep + os.environ.get("PATH", "")
    except Exception as e:
        logger.warning(f"Could not locate bundled ffmpeg for transcription: {e}")
    _ffmpeg_path_configured = True


def _get_model():
    global _model
    if _model is not None:
        return _model
    import whisper

    _ensure_ffmpeg_on_path()
    logger.info(f"Loading Whisper model '{WHISPER_MODEL_NAME}' for audio transcription (first use)...")
    _model = whisper.load_model(WHISPER_MODEL_NAME)
    return _model


def transcribe_audio_file(filepath: str) -> Optional[str]:
    """Returns the transcript text, or None if unavailable/failed."""
    if not TRANSCRIPTION_ENABLED:
        return None
    try:
        model = _get_model()
        result = model.transcribe(filepath)
        text = (result.get("text") or "").strip()
        return text or None
    except Exception as e:
        logger.warning(f"Audio transcription failed for {filepath}: {e}")
        return None


def run_transcription_job(clip_id: int) -> None:
    """Background-task entry point: loads its own DB session (mirrors
    pipeline_manager.process_video), transcribes, and writes the result
    back onto the AuditAudioClip row."""
    from app.db.session import SessionLocal
    from app.crud.audit import get_audio_clip, update_audio_transcript

    db = SessionLocal()
    try:
        clip = get_audio_clip(db, clip_id)
        if clip is None:
            return

        if not TRANSCRIPTION_ENABLED:
            update_audio_transcript(db, clip_id, None, "unavailable")
            return

        base_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
        full_path = os.path.join(base_dir, clip.filepath)
        text = transcribe_audio_file(full_path)
        update_audio_transcript(db, clip_id, text, "done" if text else "failed")
    finally:
        db.close()
