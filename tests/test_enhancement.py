import pytest
import cv2
import numpy as np
import glob
from pathlib import Path

from src.quality.enhancement import (
    crop_fundus_roi,
    apply_clahe,
    apply_nlm_denoising,
    standardize_image,
    estimate_noise_level,
    AdaptiveEnhancer
)
from src.quality.pipeline import RetinalPipeline
from src.quality.synthetic_degradation import SyntheticDegradation
from src.config import get_config


@pytest.fixture(scope="module")
def sample_image():
    """Load a real sample image from data/sample_images/."""
    images = glob.glob("data/sample_images/*.png")
    if not images:
        pytest.skip("No sample images found in data/sample_images/")
    img = cv2.imread(images[0])
    if img is None:
        pytest.skip(f"Failed to load image: {images[0]}")
    return img


@pytest.fixture(scope="module")
def enhancer():
    """Instantiate AdaptiveEnhancer with project configuration."""
    return AdaptiveEnhancer(config_dict=get_config())


def test_crop_fundus_roi(sample_image):
    """Test that ROI crop extracts the fundus disc and reduces dimensions."""
    h_orig, w_orig = sample_image.shape[:2]
    cropped, (x, y, w, h) = crop_fundus_roi(sample_image, margin_pct=0.02)

    assert cropped is not None
    assert cropped.ndim == 3
    # Cropped width and height must be less than or equal to original
    assert w <= w_orig
    assert h <= h_orig
    assert cropped.shape[0] == h
    assert cropped.shape[1] == w
    assert x >= 0 and y >= 0


def test_crop_fallback_on_blank():
    """Test that ROI crop handles blank/empty image gracefully without crashing."""
    blank = np.zeros((200, 200, 3), dtype=np.uint8)
    cropped, bbox = crop_fundus_roi(blank)
    assert cropped.shape == (200, 200, 3)
    assert bbox == (0, 0, 200, 200)


def test_noise_level_estimation(sample_image):
    """Test that estimated noise increases when Gaussian noise is injected."""
    baseline_noise = estimate_noise_level(sample_image)

    # Add Gaussian noise
    noise = np.random.normal(0, 25, sample_image.shape).astype(np.float32)
    noisy_image = np.clip(sample_image.astype(np.float32) + noise, 0, 255).astype(np.uint8)
    noisy_estimated = estimate_noise_level(noisy_image)

    assert noisy_estimated > baseline_noise


def test_clahe_lab_mode(sample_image):
    """Test LAB CLAHE improves local contrast and preserves 3 channels."""
    enhanced = apply_clahe(sample_image, clip_limit=2.5, tile_grid_size=8, mode="lab")

    assert enhanced.shape == sample_image.shape
    assert enhanced.dtype == np.uint8
    # Standard deviation should change or increase with histogram equalization
    assert not np.array_equal(enhanced, sample_image)


def test_clahe_green_mode(sample_image):
    """Test green-channel CLAHE specifically enhances the green channel."""
    enhanced = apply_clahe(sample_image, clip_limit=2.5, tile_grid_size=8, mode="green")

    assert enhanced.shape == sample_image.shape
    # Blue and red channels should remain identical in green mode
    np.testing.assert_array_equal(enhanced[:, :, 0], sample_image[:, :, 0])
    np.testing.assert_array_equal(enhanced[:, :, 2], sample_image[:, :, 2])
    # Green channel should be modified
    assert not np.array_equal(enhanced[:, :, 1], sample_image[:, :, 1])


def test_nlm_denoising(sample_image):
    """Test NLM denoising runs and produces an image of the same shape."""
    # Run on a smaller patch for test speed
    patch = sample_image[:128, :128].copy()
    denoised = apply_nlm_denoising(patch, h=5.0, template_window=7, search_window=21)

    assert denoised.shape == patch.shape
    assert denoised.dtype == np.uint8


def test_standardize_image_data_contract(sample_image):
    """
    CRITICAL TEST: Verify downstream data contract for UNet++ and EfficientNet.
    Contract: Exactly (512, 512, 3), np.float32, normalized to [0.0, 1.0].
    """
    standardized = standardize_image(
        sample_image,
        target_size=512,
        preserve_aspect=True,
        normalization_mode="float01"
    )

    assert standardized.shape == (512, 512, 3), f"Expected (512, 512, 3), got {standardized.shape}"
    assert standardized.dtype == np.float32, f"Expected float32, got {standardized.dtype}"
    assert standardized.min() >= 0.0, "Values must be >= 0.0"
    assert standardized.max() <= 1.0, "Values must be <= 1.0"


def test_standardize_uint8_mode(sample_image):
    """Test that standardization also supports uint8 [0, 255] if configured."""
    standardized = standardize_image(
        sample_image,
        target_size=256,
        preserve_aspect=True,
        normalization_mode="uint8"
    )

    assert standardized.shape == (256, 256, 3)
    assert standardized.dtype == np.uint8
    assert standardized.max() <= 255


def test_adaptive_profile_selection(enhancer):
    """Test dynamic selection of low, medium, and high profiles."""
    # Poor quality report -> high enhancement
    poor_metrics = {
        "focus": {"laplacian_variance": 5.0},
        "exposure": {"entropy": 2.5}
    }
    profile_poor = enhancer.select_profile(poor_metrics)
    assert profile_poor == "high"

    # Borderline quality report -> medium enhancement
    borderline_metrics = {
        "focus": {"laplacian_variance": 15.0},
        "exposure": {"entropy": 4.5}
    }
    profile_med = enhancer.select_profile(borderline_metrics)
    assert profile_med == "medium"

    # Pristine quality report -> low enhancement
    good_metrics = {
        "focus": {"laplacian_variance": 40.0},
        "exposure": {"entropy": 7.0}
    }
    profile_good = enhancer.select_profile(good_metrics)
    assert profile_good == "low"


def test_adaptive_enhancer_full_flow(enhancer, sample_image):
    """Test full AdaptiveEnhancer.enhance() method."""
    result = enhancer.enhance(sample_image)

    assert "enhanced_image" in result
    assert "original_shape" in result
    assert "crop_bbox" in result
    assert "profile_used" in result
    assert "parameters" in result
    assert "noise_level" in result

    img_out = result["enhanced_image"]
    assert img_out.shape == (512, 512, 3)
    assert img_out.dtype == np.float32
    assert 0.0 <= img_out.min() <= img_out.max() <= 1.0


def test_end_to_end_pipeline_accepted(sample_image):
    """Test RetinalPipeline on a valid image: Quality Gate PASS -> Enhancement SUCCESS."""
    pipeline = RetinalPipeline()
    result = pipeline.process(sample_image, image_id="valid_test_01")

    assert result["status"] == "ACCEPTED"
    assert result["quality_passed"] is True
    assert result["recapture_alert"] is None
    assert result["enhanced_image"] is not None
    assert result["enhanced_image"].shape == (512, 512, 3)
    assert result["enhanced_image"].dtype == np.float32


def test_end_to_end_pipeline_rejected_on_degraded(sample_image):
    """Test RetinalPipeline on a blurred image: Quality Gate FAIL -> Recapture Alert."""
    blurred = SyntheticDegradation.apply_gaussian_blur(sample_image, kernel_size=35)
    pipeline = RetinalPipeline()
    result = pipeline.process(blurred, image_id="blurred_test_02")

    assert result["status"] == "REJECTED"
    assert result["quality_passed"] is False
    assert result["enhanced_image"] is None
    assert result["recapture_alert"] is not None
    assert result["recapture_alert"]["status"] == "REJECTED"
    assert "FAIL_BLUR" in [a["code"] for a in result["recapture_alert"]["all_actions"]]
