"""
NETRA — Quality-Adaptive Enhancement & Normalization Module (Phase 2)

Performs:
1. Otsu-threshold ROI cropping (extracts circular retinal disc, removes black margins).
2. Quality-adaptive parameter selection (low, medium, high profiles based on quality scores).
3. Contrast-Limited Adaptive Histogram Equalization (CLAHE) in LAB color space or Green channel.
4. Non-Local Means (NLM) denoising with edge preservation.
5. Standardized 512x512 resolution with letterbox aspect-ratio preservation and [0, 1] normalization.
"""

import cv2
import numpy as np
import logging
from typing import Dict, Any, Tuple, Optional, Union
from pathlib import Path

from src.config import get_config

logger = logging.getLogger(__name__)


def crop_fundus_roi(
    image: np.ndarray,
    margin_pct: float = 0.02
) -> Tuple[np.ndarray, Tuple[int, int, int, int]]:
    """
    Extract the illuminated circular fundus ROI using Otsu thresholding and
    connected component analysis, stripping away empty black borders.

    Args:
        image (np.ndarray): Input fundus image (BGR, RGB, or Grayscale).
        margin_pct (float): Safety margin percentage around the bounding box.

    Returns:
        Tuple[np.ndarray, Tuple[int, int, int, int]]:
            - Cropped image.
            - Bounding box tuple (x, y, w, h).
    """
    if image is None or image.size == 0:
        raise ValueError("Invalid or empty image provided to crop_fundus_roi.")

    h_img, w_img = image.shape[:2]

    # Convert to grayscale if 3-channel
    if image.ndim == 3:
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    else:
        gray = image.copy()

    # Otsu thresholding to segment illuminated disc from background
    _, thresh = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)

    # Morphological closing to fill optical disc / dark macular depression holes
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (15, 15))
    closed = cv2.morphologyEx(thresh, cv2.MORPH_CLOSE, kernel)

    # Find connected components to isolate the primary retinal disc
    num_labels, labels, stats, _ = cv2.connectedComponentsWithStats(closed)

    # Fallback if no valid foreground found
    if num_labels <= 1:
        logger.warning("No foreground component found during ROI crop. Returning original image.")
        return image.copy(), (0, 0, w_img, h_img)

    # Find the largest non-background component (index 0 is background)
    largest_idx = 1
    max_area = stats[1, cv2.CC_STAT_AREA]
    for i in range(2, num_labels):
        area = stats[i, cv2.CC_STAT_AREA]
        if area > max_area:
            max_area = area
            largest_idx = i

    # Fallback if largest component is trivially small (< 1% of image)
    if max_area < (0.01 * h_img * w_img):
        logger.warning("Largest component too small for fundus disc. Returning original image.")
        return image.copy(), (0, 0, w_img, h_img)

    # Extract bounding box of the fundus disc
    x = int(stats[largest_idx, cv2.CC_STAT_LEFT])
    y = int(stats[largest_idx, cv2.CC_STAT_TOP])
    w = int(stats[largest_idx, cv2.CC_STAT_WIDTH])
    h = int(stats[largest_idx, cv2.CC_STAT_HEIGHT])

    # Apply safety margin
    pad_x = int(w * margin_pct)
    pad_y = int(h * margin_pct)

    x1 = max(0, x - pad_x)
    y1 = max(0, y - pad_y)
    x2 = min(w_img, x + w + pad_x)
    y2 = min(h_img, y + h + pad_y)

    cropped = image[y1:y2, x1:x2]
    return cropped, (x1, y1, x2 - x1, y2 - y1)


def estimate_noise_level(image: np.ndarray) -> float:
    """
    Estimate image noise level (sigma) using Median Absolute Deviation (MAD)
    of the high-frequency Laplacian response.

    Args:
        image (np.ndarray): Input image.

    Returns:
        float: Estimated noise standard deviation sigma.
    """
    if image.ndim == 3:
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    else:
        gray = image.copy()

    lap = cv2.Laplacian(gray, cv2.CV_64F)
    # MAD estimator: sigma = median(|lap - median(lap)|) / 0.6745
    median_val = np.median(lap)
    mad = np.median(np.abs(lap - median_val))
    sigma = float(mad / 0.6745)
    return sigma


def apply_clahe(
    image: np.ndarray,
    clip_limit: float = 2.5,
    tile_grid_size: int = 8,
    mode: str = "lab"
) -> np.ndarray:
    """
    Apply Contrast-Limited Adaptive Histogram Equalization (CLAHE).

    Modes:
      - 'lab': Applies CLAHE to the L (Luminance) channel in CIE-LAB space,
               preserving clinical retinal color and lesion pigments.
      - 'green': Applies CLAHE specifically to the Green channel (highest
                 retinal vascular contrast).

    Args:
        image (np.ndarray): Input image (uint8, BGR or Grayscale).
        clip_limit (float): Threshold for contrast limiting.
        tile_grid_size (int): Size of the grid for histogram equalization.
        mode (str): 'lab' or 'green'.

    Returns:
        np.ndarray: Contrast-enhanced image.
    """
    if image.dtype != np.uint8:
        # Scale to uint8 if float
        image_uint8 = np.clip(image * 255.0 if image.max() <= 1.0 else image, 0, 255).astype(np.uint8)
    else:
        image_uint8 = image.copy()

    grid = (int(tile_grid_size), int(tile_grid_size))
    clahe = cv2.createCLAHE(clipLimit=float(clip_limit), tileGridSize=grid)

    if image_uint8.ndim == 2:
        return clahe.apply(image_uint8)

    if mode.lower() == "green":
        # Apply to Green channel (channel index 1 in BGR/RGB)
        enhanced = image_uint8.copy()
        enhanced[:, :, 1] = clahe.apply(image_uint8[:, :, 1])
        return enhanced

    # Default 'lab' mode: Color-preserving luminance equalization
    lab = cv2.cvtColor(image_uint8, cv2.COLOR_BGR2LAB)
    l_channel, a_channel, b_channel = cv2.split(lab)
    l_enhanced = clahe.apply(l_channel)
    lab_enhanced = cv2.merge([l_enhanced, a_channel, b_channel])
    enhanced_bgr = cv2.cvtColor(lab_enhanced, cv2.COLOR_LAB2BGR)
    return enhanced_bgr


def apply_nlm_denoising(
    image: np.ndarray,
    h: float = 8.0,
    template_window: int = 7,
    search_window: int = 21
) -> np.ndarray:
    """
    Apply Non-Local Means (NLM) denoising to suppress camera sensor noise
    while preserving delicate microvascular edges.

    Args:
        image (np.ndarray): Input uint8 image.
        h (float): Filter strength. Higher h removes more noise but may blur details.
        template_window (int): Size in pixels of the template patch (odd number).
        search_window (int): Size in pixels of the area where patches are searched (odd number).

    Returns:
        np.ndarray: Denoised image.
    """
    if image.dtype != np.uint8:
        image_uint8 = np.clip(image * 255.0 if image.max() <= 1.0 else image, 0, 255).astype(np.uint8)
    else:
        image_uint8 = image

    # Windows must be odd integers
    t_win = int(template_window) if int(template_window) % 2 == 1 else int(template_window) + 1
    s_win = int(search_window) if int(search_window) % 2 == 1 else int(search_window) + 1
    h_val = max(1.0, float(h))

    if image_uint8.ndim == 3:
        denoised = cv2.fastNlMeansDenoisingColored(
            image_uint8,
            None,
            h=h_val,
            hColor=h_val,
            templateWindowSize=t_win,
            searchWindowSize=s_win
        )
    else:
        denoised = cv2.fastNlMeansDenoising(
            image_uint8,
            None,
            h=h_val,
            templateWindowSize=t_win,
            searchWindowSize=s_win
        )

    return denoised


def standardize_image(
    image: np.ndarray,
    target_size: int = 512,
    preserve_aspect: bool = True,
    normalization_mode: str = "float01"
) -> np.ndarray:
    """
    Resize image to target_size x target_size with optional letterbox padding
    and pixel value normalization.

    Args:
        image (np.ndarray): Input image.
        target_size (int): Target square dimension (default: 512).
        preserve_aspect (bool): If True, preserves aspect ratio with black letterbox borders.
        normalization_mode (str): 'float01' ([0.0, 1.0] float32) or 'uint8' ([0, 255] uint8).

    Returns:
        np.ndarray: Standardized array with shape (target_size, target_size, C).
    """
    h, w = image.shape[:2]

    if preserve_aspect:
        scale = target_size / max(h, w)
        new_w = max(1, int(round(w * scale)))
        new_h = max(1, int(round(h * scale)))

        # Use area interpolation for downsampling, cubic for upsampling
        interp = cv2.INTER_AREA if scale < 1.0 else cv2.INTER_CUBIC
        resized = cv2.resize(image, (new_w, new_h), interpolation=interp)

        # Create centered black canvas
        if image.ndim == 3:
            canvas = np.zeros((target_size, target_size, image.shape[2]), dtype=image.dtype)
        else:
            canvas = np.zeros((target_size, target_size), dtype=image.dtype)

        start_y = (target_size - new_h) // 2
        start_x = (target_size - new_w) // 2
        canvas[start_y:start_y + new_h, start_x:start_x + new_w] = resized
        standardized = canvas
    else:
        interp = cv2.INTER_AREA if (target_size < w or target_size < h) else cv2.INTER_CUBIC
        standardized = cv2.resize(image, (target_size, target_size), interpolation=interp)

    # Normalize output format
    if normalization_mode == "float01":
        if standardized.dtype == np.uint8:
            return (standardized.astype(np.float32) / 255.0)
        else:
            return np.clip(standardized.astype(np.float32), 0.0, 1.0)
    elif normalization_mode == "uint8":
        if standardized.dtype != np.uint8:
            return np.clip(standardized * 255.0 if standardized.max() <= 1.0 else standardized, 0, 255).astype(np.uint8)
        return standardized
    else:
        raise ValueError(f"Unsupported normalization mode: {normalization_mode}")


class AdaptiveEnhancer:
    """
    End-to-End Quality-Adaptive Retinal Enhancement Engine.
    Coordinates ROI cropping, adaptive parameter selection, CLAHE, NLM denoising,
    and 512x512 standardization.
    """

    def __init__(self, config_dict: Optional[Dict[str, Any]] = None):
        """Initialize with configuration dictionary."""
        if config_dict is None:
            config_dict = get_config()

        self.full_config = config_dict
        self.enh_config = config_dict.get('enhancement', {})

        self.target_size = int(self.enh_config.get('target_size', 512))
        self.normalization_mode = self.enh_config.get('normalization_mode', 'float01')
        self.clahe_mode = self.enh_config.get('clahe_mode', 'lab')
        self.margin_pct = float(self.enh_config.get('crop_margin_pct', 0.02))

        # Profiles
        self.profiles = self.enh_config.get('profiles', {
            'low': {'clahe_clip_limit': 1.5, 'clahe_tile_grid': 8, 'nlm_filter_strength': 5, 'nlm_template_window': 7, 'nlm_search_window': 21},
            'medium': {'clahe_clip_limit': 2.5, 'clahe_tile_grid': 8, 'nlm_filter_strength': 8, 'nlm_template_window': 7, 'nlm_search_window': 21},
            'high': {'clahe_clip_limit': 4.0, 'clahe_tile_grid': 8, 'nlm_filter_strength': 12, 'nlm_template_window': 7, 'nlm_search_window': 21}
        })

        self.profile_selection_cfg = self.enh_config.get('profile_selection', {
            'high_threshold': 0.5,
            'medium_threshold': 0.7
        })

    def select_profile(
        self,
        quality_metrics: Optional[Dict[str, Any]] = None,
        estimated_noise: Optional[float] = None
    ) -> str:
        """
        Dynamically determine whether to use 'low', 'medium', or 'high' profile.

        Selection heuristic:
        - If QualityGate focus/exposure are near lower boundaries or noise is elevated -> 'high'
        - If borderline -> 'medium'
        - If clear and high contrast -> 'low'
        """
        if quality_metrics is None:
            # Default to medium if no upstream report available
            return 'medium'

        # Inspect metrics from Phase 1 report
        focus_info = quality_metrics.get('focus', {})
        exposure_info = quality_metrics.get('exposure', {})

        lap_var = focus_info.get('laplacian_variance', 50.0)
        entropy = exposure_info.get('entropy', 5.0)

        # Compute a composite quality score [0.0, 1.0]
        # Low entropy (< 4.0) or low sharpness (< 10.0) indicates poor contrast/clarity
        sharpness_score = min(1.0, lap_var / 30.0)
        entropy_score = min(1.0, entropy / 6.5)
        composite_score = 0.5 * sharpness_score + 0.5 * entropy_score

        # Factor in noise level if provided
        if estimated_noise is not None and estimated_noise > 12.0:
            composite_score *= 0.8

        high_thresh = self.profile_selection_cfg.get('high_threshold', 0.5)
        med_thresh = self.profile_selection_cfg.get('medium_threshold', 0.7)

        if composite_score < high_thresh:
            return 'high'
        elif composite_score < med_thresh:
            return 'medium'
        else:
            return 'low'

    def enhance(
        self,
        image_input: Union[str, Path, np.ndarray],
        quality_metrics: Optional[Dict[str, Any]] = None,
        profile_override: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Run the complete enhancement pipeline.

        Args:
            image_input: File path or np.ndarray image.
            quality_metrics: Optional metrics from QualityGate.assess_image().
            profile_override: Explicitly force 'low', 'medium', or 'high' profile.

        Returns:
            Dict containing:
                - 'enhanced_image': Standardized (512, 512, 3) image
                - 'original_shape': Tuple of original dimensions
                - 'crop_bbox': Bounding box (x, y, w, h)
                - 'profile_used': Selected profile name
                - 'parameters': Profile parameters applied
                - 'noise_level': Estimated noise sigma
        """
        # Load image if path provided
        if isinstance(image_input, (str, Path)):
            img = cv2.imread(str(image_input))
            if img is None:
                raise ValueError(f"Could not load image at {image_input}")
        elif isinstance(image_input, np.ndarray):
            img = image_input.copy()
        else:
            raise TypeError("image_input must be a file path or numpy array.")

        orig_shape = img.shape

        # 1. Otsu ROI Cropping
        cropped, bbox = crop_fundus_roi(img, margin_pct=self.margin_pct)

        # 2. Noise Level Estimation
        noise_level = estimate_noise_level(cropped)

        # 3. Profile Selection
        if profile_override and profile_override in self.profiles:
            profile_name = profile_override
        else:
            profile_name = self.select_profile(quality_metrics, noise_level)

        params = self.profiles.get(profile_name, self.profiles['medium'])

        # 4. CLAHE
        clahe_enhanced = apply_clahe(
            cropped,
            clip_limit=params.get('clahe_clip_limit', 2.5),
            tile_grid_size=params.get('clahe_tile_grid', 8),
            mode=self.clahe_mode
        )

        # 5. Non-Local Means Denoising
        denoised = apply_nlm_denoising(
            clahe_enhanced,
            h=params.get('nlm_filter_strength', 8.0),
            template_window=params.get('nlm_template_window', 7),
            search_window=params.get('nlm_search_window', 21)
        )

        # 6. Standardization to 512x512
        standardized = standardize_image(
            denoised,
            target_size=self.target_size,
            preserve_aspect=True,
            normalization_mode=self.normalization_mode
        )

        logger.info(
            f"Enhanced image from {orig_shape} to {standardized.shape} "
            f"(Profile: {profile_name}, Noise: {noise_level:.2f})"
        )

        return {
            "enhanced_image": standardized,
            "original_shape": orig_shape,
            "crop_bbox": bbox,
            "profile_used": profile_name,
            "parameters": params,
            "noise_level": noise_level,
            "target_size": (self.target_size, self.target_size),
            "normalization_mode": self.normalization_mode
        }
