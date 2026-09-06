import cv2
import numpy as np
import logging
from typing import Dict, Any, Optional, Tuple

from src.config import get_config

logger = logging.getLogger(__name__)


class FundusEnhancer:
    """
    Quality-adaptive enhancement pipeline for fundus images.

    Reads all parameters from the 'enhancement' section of the project config.
    Follows the same config-injection pattern as QualityGate.
    """

    def __init__(self, config_dict: Optional[Dict] = None):
        """
        Initialize the enhancer with configuration parameters.

        Args:
            config_dict: Full config dictionary. If None, loads from
                         configs/default_config.yaml via get_config().
        """
        if config_dict is None:
            config_dict = get_config()

        self.config = config_dict.get('enhancement', {})
        self.target_size = self.config.get('target_size', 512)
        self.normalization_mode = self.config.get('normalization_mode', 'float01')
        self.profiles = self.config.get('profiles', {})
        self.profile_selection = self.config.get('profile_selection', {})

    # Step 1: ROI Cropping
    def crop_roi(self, image: np.ndarray) -> np.ndarray:
        """
        Isolate the fundus disc from the black background using Otsu thresholding.

        Process:
            1. Convert to grayscale
            2. Otsu binary threshold to separate fundus from background
            3. Morphological closing to fill holes
            4. Find the largest connected component (the fundus disc)
            5. Compute bounding box and crop

        Args:
            image: BGR fundus image (H×W×3, uint8).

        Returns:
            Cropped BGR image containing only the fundus disc region.
            Returns the original image if no valid ROI is found.
        """
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)

        # Otsu threshold to find the bright fundus against black background
        _, binary_mask = cv2.threshold(
            gray, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU
        )

        # Morphological closing to fill small holes in the mask
        kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (15, 15))
        binary_mask = cv2.morphologyEx(binary_mask, cv2.MORPH_CLOSE, kernel)

        # Find connected components — pick the largest one (the fundus disc)
        num_labels, labels, stats, _ = cv2.connectedComponentsWithStats(
            binary_mask, connectivity=8
        )

        if num_labels <= 1:
            # No foreground found — return original
            logger.warning("ROI crop: no foreground detected, returning original.")
            return image

        # Skip label 0 (background), find the component with the largest area
        component_areas = stats[1:, cv2.CC_STAT_AREA]
        largest_idx = np.argmax(component_areas) + 1  # +1 to offset skipping bg

        # Extract bounding box of the largest component
        x = stats[largest_idx, cv2.CC_STAT_LEFT]
        y = stats[largest_idx, cv2.CC_STAT_TOP]
        w = stats[largest_idx, cv2.CC_STAT_WIDTH]
        h = stats[largest_idx, cv2.CC_STAT_HEIGHT]

        # Add a small margin (2% of each dimension) to avoid cutting edges
        margin_x = max(int(w * 0.02), 1)
        margin_y = max(int(h * 0.02), 1)

        x_start = max(x - margin_x, 0)
        y_start = max(y - margin_y, 0)
        x_end = min(x + w + margin_x, image.shape[1])
        y_end = min(y + h + margin_y, image.shape[0])

        cropped = image[y_start:y_end, x_start:x_end]

        # Safety check: if crop is too small, return original
        if cropped.size == 0 or cropped.shape[0] < 10 or cropped.shape[1] < 10:
            logger.warning("ROI crop: result too small, returning original.")
            return image

        logger.info(
            f"ROI crop: {image.shape[:2]} → {cropped.shape[:2]} "
            f"(bbox: x={x_start}:{x_end}, y={y_start}:{y_end})"
        )
        return cropped

    # Step 2: Green-Channel CLAHE
    
    def apply_green_clahe(
        self,
        image: np.ndarray,
        clip_limit: float,
        tile_grid_size: int
    ) -> np.ndarray:
        """
        Apply CLAHE to the green channel of a BGR fundus image.

        The green channel carries the strongest vascular and lesion contrast
        in fundus photography, making it the ideal target for enhancement.

        Args:
            image:          BGR fundus image (H×W×3, uint8).
            clip_limit:     CLAHE contrast limiting threshold.
            tile_grid_size: Size of the grid for histogram equalization.

        Returns:
            BGR image with CLAHE-enhanced green channel.
        """
        # Split channels
        b, g, r = cv2.split(image)

        # Create and apply CLAHE to the green channel
        clahe = cv2.createCLAHE(
            clipLimit=clip_limit,
            tileGridSize=(tile_grid_size, tile_grid_size)
        )
        g_enhanced = clahe.apply(g)

        # Merge back
        enhanced = cv2.merge([b, g_enhanced, r])

        logger.debug(
            f"Green CLAHE applied: clip={clip_limit}, grid={tile_grid_size}x{tile_grid_size}"
        )
        return enhanced

    def apply_lab_clahe(
        self,
        image: np.ndarray,
        clip_limit: float,
        tile_grid_size: int
    ) -> np.ndarray:
        """
        Apply CLAHE on the L-channel of LAB color space for color-preserved
        contrast enhancement.

        This variant enhances luminance without distorting color information,
        useful when color fidelity is critical for downstream analysis.

        Args:
            image:          BGR fundus image (H×W×3, uint8).
            clip_limit:     CLAHE contrast limiting threshold.
            tile_grid_size: Size of the grid for histogram equalization.

        Returns:
            BGR image with CLAHE-enhanced luminance.
        """
        # Convert BGR → LAB
        lab = cv2.cvtColor(image, cv2.COLOR_BGR2LAB)
        l_channel, a_channel, b_channel = cv2.split(lab)

        # Apply CLAHE to L channel
        clahe = cv2.createCLAHE(
            clipLimit=clip_limit,
            tileGridSize=(tile_grid_size, tile_grid_size)
        )
        l_enhanced = clahe.apply(l_channel)

        # Merge and convert back to BGR
        lab_enhanced = cv2.merge([l_enhanced, a_channel, b_channel])
        enhanced = cv2.cvtColor(lab_enhanced, cv2.COLOR_LAB2BGR)

        logger.debug(
            f"LAB CLAHE applied: clip={clip_limit}, grid={tile_grid_size}x{tile_grid_size}"
        )
        return enhanced

    # Step 3: Non-Local Means Denoising
    
    def apply_nlm_denoising(
        self,
        image: np.ndarray,
        filter_strength: int,
        template_window_size: int,
        search_window_size: int
    ) -> np.ndarray:
        """
        Apply Non-Local Means denoising for colored images.

        NLM preserves edges better than Gaussian/median filters by averaging
        similar patches across the image rather than just local neighborhoods.

        Args:
            image:                BGR fundus image (H×W×3, uint8).
            filter_strength:      Filter strength (h). Higher removes more noise
                                  but may blur fine details.
            template_window_size: Size of the template patch (should be odd).
            search_window_size:   Size of the area to search for similar patches
                                  (should be odd).

        Returns:
            Denoised BGR image.
        """
        # Use positional args for cross-version OpenCV compatibility
        # Signature: src, dst, h, hForColorComponents, templateWindowSize, searchWindowSize
        denoised = cv2.fastNlMeansDenoisingColored(
            image,
            None,
            filter_strength,
            filter_strength,
            template_window_size,
            search_window_size
        )

        logger.debug(
            f"NLM denoising applied: h={filter_strength}, "
            f"template={template_window_size}, search={search_window_size}"
        )
        return denoised

    # Step 4: Standardization (Resize + Normalize)
    def standardize(
        self,
        image: np.ndarray,
        target_size: Optional[int] = None,
        normalization_mode: Optional[str] = None
    ) -> np.ndarray:
        """
        Resize to target dimensions and normalize pixel values.

        Args:
            image:              BGR image (H×W×3).
            target_size:        Output dimension (square). Defaults to config value.
            normalization_mode: 'float01' for [0.0, 1.0] float32, or
                                'uint8' for [0, 255] uint8. Defaults to config.

        Returns:
            Standardized image as NumPy array (target_size × target_size × 3).
        """
        size = target_size if target_size is not None else self.target_size
        mode = normalization_mode if normalization_mode is not None else self.normalization_mode

        # Resize using INTER_AREA for downscaling (anti-aliasing),
        # INTER_LINEAR for upscaling (smooth interpolation)
        h, w = image.shape[:2]
        if h > size or w > size:
            interpolation = cv2.INTER_AREA
        else:
            interpolation = cv2.INTER_LINEAR

        resized = cv2.resize(image, (size, size), interpolation=interpolation)

        # Normalize
        if mode == 'float01':
            standardized = resized.astype(np.float32) / 255.0
        else:
            # Ensure uint8
            standardized = resized.astype(np.uint8)

        logger.debug(
            f"Standardized: {image.shape} → {standardized.shape}, mode={mode}"
        )
        return standardized

    # Quality-Adaptive Profile Selection
   
    def select_enhancement_profile(
        self, quality_scores: Optional[Dict[str, Any]] = None
    ) -> str:
        """
        Select enhancement intensity profile based on Quality Gate scores.

        The profile determines how aggressively enhancement is applied:
          - 'low':    Good image quality → minimal enhancement
          - 'medium': Borderline quality → moderate enhancement
          - 'high':   Near-rejection quality → aggressive enhancement

        Profile selection uses a composite quality score derived from the
        Quality Gate's FOV coverage, focus, and exposure metrics.

        Args:
            quality_scores: Quality Gate metrics dict. Expected structure:
                {
                    'metrics': {
                        'fov': {'coverage': float},
                        'focus': {'laplacian_variance': float, 'tenengrad_variance': float},
                        'exposure': {'mean_brightness': float, 'entropy': float}
                    }
                }
                If None, defaults to 'low' profile (assumes good quality).

        Returns:
            Profile name: 'low', 'medium', or 'high'.
        """
        if quality_scores is None:
            return 'low'

        metrics = quality_scores.get('metrics', {})

        # Extract individual quality indicators and normalize to [0, 1]
        fov_data = metrics.get('fov', {})
        focus_data = metrics.get('focus', {})
        exposure_data = metrics.get('exposure', {})

        # FOV coverage is already in [0, 1]
        fov_score = fov_data.get('coverage', 1.0)

        # Normalize focus: use Laplacian variance.
        # Typical range for good fundus images: 3-500+
        # We clamp and normalize against a reasonable upper bound
        lap_var = focus_data.get('laplacian_variance', 100.0)
        focus_score = min(lap_var / 100.0, 1.0)

        # Normalize exposure: how close to ideal midpoint (128) on 0-255 scale
        brightness = exposure_data.get('mean_brightness', 128.0)
        # Score = 1.0 at ideal brightness (128), drops toward 0 at extremes
        exposure_score = 1.0 - abs(brightness - 128.0) / 128.0
        exposure_score = max(exposure_score, 0.0)

        # Composite quality score (weighted average)
        composite = 0.4 * fov_score + 0.35 * focus_score + 0.25 * exposure_score

        # Map composite to profile using config thresholds
        high_threshold = self.profile_selection.get('high_threshold', 0.5)
        medium_threshold = self.profile_selection.get('medium_threshold', 0.7)

        if composite < high_threshold:
            profile = 'high'
        elif composite < medium_threshold:
            profile = 'medium'
        else:
            profile = 'low'

        logger.info(
            f"Profile selection: composite={composite:.3f} "
            f"(fov={fov_score:.2f}, focus={focus_score:.2f}, exposure={exposure_score:.2f}) "
            f"→ '{profile}'"
        )
        return profile

    def _get_profile_params(self, profile_name: str) -> Dict[str, Any]:
        """
        Retrieve enhancement parameters for the given profile name.

        Args:
            profile_name: One of 'low', 'medium', 'high'.

        Returns:
            Dict with keys: clahe_clip_limit, clahe_tile_grid,
            nlm_filter_strength, nlm_template_window, nlm_search_window.
        """
        # Default fallback parameters (only used if config is missing)
        defaults = {
            'clahe_clip_limit': 2.0,
            'clahe_tile_grid': 8,
            'nlm_filter_strength': 7,
            'nlm_template_window': 7,
            'nlm_search_window': 21
        }

        profile = self.profiles.get(profile_name, defaults)

        return {
            'clahe_clip_limit': profile.get('clahe_clip_limit', defaults['clahe_clip_limit']),
            'clahe_tile_grid': profile.get('clahe_tile_grid', defaults['clahe_tile_grid']),
            'nlm_filter_strength': profile.get('nlm_filter_strength', defaults['nlm_filter_strength']),
            'nlm_template_window': profile.get('nlm_template_window', defaults['nlm_template_window']),
            'nlm_search_window': profile.get('nlm_search_window', defaults['nlm_search_window']),
        }

    # Quality Metrics (Before/After Comparison)
    def compute_quality_metrics(self, image: np.ndarray) -> Dict[str, float]:
        """
        Compute quality metrics for before/after comparison.

        Metrics:
          - histogram_std:    Standard deviation of pixel intensity histogram
                              (higher = more contrast spread)
          - mean_brightness:  Average pixel intensity
          - estimated_snr:    Estimated signal-to-noise ratio using Laplacian
                              method (higher = cleaner image)

        Args:
            image: BGR image (uint8 or float32). If float32, auto-converts.

        Returns:
            Dict with metric name → value.
        """
        # Ensure uint8 for consistent measurements
        if image.dtype == np.float32 or image.dtype == np.float64:
            measure_img = (image * 255).clip(0, 255).astype(np.uint8)
        else:
            measure_img = image

        gray = cv2.cvtColor(measure_img, cv2.COLOR_BGR2GRAY)

        # Histogram spread (contrast indicator)
        histogram_std = float(np.std(gray))

        # Mean brightness
        mean_brightness = float(np.mean(gray))

        # Estimated SNR via Laplacian noise estimation
        # Noise σ ≈ median(|Laplacian|) / 0.6745 (robust estimator)
        laplacian = cv2.Laplacian(gray, cv2.CV_64F)
        noise_sigma = np.median(np.abs(laplacian)) / 0.6745
        # SNR = mean_signal / noise (avoid division by zero)
        estimated_snr = float(mean_brightness / max(noise_sigma, 1e-6))

        return {
            'histogram_std': histogram_std,
            'mean_brightness': mean_brightness,
            'estimated_snr': estimated_snr
        }

    # Full Pipeline Orchestrator
    def enhance(
        self,
        image: np.ndarray,
        quality_scores: Optional[Dict[str, Any]] = None
    ) -> Tuple[np.ndarray, Dict[str, Any]]:
        """
        Run the full quality-adaptive enhancement pipeline.

        Pipeline:
            1. ROI Crop — isolate fundus disc from black background
            2. Green-Channel CLAHE — enhance vascular/lesion contrast
            3. NLM Denoising — reduce noise while preserving edges
            4. Standardize — resize to 512×512 and normalize

        Enhancement strength adapts based on Quality Gate scores via profile
        selection (low / medium / high).

        Args:
            image:          Raw BGR fundus image (H×W×3, uint8).
            quality_scores: Quality Gate output dict (from QualityGate.assess_image).
                            Used to select enhancement profile. If None, uses 'low'
                            profile (minimal enhancement for good-quality images).

        Returns:
            Tuple of:
                - enhanced_image: Standardized NumPy array (512×512×3), ready for
                                  both UNet++ and Hybrid Grading model input.
                - metadata: Dict containing:
                    - profile: Enhancement profile used ('low'/'medium'/'high')
                    - parameters: Actual CLAHE/NLM parameters applied
                    - metrics_before: Quality metrics of the input image
                    - metrics_after: Quality metrics of the enhanced image
                    - original_shape: Original image dimensions
                    - cropped_shape: Dimensions after ROI crop
        """
        # Record before-enhancement metrics
        metrics_before = self.compute_quality_metrics(image)
        original_shape = image.shape[:2]

        # 1. Select enhancement profile
        profile_name = self.select_enhancement_profile(quality_scores)
        params = self._get_profile_params(profile_name)

        logger.info(
            f"Enhancement pipeline starting: profile='{profile_name}', "
            f"input_shape={image.shape[:2]}"
        )

        # 2. ROI Crop
        cropped = self.crop_roi(image)
        cropped_shape = cropped.shape[:2]

        # 3. Green-Channel CLAHE
        clahe_enhanced = self.apply_green_clahe(
            cropped,
            clip_limit=params['clahe_clip_limit'],
            tile_grid_size=params['clahe_tile_grid']
        )

        # 4. NLM Denoising
        denoised = self.apply_nlm_denoising(
            clahe_enhanced,
            filter_strength=params['nlm_filter_strength'],
            template_window_size=params['nlm_template_window'],
            search_window_size=params['nlm_search_window']
        )

        # 5. Standardize (resize + normalize)
        standardized = self.standardize(denoised)

        # Record after-enhancement metrics
        metrics_after = self.compute_quality_metrics(standardized)

        metadata = {
            'profile': profile_name,
            'parameters': params,
            'metrics_before': metrics_before,
            'metrics_after': metrics_after,
            'original_shape': original_shape,
            'cropped_shape': cropped_shape,
            'target_size': self.target_size,
            'normalization_mode': self.normalization_mode
        }

        logger.info(
            f"Enhancement complete: profile='{profile_name}', "
            f"output_shape={standardized.shape}, "
            f"contrast_before={metrics_before['histogram_std']:.1f} → "
            f"after={metrics_after['histogram_std']:.1f}"
        )

        return standardized, metadata


# Convenience: standalone usage and visual verification
if __name__ == "__main__":
    import glob
    import os

    logging.basicConfig(level=logging.INFO)

    enhancer = FundusEnhancer()

    sample_images = glob.glob("data/sample_images/*.png")
    if not sample_images:
        print("No sample images found in data/sample_images/")
        exit(1)

    for img_path in sample_images:
        print(f"\n{'='*60}")
        print(f"Processing: {img_path}")
        print(f"{'='*60}")

        img = cv2.imread(img_path)
        if img is None:
            print(f"  Failed to load image")
            continue

        enhanced, metadata = enhancer.enhance(img)

        print(f"  Profile: {metadata['profile']}")
        print(f"  Original: {metadata['original_shape']}")
        print(f"  Cropped:  {metadata['cropped_shape']}")
        print(f"  Output:   {enhanced.shape}")
        print(f"  Contrast: {metadata['metrics_before']['histogram_std']:.1f} → "
              f"{metadata['metrics_after']['histogram_std']:.1f}")
        print(f"  SNR:      {metadata['metrics_before']['estimated_snr']:.2f} → "
              f"{metadata['metrics_after']['estimated_snr']:.2f}")

        # Save enhanced output for visual inspection
        out_dir = "data/sample_images/enhanced"
        os.makedirs(out_dir, exist_ok=True)
        base_name = os.path.basename(img_path).split('.')[0]

        # Save as uint8 for visualization regardless of normalization mode
        if enhanced.dtype == np.float32 or enhanced.dtype == np.float64:
            save_img = (enhanced * 255).clip(0, 255).astype(np.uint8)
        else:
            save_img = enhanced

        out_path = os.path.join(out_dir, f"{base_name}_enhanced.png")
        cv2.imwrite(out_path, save_img)
        print(f"  Saved: {out_path}")
