FROM python:3.12-slim

# build-essential: pycocotools/yolox compile native extensions at install time.
# libgl1/libglib2.0-0: runtime shared libs opencv-python needs (no X server
# on a headless server, but these libs are still linked at import time).
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libgl1 \
    libglib2.0-0 \
    curl \
    && rm -rf /var/lib/apt/lists/*

# WORKDIR is one level deeper than usual (/app/backend, not /app) on
# purpose: pdf_generator.py/excel_generator.py/reports.py's download routes
# all resolve paths as N ".." hops up from their own __file__, up to a
# shared base_dir (the parent of backend/). Using /app as WORKDIR directly
# would shift every one of those hops by one level.
WORKDIR /app/backend

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# yolox's own PyPI metadata pins onnx==1.8.1 (no wheel for this Python
# version) among other training-only deps this project's inference path
# never uses -- --no-deps skips that unresolvable set. See the comment in
# requirements.txt above the pycocotools/loguru/tabulate/thop/tqdm block.
RUN pip install --no-cache-dir cmake ninja \
    && pip install --no-cache-dir yolox==0.3.0 --no-deps --no-build-isolation

COPY . .

# Some Git-connected build providers (confirmed: Railway) check out ~130-byte
# git-lfs *pointer* files here instead of resolving the real ~200MB/70MB
# checkpoints -- docker-compose sidesteps this via a runtime bind mount over
# ./backend/models, but a provider with no such mount ships a backend that
# can't load its own models. Redownload from a GitHub Release, but only when
# what's on disk isn't already the real file (keeps this a no-op for
# docker-compose, where the bind mount already has the genuine files).
RUN for f in road_best.pth signage_best.pth; do \
      size=$(stat -c%s "models/$f" 2>/dev/null || echo 0); \
      if [ "$size" -lt 1000000 ]; then \
        echo "models/$f is $size bytes (likely an unresolved git-lfs pointer) -- fetching the real file from GitHub Releases..." && \
        curl -fsSL -o "models/$f" "https://github.com/amanjha15/Distress_management_project/releases/download/model-weights-v1/$f"; \
      fi; \
    done

# uploads/ (raw + processed videos, detection crops) and generated
# PDF/Excel reports (uploads/reports/) both persist inside backend/,
# mounted as one volume in docker-compose.yml (or one Railway Volume),
# not baked into the image.
RUN mkdir -p uploads/reports

EXPOSE 8000

# Shell form (not exec-form array) so $PORT expands -- Railway injects a
# dynamic PORT at runtime and expects the process to bind to it; falls back
# to 8000 for docker-compose/local runs where PORT is unset.
CMD uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}
