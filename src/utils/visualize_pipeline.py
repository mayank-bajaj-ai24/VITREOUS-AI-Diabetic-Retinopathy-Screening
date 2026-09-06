"""
NETRA — Pipeline Visualization Utility
Generates clinical diagnostic comparison figures illustrating:
1. Original image with detected Otsu ROI bounding box.
2. Standardized 512x512 enhanced output.
3. Pre vs. Post CLAHE histogram dynamic range comparison.
4. Quality gate & adaptive enhancement metrics dashboard.
"""

import os
import glob
import cv2
import numpy as np
import matplotlib.pyplot as plt
from pathlib import Path
from typing import Optional

from src.quality.pipeline import RetinalPipeline
from src.config import get_config


def visualize_enhancement_result(
    image_path: str,
    output_dir: str = "data/processed",
    save_filename: str = "pipeline_visualization.png"
) -> str:
    """
    Run the complete pipeline on an image and create a 4-panel diagnostic comparison.
    """
    os.makedirs(output_dir, exist_ok=True)
    out_fig_path = os.path.join(output_dir, save_filename)

    pipeline = RetinalPipeline()
    result = pipeline.process(image_path)

    # Read original image in RGB
    orig_bgr = cv2.imread(image_path)
    if orig_bgr is None:
        raise ValueError(f"Could not load {image_path}")
    orig_rgb = cv2.cvtColor(orig_bgr, cv2.COLOR_BGR2RGB)

    # Prepare bounding box visualization
    bbox_img = orig_rgb.copy()
    if result["status"] == "ACCEPTED":
        bbox = result["enhancement_metadata"]["crop_bbox"]
        x, y, w, h = bbox
        cv2.rectangle(bbox_img, (x, y), (x + w, y + h), (0, 255, 0), 4)
        enhanced_float = result["enhanced_image"]
        enhanced_rgb = cv2.cvtColor((enhanced_float * 255.0).astype(np.uint8), cv2.COLOR_BGR2RGB)
    else:
        enhanced_rgb = np.zeros((512, 512, 3), dtype=np.uint8)

    # Create figure
    fig, axes = plt.subplots(2, 2, figsize=(14, 12))
    fig.patch.set_facecolor('#0f172a')  # Dark sleek background

    # 1. Original Image with ROI Bounding Box
    axes[0, 0].imshow(bbox_img)
    axes[0, 0].set_title("1. Raw Input & Otsu ROI Bounding Box", color='white', fontsize=12, fontweight='bold', pad=10)
    axes[0, 0].axis('off')

    # 2. Enhanced Standardized Output (512x512)
    axes[0, 1].imshow(enhanced_rgb)
    status_label = result["status"]
    axes[0, 1].set_title(f"2. Enhanced Output (512x512x3) — Status: {status_label}", color='#38bdf8', fontsize=12, fontweight='bold', pad=10)
    axes[0, 1].axis('off')

    # 3. Histogram Comparison (Green Channel)
    axes[1, 0].set_facecolor('#1e293b')
    orig_green = orig_rgb[:, :, 1].ravel()
    enh_green = enhanced_rgb[:, :, 1].ravel()

    # Exclude zero background pixels from histogram comparison
    orig_green_nonzero = orig_green[orig_green > 10]
    enh_green_nonzero = enh_green[enh_green > 10]

    axes[1, 0].hist(orig_green_nonzero, bins=64, color='#94a3b8', alpha=0.6, label='Pre-Enhancement (Green)', density=True)
    axes[1, 0].hist(enh_green_nonzero, bins=64, color='#10b981', alpha=0.6, label='Post-CLAHE Enhanced (Green)', density=True)
    axes[1, 0].set_title("3. Green-Channel Intensity Histogram Shift", color='white', fontsize=12, fontweight='bold', pad=10)
    axes[1, 0].set_xlabel("Pixel Intensity (0-255)", color='#94a3b8')
    axes[1, 0].set_ylabel("Density", color='#94a3b8')
    axes[1, 0].tick_params(colors='#94a3b8')
    axes[1, 0].legend(loc='upper right', facecolor='#0f172a', edgecolor='#334155', labelcolor='white')
    axes[1, 0].grid(True, linestyle='--', alpha=0.2, color='#64748b')

    # 4. Metrics & Profile Dashboard
    axes[1, 1].set_facecolor('#1e293b')
    axes[1, 1].axis('off')

    metrics = result["quality_report"]["metrics"]
    metadata = result.get("enhancement_metadata") or {}

    summary_text = (
        "═══════════════════════════════════════\n"
        "   NETRA PREPROCESSING DIAGNOSTIC REPORT\n"
        "═══════════════════════════════════════\n\n"
        f" • Overall Status:       {result['status']}\n"
        f" • Quality Gate Passed:  {result['quality_passed']}\n\n"
        "── Quality Gate Metrics ────────────────\n"
        f" • Blur (Laplacian Var): {metrics['focus']['laplacian_variance']:.2f}\n"
        f" • Tenengrad Variance:   {metrics['focus']['tenengrad_variance']:.2f}\n"
        f" • Mean Brightness:      {metrics['exposure']['mean_brightness']:.2f}\n"
        f" • Histogram Entropy:    {metrics['exposure']['entropy']:.2f}\n"
        f" • FOV Retinal Coverage: {metrics['fov']['coverage']*100:.1f}%\n"
        f" • Centroid Offset (X,Y):({metrics['fov']['centroid_offset_x']:.2f}, {metrics['fov']['centroid_offset_y']:.2f})\n\n"
        "── Adaptive Enhancement (Phase 2) ──────\n"
        f" • Selected Profile:     {metadata.get('profile_used', 'N/A').upper()}\n"
        f" • CLAHE Clip Limit:     {metadata.get('parameters', {}).get('clahe_clip_limit', 'N/A')}\n"
        f" • NLM Filter Strength:  {metadata.get('parameters', {}).get('nlm_filter_strength', 'N/A')}\n"
        f" • Noise Level (Sigma):  {metadata.get('noise_level', 0.0):.2f}\n"
        f" • Downstream Tensor:    (512, 512, 3) float32 [0.0, 1.0]\n"
    )

    axes[1, 1].text(
        0.05, 0.95, summary_text,
        transform=axes[1, 1].transAxes,
        fontsize=10,
        fontfamily='monospace',
        verticalalignment='top',
        color='#f8fafc',
        bbox=dict(boxstyle='round,pad=0.8', facecolor='#0f172a', edgecolor='#3b82f6', alpha=0.9)
    )

    plt.tight_layout()
    plt.savefig(out_fig_path, dpi=200, bbox_inches='tight', facecolor=fig.get_facecolor())
    plt.close()

    # Also save the pure enhanced image
    if result["status"] == "ACCEPTED":
        enhanced_out_path = os.path.join(output_dir, "enhanced_sample_512.png")
        cv2.imwrite(enhanced_out_path, (result["enhanced_image"] * 255.0).astype(np.uint8))

    return out_fig_path


if __name__ == "__main__":
    sample_images = glob.glob("data/sample_images/*.png")
    if sample_images:
        path = visualize_enhancement_result(sample_images[0])
        print(f"Visualization saved to: {path}")
    else:
        print("No sample images found.")
