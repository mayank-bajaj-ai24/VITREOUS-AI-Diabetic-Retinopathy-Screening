import cv2
import numpy as np
import logging
from typing import Dict, Any, List

from src.config import get_config

# Configure logging
logger = logging.getLogger(__name__)

class QualityGate:
    """
    Quality Gate for fundus image screening.
    Checks for: Focus (blur), Illumination (exposure), and Field of View (coverage).
    """

    def __init__(self, config_dict=None):
        """Initialize with configuration thresholds."""
        if config_dict is None:
            config_dict = get_config()
        self.config = config_dict.get('quality_gate', {})
        self.blur_cfg = self.config.get('blur', {})
        self.exposure_cfg = self.config.get('exposure', {})
        self.fov_cfg = self.config.get('fov', {})

    def check_focus(self, image_gray: np.ndarray) -> Dict[str, Any]:
        """
        Check image sharpness using Laplacian variance and Tenengrad gradient.
        
        Args:
            image_gray (np.ndarray): Grayscale fundus image.
            
        Returns:
            Dict: Result containing pass/fail and scores.
        """
        # 1. Laplacian Variance
        laplacian_var = cv2.Laplacian(image_gray, cv2.CV_64F).var()
        
        # 2. Tenengrad Gradient (Sobel)
        sobel_x = cv2.Sobel(image_gray, cv2.CV_64F, 1, 0, ksize=3)
        sobel_y = cv2.Sobel(image_gray, cv2.CV_64F, 0, 1, ksize=3)
        tenengrad_var = np.mean(sobel_x**2 + sobel_y**2)
        
        # Combined evaluation
        min_lap_var = self.blur_cfg.get('laplacian_variance_min', 100.0)
        min_tenengrad = self.blur_cfg.get('tenengrad_min', 50.0)
        
        passed = bool(laplacian_var >= min_lap_var and tenengrad_var >= min_tenengrad)
        
        return {
            "passed": passed,
            "laplacian_variance": float(laplacian_var),
            "tenengrad_variance": float(tenengrad_var),
            "fail_code": "FAIL_BLUR" if not passed else None
        }

    def check_exposure(self, image_gray: np.ndarray, mask: np.ndarray = None) -> Dict[str, Any]:
        """
        Check image illumination and exposure levels inside the FOV mask.
        
        Args:
            image_gray (np.ndarray): Grayscale fundus image.
            mask (np.ndarray, optional): FOV mask to exclude background.
            
        Returns:
            Dict: Result containing pass/fail and scores.
        """
        if mask is not None:
            mean_brightness = cv2.mean(image_gray, mask=mask)[0]
        else:
            mean_brightness = np.mean(image_gray)
            
        min_bright = self.exposure_cfg.get('brightness_min', 40)
        max_bright = self.exposure_cfg.get('brightness_max', 220)
        
        fail_code = None
        passed = True
        
        if mean_brightness < min_bright:
            passed = False
            fail_code = "FAIL_UNDEREXPOSED"
        elif mean_brightness > max_bright:
            passed = False
            fail_code = "FAIL_OVEREXPOSED"
            
        # Optional: Histogram Uniformity check
        if mask is not None:
            hist = cv2.calcHist([image_gray], [0], mask, [256], [0, 256])
        else:
            hist = cv2.calcHist([image_gray], [0], None, [256], [0, 256])
            
        hist = hist.ravel() / hist.sum()
        # Entropy as a measure of histogram spread (uniformity)
        entropy = -np.sum(hist * np.log2(hist + 1e-7))
        uniformity_min = self.exposure_cfg.get('histogram_uniformity_min', 0.3)
        
        # Note: entropy is generally between 0 and 8 for 8-bit images. 
        # We'll just record it for now, and strictly fail on brightness limits.
        
        return {
            "passed": passed,
            "mean_brightness": float(mean_brightness),
            "entropy": float(entropy),
            "fail_code": fail_code
        }

    def check_fov(self, image_gray: np.ndarray) -> Dict[str, Any]:
        """
        Check the Field of View (FOV) coverage and centering.
        Extracts circular fundus mask using Otsu thresholding.
        
        Args:
            image_gray (np.ndarray): Grayscale fundus image.
            
        Returns:
            Dict: Result containing pass/fail, fov coverage, and the generated mask.
        """
        h, w = image_gray.shape
        total_pixels = h * w
        
        # Otsu thresholding to find the bright fundus disc against black background
        _, mask = cv2.threshold(image_gray, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
        
        # Morphological closing to fill holes in the mask
        kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (15, 15))
        mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, kernel)
        
        # Calculate coverage area
        fov_area = cv2.countNonZero(mask)
        coverage = fov_area / total_pixels
        
        # Check coverage
        min_coverage = self.fov_cfg.get('coverage_min', 0.50)
        
        # Check centering via moments
        M = cv2.moments(mask)
        if M["m00"] != 0:
            cX = int(M["m10"] / M["m00"])
            cY = int(M["m01"] / M["m00"])
        else:
            cX, cY = w // 2, h // 2
            
        # Offset from center as fraction of image width/height
        offset_x = abs(cX - w / 2) / w
        offset_y = abs(cY - h / 2) / h
        max_offset = self.fov_cfg.get('centering_max_offset', 0.20)
        
        passed = bool(coverage >= min_coverage and offset_x <= max_offset and offset_y <= max_offset)
        
        return {
            "passed": passed,
            "coverage": float(coverage),
            "centroid_offset_x": float(offset_x),
            "centroid_offset_y": float(offset_y),
            "mask": mask,
            "fail_code": "FAIL_FOV" if not passed else None
        }

    def assess_image(self, image_path: str) -> Dict[str, Any]:
        """
        Run all quality checks on an image.
        
        Args:
            image_path (str): Path to the image file.
            
        Returns:
            Dict: Comprehensive quality assessment report.
        """
        img = cv2.imread(image_path)
        if img is None:
            raise ValueError(f"Could not load image at {image_path}")
            
        # Convert to grayscale for structural checks
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        
        # 1. FOV Check (Run first to get the mask)
        fov_res = self.check_fov(gray)
        mask = fov_res.pop('mask') # Extract mask for exposure check
        
        # 2. Focus Check
        focus_res = self.check_focus(gray)
        
        # 3. Exposure Check (using FOV mask to ignore black background)
        exposure_res = self.check_exposure(gray, mask)
        
        # Compile final results
        fail_codes = []
        for res in [fov_res, focus_res, exposure_res]:
            if res.get('fail_code'):
                fail_codes.append(res['fail_code'])
                
        is_passed = len(fail_codes) == 0
        
        report = {
            "is_passed": is_passed,
            "fail_codes": fail_codes,
            "metrics": {
                "fov": fov_res,
                "focus": focus_res,
                "exposure": exposure_res
            }
        }
        
        # Log outcome
        if is_passed:
            logger.info(f"Image {image_path} passed quality gate.")
        else:
            logger.warning(f"Image {image_path} failed quality gate. Reasons: {fail_codes}")
            
        return report

# For manual testing
if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    gate = QualityGate()
    
    import glob
    # Test on the sample images we downloaded
    sample_images = glob.glob("data/sample_images/*.png")
    for img_path in sample_images:
        print(f"\\n--- Testing {img_path} ---")
        try:
            res = gate.assess_image(img_path)
            print(f"Pass: {res['is_passed']}")
            print(f"Fail Codes: {res['fail_codes']}")
            print(f"Blur (Laplacian): {res['metrics']['focus']['laplacian_variance']:.2f}")
            print(f"Brightness: {res['metrics']['exposure']['mean_brightness']:.2f}")
            print(f"FOV Coverage: {res['metrics']['fov']['coverage']:.2f}")
        except Exception as e:
            print(f"Error processing {img_path}: {e}")
