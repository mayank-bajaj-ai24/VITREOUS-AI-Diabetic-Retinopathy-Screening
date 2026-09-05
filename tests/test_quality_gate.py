import pytest
import cv2
import numpy as np
import glob
import os

from src.quality.quality_gate import QualityGate
from src.quality.synthetic_degradation import SyntheticDegradation
from src.quality.recapture_alert import RecaptureAlert
from src.config import get_config

@pytest.fixture(scope="module")
def sample_image():
    """Load the first sample image as a numpy array."""
    # Ensure working dir is project root
    images = glob.glob("data/sample_images/*.png")
    if not images:
        pytest.skip("No sample images found in data/sample_images/")
    img = cv2.imread(images[0])
    if img is None:
        pytest.skip(f"Failed to load image: {images[0]}")
    return img

@pytest.fixture(scope="module")
def quality_gate():
    """Instantiate QualityGate with default config."""
    # Set testing thresholds to match config
    config = get_config()
    return QualityGate(config_dict=config)

def test_original_passes_gate(quality_gate, sample_image):
    """Test that the pristine original sample image passes the quality gate."""
    gray = cv2.cvtColor(sample_image, cv2.COLOR_BGR2GRAY)
    
    focus_res = quality_gate.check_focus(gray)
    assert focus_res['passed'] is True, f"Original failed focus: {focus_res}"
    
    fov_res = quality_gate.check_fov(gray)
    assert fov_res['passed'] is True, f"Original failed fov: {fov_res}"
    
    exposure_res = quality_gate.check_exposure(gray, fov_res['mask'])
    assert exposure_res['passed'] is True, f"Original failed exposure: {exposure_res}"

def test_synthetic_blur_fails(quality_gate, sample_image):
    """Test that a synthetically blurred image fails the focus check."""
    blurred = SyntheticDegradation.apply_gaussian_blur(sample_image, kernel_size=31)
    gray = cv2.cvtColor(blurred, cv2.COLOR_BGR2GRAY)
    
    focus_res = quality_gate.check_focus(gray)
    assert focus_res['passed'] is False
    assert focus_res['fail_code'] == "FAIL_BLUR"

def test_synthetic_underexposure_fails(quality_gate, sample_image):
    """Test that an underexposed image fails the exposure check."""
    dark = SyntheticDegradation.apply_underexposure(sample_image, factor=0.2)
    gray = cv2.cvtColor(dark, cv2.COLOR_BGR2GRAY)
    
    fov_res = quality_gate.check_fov(gray)
    exposure_res = quality_gate.check_exposure(gray, fov_res['mask'])
    
    assert exposure_res['passed'] is False
    assert exposure_res['fail_code'] == "FAIL_UNDEREXPOSED"

def test_synthetic_overexposure_fails(quality_gate, sample_image):
    """Test that an overexposed image fails the exposure check."""
    bright = SyntheticDegradation.apply_overexposure(sample_image, gamma=0.1)
    gray = cv2.cvtColor(bright, cv2.COLOR_BGR2GRAY)
    
    fov_res = quality_gate.check_fov(gray)
    exposure_res = quality_gate.check_exposure(gray, fov_res['mask'])
    
    assert exposure_res['passed'] is False
    assert exposure_res['fail_code'] == "FAIL_OVEREXPOSED"

def test_synthetic_fov_fails(quality_gate, sample_image):
    """Test that a heavily shifted/cropped image fails the FOV check."""
    # Shift completely off center
    h, w = sample_image.shape[:2]
    cropped = SyntheticDegradation.apply_fov_crop(sample_image, shift_x=int(w*0.5), shift_y=int(h*0.5))
    gray = cv2.cvtColor(cropped, cv2.COLOR_BGR2GRAY)
    
    fov_res = quality_gate.check_fov(gray)
    assert fov_res['passed'] is False
    assert fov_res['fail_code'] == "FAIL_FOV"

def test_recapture_alert_prioritization():
    """Test that RecaptureAlert correctly prioritizes failure codes."""
    # FOV is most severe, should be primary action
    feedback = RecaptureAlert.generate_feedback(["FAIL_BLUR", "FAIL_FOV", "FAIL_UNDEREXPOSED"])
    assert feedback['status'] == "REJECTED"
    assert feedback['all_actions'][0]['code'] == "FAIL_FOV"
    assert feedback['all_actions'][1]['code'] == "FAIL_BLUR"
    assert feedback['all_actions'][2]['code'] == "FAIL_UNDEREXPOSED"

def test_assess_image_pipeline(quality_gate):
    """Test the end-to-end assess_image function on a real image."""
    images = glob.glob("data/sample_images/*.png")
    if not images:
        pytest.skip("No sample images found")
        
    report = quality_gate.assess_image(images[0])
    
    assert "is_passed" in report
    assert "fail_codes" in report
    assert "metrics" in report
    assert "fov" in report["metrics"]
    assert "focus" in report["metrics"]
    assert "exposure" in report["metrics"]
