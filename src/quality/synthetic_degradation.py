import cv2
import numpy as np

class SyntheticDegradation:
    """
    Applies synthetic noise, blur, and exposure changes to fundus images 
    to validate the quality gate thresholds.
    """

    @staticmethod
    def apply_gaussian_blur(image: np.ndarray, kernel_size: int = 15) -> np.ndarray:
        """Apply severe Gaussian blur (e.g. out of focus camera)."""
        # Kernel size must be odd
        k = kernel_size if kernel_size % 2 == 1 else kernel_size + 1
        return cv2.GaussianBlur(image, (k, k), 0)

    @staticmethod
    def apply_motion_blur(image: np.ndarray, kernel_size: int = 15) -> np.ndarray:
        """Apply directional motion blur (e.g. patient moved during capture)."""
        kernel_motion_blur = np.zeros((kernel_size, kernel_size))
        kernel_motion_blur[int((kernel_size-1)/2), :] = np.ones(kernel_size)
        kernel_motion_blur = kernel_motion_blur / kernel_size
        return cv2.filter2D(image, -1, kernel_motion_blur)

    @staticmethod
    def apply_underexposure(image: np.ndarray, factor: float = 0.2) -> np.ndarray:
        """
        Simulate poor flash/dark room. 
        Multiplies the image intensity by a factor < 1.
        """
        return cv2.convertScaleAbs(image, alpha=factor, beta=0)

    @staticmethod
    def apply_overexposure(image: np.ndarray, gamma: float = 0.4) -> np.ndarray:
        """
        Simulate flash glare/overexposure. 
        Gamma < 1 brightens the image.
        """
        table = np.array([((i / 255.0) ** gamma) * 255
                          for i in np.arange(0, 256)]).astype("uint8")
        return cv2.LUT(image, table)

    @staticmethod
    def apply_fov_crop(image: np.ndarray, shift_x: int = 200, shift_y: int = 100) -> np.ndarray:
        """
        Simulate off-center capture where part of the retina is cut off.
        Shifts the image pixels and pads with black.
        """
        rows, cols = image.shape[:2]
        M = np.float32([[1, 0, shift_x], [0, 1, shift_y]])
        return cv2.warpAffine(image, M, (cols, rows), borderValue=(0,0,0))

    @staticmethod
    def generate_all_degradations(image: np.ndarray) -> dict:
        """Generate a dictionary of all degradations for testing."""
        return {
            "original": image,
            "blur_gaussian": SyntheticDegradation.apply_gaussian_blur(image, 31),
            "blur_motion": SyntheticDegradation.apply_motion_blur(image, 25),
            "underexposed": SyntheticDegradation.apply_underexposure(image, 4.0),
            "overexposed": SyntheticDegradation.apply_overexposure(image, 0.2),
            "fov_cropped": SyntheticDegradation.apply_fov_crop(image, 400, 200)
        }

if __name__ == "__main__":
    # Test degradation visualizer
    import sys
    import os
    
    if len(sys.argv) > 1:
        img_path = sys.argv[1]
    else:
        # Default to first sample image
        import glob
        img_path = glob.glob("data/sample_images/*.png")[0]
        
    img = cv2.imread(img_path)
    if img is None:
        print("Image not found")
        sys.exit(1)
        
    degraded = SyntheticDegradation.generate_all_degradations(img)
    
    # Save outputs to data/sample_images for review
    base_name = os.path.basename(img_path).split('.')[0]
    out_dir = "data/sample_images/degraded"
    os.makedirs(out_dir, exist_ok=True)
    
    for name, d_img in degraded.items():
        if name != "original":
            out_path = f"{out_dir}/{base_name}_{name}.png"
            cv2.imwrite(out_path, d_img)
            print(f"Saved {out_path}")
