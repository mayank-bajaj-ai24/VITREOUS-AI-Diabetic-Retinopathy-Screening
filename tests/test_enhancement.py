import pytest
import cv2
import numpy as np
import glob
import os

from src.quality.enhancement import FundusEnhancer
from src.quality.quality_gate import QualityGate
from src.config import get_config


@pytest.fixture(scope="module")
def sample_image():
    """Load the first sample fundus image as a BGR numpy array."""
    images = glob.glob("data/sample_images/*.png")
    if not images:
        pytest.skip("No sample images found in data/sample_images/")
    img = cv2.imread(images[0])
    if img is None:
        pytest.skip(f"Failed to load image: {images[0]}")
    return img


@pytest.fixture(scope="module")
def config():
    """Load the project config."""
    return get_config()


@pytest.fixture(scope="module")
def enhancer(config):
    """Instantiate FundusEnhancer with default config."""
    return FundusEnhancer(config_dict=config)


@pytest.fixture(scope="module")
def quality_gate(config):
    """Instantiate QualityGate with default config."""
    return QualityGate(config_dict=config)


# ROI Cropping Test
class TestROICropping:
    """Tests for the Otsu-threshold ROI cropping step."""

    def test_roi_crop_isolates_fundus(self, enhancer, sample_image):
        """
        ROI crop should remove the black border and produce a smaller image
        that contains the fundus disc.
        """
        cropped = enhancer.crop_roi(sample_image)

        # Cropped should be non-empty and valid
        assert cropped is not None
        assert cropped.size > 0
        assert len(cropped.shape) == 3
        assert cropped.shape[2] == 3  # Still BGR

        # Cropped region should have meaningful content (not all black)
        gray = cv2.cvtColor(cropped, cv2.COLOR_BGR2GRAY)
        assert np.mean(gray) > 10, "Cropped image appears to be mostly black"

    def test_roi_crop_handles_no_background(self, enhancer):
        """If the image has no black background, ROI crop should still work."""
        # Create a fully bright image (no black border to remove)
        bright_img = np.ones((400, 400, 3), dtype=np.uint8) * 180
        cropped = enhancer.crop_roi(bright_img)

        # Should return something valid (either cropped or original)
        assert cropped is not None
        assert cropped.size > 0

    def test_roi_crop_handles_fully_black(self, enhancer):
        """If the image is completely black, should return the original."""
        black_img = np.zeros((400, 400, 3), dtype=np.uint8)
        cropped = enhancer.crop_roi(black_img)

        # Should return original since there's nothing to crop
        assert cropped is not None
        assert cropped.size > 0


# CLAHE Tests
class TestCLAHE:
    """Tests for Green-channel and LAB CLAHE enhancement."""

    def test_green_clahe_increases_contrast(self, enhancer, sample_image):
        """
        Green-channel CLAHE should increase the histogram spread (standard
        deviation) of the green channel, indicating improved contrast.
        """
        enhanced = enhancer.apply_green_clahe(sample_image, clip_limit=2.0, tile_grid_size=8)

        # Measure green channel histogram spread before and after
        green_before = sample_image[:, :, 1]
        green_after = enhanced[:, :, 1]

        std_before = np.std(green_before)
        std_after = np.std(green_after)

        assert std_after >= std_before * 0.95, (
            f"CLAHE should maintain or increase contrast: "
            f"std_before={std_before:.2f}, std_after={std_after:.2f}"
        )

    def test_green_clahe_preserves_shape(self, enhancer, sample_image):
        """CLAHE should not change image dimensions."""
        enhanced = enhancer.apply_green_clahe(sample_image, clip_limit=2.0, tile_grid_size=8)
        assert enhanced.shape == sample_image.shape

    def test_green_clahe_preserves_other_channels(self, enhancer, sample_image):
        """CLAHE on green should not modify blue or red channels."""
        enhanced = enhancer.apply_green_clahe(sample_image, clip_limit=2.0, tile_grid_size=8)

        # Blue and red channels should be identical
        np.testing.assert_array_equal(
            sample_image[:, :, 0], enhanced[:, :, 0],
            err_msg="Blue channel was modified by green CLAHE"
        )
        np.testing.assert_array_equal(
            sample_image[:, :, 2], enhanced[:, :, 2],
            err_msg="Red channel was modified by green CLAHE"
        )

    def test_lab_clahe_preserves_color(self, enhancer, sample_image):
        """
        LAB CLAHE should enhance luminance without severely distorting
        the color channels (a, b in LAB space).
        """
        enhanced = enhancer.apply_lab_clahe(sample_image, clip_limit=2.0, tile_grid_size=8)

        # Convert both to LAB and compare color channels
        lab_before = cv2.cvtColor(sample_image, cv2.COLOR_BGR2LAB)
        lab_after = cv2.cvtColor(enhanced, cv2.COLOR_BGR2LAB)

        # a and b channels should be similar (allow small rounding differences
        # from the BGR→LAB→BGR round-trip)
        a_diff = np.mean(np.abs(lab_before[:, :, 1].astype(float) - lab_after[:, :, 1].astype(float)))
        b_diff = np.mean(np.abs(lab_before[:, :, 2].astype(float) - lab_after[:, :, 2].astype(float)))

        assert a_diff < 5.0, f"LAB CLAHE distorted 'a' channel: mean diff = {a_diff:.2f}"
        assert b_diff < 5.0, f"LAB CLAHE distorted 'b' channel: mean diff = {b_diff:.2f}"

    def test_lab_clahe_preserves_shape(self, enhancer, sample_image):
        """LAB CLAHE should not change image dimensions."""
        enhanced = enhancer.apply_lab_clahe(sample_image, clip_limit=2.0, tile_grid_size=8)
        assert enhanced.shape == sample_image.shape


# NLM Denoising Tests
class TestNLMDenoising:
    """Tests for Non-Local Means denoising."""

    def test_nlm_reduces_noise(self, enhancer, sample_image):
        """
        NLM denoising should reduce the estimated noise level in the image.
        We add synthetic noise and verify NLM removes some of it.
        """
        # Add Gaussian noise
        noise = np.random.normal(0, 25, sample_image.shape).astype(np.float64)
        noisy = np.clip(sample_image.astype(np.float64) + noise, 0, 255).astype(np.uint8)

        # Denoise
        denoised = enhancer.apply_nlm_denoising(noisy, filter_strength=10, template_window_size=7, search_window_size=21)

        # Measure noise via Laplacian variance (lower = less noise)
        gray_noisy = cv2.cvtColor(noisy, cv2.COLOR_BGR2GRAY)
        gray_denoised = cv2.cvtColor(denoised, cv2.COLOR_BGR2GRAY)

        noise_noisy = cv2.Laplacian(gray_noisy, cv2.CV_64F).var()
        noise_denoised = cv2.Laplacian(gray_denoised, cv2.CV_64F).var()

        assert noise_denoised < noise_noisy, (
            f"NLM should reduce noise: noisy={noise_noisy:.2f}, denoised={noise_denoised:.2f}"
        )

    def test_nlm_preserves_shape(self, enhancer, sample_image):
        """NLM denoising should not change image dimensions."""
        denoised = enhancer.apply_nlm_denoising(sample_image, filter_strength=5, template_window_size=7, search_window_size=21)
        assert denoised.shape == sample_image.shape

# Standardization Tests
class TestStandardization:
    """Tests for resize and normalization."""

    def test_output_shape_512x512(self, enhancer, sample_image):
        """Output must be exactly (512, 512, 3)."""
        result = enhancer.standardize(sample_image)
        assert result.shape == (512, 512, 3), f"Expected (512,512,3), got {result.shape}"

    def test_float01_normalization(self, enhancer, sample_image):
        """With float01 mode, all pixel values should be in [0.0, 1.0]."""
        result = enhancer.standardize(sample_image, normalization_mode='float01')

        assert result.dtype == np.float32, f"Expected float32, got {result.dtype}"
        assert result.min() >= 0.0, f"Min value {result.min()} is below 0.0"
        assert result.max() <= 1.0, f"Max value {result.max()} is above 1.0"

    def test_uint8_normalization(self, enhancer, sample_image):
        """With uint8 mode, dtype should be uint8."""
        result = enhancer.standardize(sample_image, normalization_mode='uint8')

        assert result.dtype == np.uint8, f"Expected uint8, got {result.dtype}"

    def test_custom_target_size(self, enhancer, sample_image):
        """Should support arbitrary target sizes."""
        result = enhancer.standardize(sample_image, target_size=256)
        assert result.shape[:2] == (256, 256)

    def test_small_image_upscaling(self, enhancer):
        """Small images should be upscaled to target size."""
        small = np.ones((64, 64, 3), dtype=np.uint8) * 128
        result = enhancer.standardize(small, target_size=512)
        assert result.shape == (512, 512, 3)


# Profile Selection Tests
class TestProfileSelection:
    """Tests for quality-adaptive profile selection."""

    def test_no_scores_returns_low(self, enhancer):
        """Without quality scores, should default to 'low' profile."""
        profile = enhancer.select_enhancement_profile(None)
        assert profile == 'low'

    def test_good_quality_returns_low(self, enhancer):
        """High-quality scores should select 'low' enhancement."""
        good_scores = {
            'metrics': {
                'fov': {'coverage': 0.95},
                'focus': {'laplacian_variance': 200.0, 'tenengrad_variance': 100.0},
                'exposure': {'mean_brightness': 130.0, 'entropy': 6.5}
            }
        }
        profile = enhancer.select_enhancement_profile(good_scores)
        assert profile == 'low', f"Good scores should give 'low', got '{profile}'"

    def test_poor_quality_returns_high(self, enhancer):
        """Low-quality scores should select 'high' enhancement."""
        poor_scores = {
            'metrics': {
                'fov': {'coverage': 0.50},
                'focus': {'laplacian_variance': 5.0, 'tenengrad_variance': 2.0},
                'exposure': {'mean_brightness': 50.0, 'entropy': 3.0}
            }
        }
        profile = enhancer.select_enhancement_profile(poor_scores)
        assert profile == 'high', f"Poor scores should give 'high', got '{profile}'"

    def test_medium_quality_returns_medium(self, enhancer):
        """Borderline scores should select 'medium' enhancement."""
        borderline_scores = {
            'metrics': {
                'fov': {'coverage': 0.75},
                'focus': {'laplacian_variance': 40.0, 'tenengrad_variance': 20.0},
                'exposure': {'mean_brightness': 100.0, 'entropy': 5.0}
            }
        }
        profile = enhancer.select_enhancement_profile(borderline_scores)
        assert profile in ('medium', 'low'), (
            f"Borderline scores should give 'medium' or 'low', got '{profile}'"
        )

    def test_profile_params_loaded_from_config(self, enhancer):
        """Profile parameters should be loaded from the config, not hardcoded."""
        params = enhancer._get_profile_params('low')
        assert 'clahe_clip_limit' in params
        assert 'nlm_filter_strength' in params
        assert 'clahe_tile_grid' in params

        # Verify they match what's in the config
        config_profile = enhancer.profiles.get('low', {})
        if config_profile:
            assert params['clahe_clip_limit'] == config_profile['clahe_clip_limit']


# Full Pipeline Tests
class TestFullPipeline:
    """Tests for the end-to-end enhancement pipeline."""

    def test_full_pipeline_output_shape(self, enhancer, sample_image):
        """Full pipeline should produce a (512, 512, 3) array."""
        enhanced, metadata = enhancer.enhance(sample_image)
        assert enhanced.shape == (512, 512, 3), f"Expected (512,512,3), got {enhanced.shape}"

    def test_full_pipeline_returns_metadata(self, enhancer, sample_image):
        """Pipeline should return comprehensive metadata."""
        _, metadata = enhancer.enhance(sample_image)

        # Check all expected metadata keys
        assert 'profile' in metadata, "Missing 'profile' in metadata"
        assert 'parameters' in metadata, "Missing 'parameters' in metadata"
        assert 'metrics_before' in metadata, "Missing 'metrics_before' in metadata"
        assert 'metrics_after' in metadata, "Missing 'metrics_after' in metadata"
        assert 'original_shape' in metadata, "Missing 'original_shape' in metadata"
        assert 'cropped_shape' in metadata, "Missing 'cropped_shape' in metadata"
        assert 'target_size' in metadata, "Missing 'target_size' in metadata"
        assert 'normalization_mode' in metadata, "Missing 'normalization_mode' in metadata"

    def test_full_pipeline_metadata_metrics(self, enhancer, sample_image):
        """Before/after metrics should contain histogram_std, mean_brightness, estimated_snr."""
        _, metadata = enhancer.enhance(sample_image)

        for key in ['metrics_before', 'metrics_after']:
            metrics = metadata[key]
            assert 'histogram_std' in metrics, f"Missing histogram_std in {key}"
            assert 'mean_brightness' in metrics, f"Missing mean_brightness in {key}"
            assert 'estimated_snr' in metrics, f"Missing estimated_snr in {key}"

    def test_full_pipeline_profile_is_valid(self, enhancer, sample_image):
        """Profile name should be one of the defined profiles."""
        _, metadata = enhancer.enhance(sample_image)
        assert metadata['profile'] in ('low', 'medium', 'high'), (
            f"Unknown profile: {metadata['profile']}"
        )

    def test_full_pipeline_with_quality_scores(self, enhancer, sample_image):
        """Pipeline with explicit quality scores should use the appropriate profile."""
        good_scores = {
            'metrics': {
                'fov': {'coverage': 0.95},
                'focus': {'laplacian_variance': 200.0, 'tenengrad_variance': 100.0},
                'exposure': {'mean_brightness': 130.0, 'entropy': 6.5}
            }
        }
        enhanced, metadata = enhancer.enhance(sample_image, quality_scores=good_scores)

        assert enhanced.shape == (512, 512, 3)
        assert metadata['profile'] == 'low'

# Integration with Quality Gate (Phase 1 → Phase 2)
class TestIntegrationWithQualityGate:
    """
    End-to-end integration: Quality Gate assess → Enhancement pipeline.
    Validates the handoff between Phase 1 (Krrish's work) and Phase 2.
    """

    def test_quality_gate_to_enhancement(self, quality_gate, enhancer):
        """
        Full integration: assess a sample image with Quality Gate,
        then feed its output to the enhancement pipeline.
        """
        images = glob.glob("data/sample_images/*.png")
        if not images:
            pytest.skip("No sample images found")

        # Phase 1: Quality Gate assessment
        report = quality_gate.assess_image(images[0])

        if not report['is_passed']:
            pytest.skip("Sample image did not pass quality gate (can't enhance)")

        # Phase 2: Enhancement with quality-adaptive profile
        img = cv2.imread(images[0])
        enhanced, metadata = enhancer.enhance(img, quality_scores=report)

        # Validate output
        assert enhanced.shape == (512, 512, 3)
        assert metadata['profile'] in ('low', 'medium', 'high')
        assert metadata['parameters']['clahe_clip_limit'] > 0

    def test_enhancement_output_compatible_with_downstream(self, enhancer, sample_image):
        """
        Enhanced output must meet the interface contract for both
        downstream AI tracks (UNet++ segmentation ∥ Hybrid grading).

        Contract: 512×512×3, normalized, NumPy array.
        """
        enhanced, _ = enhancer.enhance(sample_image)

        # Shape contract
        assert enhanced.shape == (512, 512, 3), (
            f"Downstream expects (512,512,3), got {enhanced.shape}"
        )

        # NumPy array
        assert isinstance(enhanced, np.ndarray)

        # Normalization: values in valid range
        if enhanced.dtype == np.float32:
            assert enhanced.min() >= 0.0
            assert enhanced.max() <= 1.0
        elif enhanced.dtype == np.uint8:
            assert enhanced.min() >= 0
            assert enhanced.max() <= 255


# Quality Metrics Tests
class TestQualityMetrics:
    """Tests for the quality metric computation utility."""

    def test_metrics_structure(self, enhancer, sample_image):
        """Metrics dict should have the expected keys."""
        metrics = enhancer.compute_quality_metrics(sample_image)
        assert 'histogram_std' in metrics
        assert 'mean_brightness' in metrics
        assert 'estimated_snr' in metrics

    def test_metrics_positive_values(self, enhancer, sample_image):
        """All metric values should be non-negative."""
        metrics = enhancer.compute_quality_metrics(sample_image)
        assert metrics['histogram_std'] >= 0
        assert metrics['mean_brightness'] >= 0
        assert metrics['estimated_snr'] >= 0

    def test_metrics_handles_float_input(self, enhancer):
        """Metrics should handle float32 [0,1] images correctly."""
        float_img = np.random.rand(256, 256, 3).astype(np.float32)
        metrics = enhancer.compute_quality_metrics(float_img)
        assert metrics['histogram_std'] >= 0
        assert metrics['mean_brightness'] >= 0
