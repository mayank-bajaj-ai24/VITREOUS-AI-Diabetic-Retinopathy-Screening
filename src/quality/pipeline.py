"""
NETRA — End-to-End Retinal Quality & Preprocessing Pipeline
Chains Phase 1 (Quality Gate) and Phase 2 (Adaptive Enhancement) into a unified workflow.
"""

import cv2
import numpy as np
import logging
from typing import Dict, Any, Union, Optional
from pathlib import Path

from src.quality.quality_gate import QualityGate
from src.quality.recapture_alert import RecaptureAlert
from src.quality.enhancement import AdaptiveEnhancer
from src.config import get_config

logger = logging.getLogger(__name__)


class RetinalPipeline:
    """
    Unified upstream screening pipeline for NETRA.
    Evaluates image gradability, triggers alerts on failure, and produces
    standardized (512x512x3) normalized inputs for AI segmentation & grading models.
    """

    def __init__(self, config_dict: Optional[Dict[str, Any]] = None):
        if config_dict is None:
            config_dict = get_config()

        self.config = config_dict
        self.quality_gate = QualityGate(config_dict=self.config)
        self.enhancer = AdaptiveEnhancer(config_dict=self.config)

    def process(
        self,
        image_input: Union[str, Path, np.ndarray],
        image_id: str = "sample"
    ) -> Dict[str, Any]:
        """
        Execute the complete upstream pipeline on an input fundus image.

        Args:
            image_input: File path or np.ndarray image.
            image_id: Unique identifier for tracking and logging.

        Returns:
            Dict containing pipeline results, status, feedback, and tensor-ready image.
        """
        # Load image if file path
        if isinstance(image_input, (str, Path)):
            img = cv2.imread(str(image_input))
            if img is None:
                raise ValueError(f"Failed to read image at {image_input}")
        elif isinstance(image_input, np.ndarray):
            img = image_input.copy()
        else:
            raise TypeError("image_input must be a file path or numpy array.")

        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY) if img.ndim == 3 else img.copy()

        # Step 1: Field of View check (and extract mask)
        fov_result = self.quality_gate.check_fov(gray)
        mask = fov_result.pop('mask', None)

        # Step 2: Focus / Sharpness check
        focus_result = self.quality_gate.check_focus(gray)

        # Step 3: Exposure / Illumination check
        exposure_result = self.quality_gate.check_exposure(gray, mask)

        fail_codes = []
        for res in [fov_result, focus_result, exposure_result]:
            if res.get('fail_code'):
                fail_codes.append(res['fail_code'])

        is_passed = len(fail_codes) == 0

        quality_report = {
            "is_passed": is_passed,
            "fail_codes": fail_codes,
            "metrics": {
                "fov": fov_result,
                "focus": focus_result,
                "exposure": exposure_result
            }
        }

        # If image fails quality gate, generate recapture instructions and halt
        if not is_passed:
            alert = RecaptureAlert.generate_feedback(fail_codes, image_id=image_id)
            logger.warning(f"Image {image_id} rejected by Quality Gate: {fail_codes}")
            return {
                "status": "REJECTED",
                "image_id": image_id,
                "quality_passed": False,
                "recapture_alert": alert,
                "quality_report": quality_report,
                "enhanced_image": None,
                "enhancement_metadata": None
            }

        # Step 4: If quality gate passes, run quality-adaptive enhancement
        logger.info(f"Image {image_id} passed Quality Gate. Enhancing...")
        enhancement_res = self.enhancer.enhance(
            img,
            quality_metrics=quality_report["metrics"]
        )

        return {
            "status": "ACCEPTED",
            "image_id": image_id,
            "quality_passed": True,
            "recapture_alert": None,
            "quality_report": quality_report,
            "enhanced_image": enhancement_res["enhanced_image"],
            "enhancement_metadata": {
                "original_shape": enhancement_res["original_shape"],
                "crop_bbox": enhancement_res["crop_bbox"],
                "profile_used": enhancement_res["profile_used"],
                "noise_level": enhancement_res["noise_level"],
                "parameters": enhancement_res["parameters"]
            }
        }
