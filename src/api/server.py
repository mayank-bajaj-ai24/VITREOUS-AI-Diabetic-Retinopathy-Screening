"""
NETRA — Real-Time Screening API (Phase 1 & Phase 2 Demo Hook)
Provides REST endpoints for retinal image quality assessment and adaptive enhancement.
"""

import os
import sys
from pathlib import Path
import base64
import cv2
import numpy as np
from fastapi import FastAPI, File, UploadFile, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

# Ensure project root is in sys.path
PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from src.quality.pipeline import RetinalPipeline
from src.config import get_config

app = FastAPI(
    title="NETRA AI Retinal Screening API",
    description="Upstream Image Quality Gate & Adaptive Enhancement Service",
    version="1.0.0"
)

# Enable CORS for React frontend (http://localhost:5173)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

pipeline = RetinalPipeline()


@app.get("/api/health")
async def health_check():
    """Health check endpoint to verify backend status."""
    return {
        "status": "healthy",
        "service": "NETRA Retinal Quality & Preprocessing Engine",
        "version": "1.0.0"
    }


@app.get("/api/samples")
async def get_sample_images():
    """Return available pre-loaded sample images for instant one-click testing."""
    sample_dir = PROJECT_ROOT / "data" / "sample_images"
    samples = []
    
    if sample_dir.exists():
        for img_path in sorted(sample_dir.glob("*.png")):
            # Skip large temporary user test files if any
            if "user_test" in img_path.name:
                continue
            samples.append({
                "filename": img_path.name,
                "label": f"Sample Retina ({img_path.stem[:8]})"
            })
            
    return {"samples": samples}


@app.post("/api/screen")
async def screen_retinal_image(file: UploadFile = File(...)):
    """
    Process an uploaded retinal fundus photograph through:
    1. Quality Gate (Blur, Exposure, FOV checks)
    2. Recapture Alert generation (if failed)
    3. Quality-Adaptive Enhancement & Standardization (if passed)
    """
    try:
        contents = await file.read()
        nparr = np.frombuffer(contents, np.uint8)
        img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)

        if img is None:
            raise HTTPException(status_code=400, detail="Invalid image file or unsupported format.")

        image_id = file.filename or "uploaded_scan"
        result = pipeline.process(img, image_id=image_id)

        enhanced_b64 = None
        if result["status"] == "ACCEPTED" and result["enhanced_image"] is not None:
            # Convert float32 [0, 1] tensor back to uint8 BGR for JPEG transmission
            enhanced_uint8 = np.clip(result["enhanced_image"] * 255.0, 0, 255).astype(np.uint8)
            success, buffer = cv2.imencode(".jpg", enhanced_uint8, [int(cv2.IMWRITE_JPEG_QUALITY), 92])
            if success:
                enhanced_b64 = base64.b64encode(buffer).decode("utf-8")

        response_data = {
            "status": result["status"],
            "image_id": image_id,
            "quality_passed": result["quality_passed"],
            "fail_codes": result["quality_report"]["fail_codes"],
            "metrics": result["quality_report"]["metrics"],
            "recapture_alert": result.get("recapture_alert"),
            "enhancement_metadata": result.get("enhancement_metadata"),
            "enhanced_image_base64": enhanced_b64
        }

        return JSONResponse(content=response_data)

    except Exception as e:
        return JSONResponse(
            status_code=500,
            content={"status": "ERROR", "message": str(e)}
        )


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("src.api.server:app", host="0.0.0.0", port=8000, reload=True)
