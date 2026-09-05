import json
from typing import List, Dict, Any

class RecaptureAlert:
    """
    Translates quality gate failure codes into actionable, human-readable instructions 
    for the clinician or health worker.
    """
    
    # Mapping of fail codes to specific actionable feedback
    FEEDBACK_MAPPING = {
        "FAIL_BLUR": "Hold the camera steady and refocus the lens.",
        "FAIL_UNDEREXPOSED": "Increase the camera flash intensity or room illumination.",
        "FAIL_OVEREXPOSED": "Reduce the camera flash intensity.",
        "FAIL_FOV": "Ask the patient to look straight ahead and recenter the retina in the frame."
    }
    
    # Priority order: which failure is most critical to address first if multiple exist
    SEVERITY_RANKING = {
        "FAIL_FOV": 1,          # Can't see the retina at all
        "FAIL_BLUR": 2,         # Can't see the lesions
        "FAIL_UNDEREXPOSED": 3, # Hard to see details
        "FAIL_OVEREXPOSED": 4   # Washed out
    }

    @classmethod
    def generate_feedback(cls, fail_codes: List[str], image_id: str = "Unknown") -> Dict[str, Any]:
        """
        Generate a structured JSON output with prioritized actionable instructions.
        
        Args:
            fail_codes (List[str]): List of fail codes from QualityGate.
            image_id (str): Identifier for logging purposes.
            
        Returns:
            Dict: Structured feedback response.
        """
        if not fail_codes:
            return {
                "status": "SUCCESS",
                "message": "Image passed quality gate.",
                "actions": []
            }
            
        # Sort fail codes by severity (1 is highest priority)
        sorted_codes = sorted(fail_codes, key=lambda c: cls.SEVERITY_RANKING.get(c, 99))
        
        actions = []
        for code in sorted_codes:
            instruction = cls.FEEDBACK_MAPPING.get(code, "Unknown issue detected.")
            actions.append({
                "code": code,
                "instruction": instruction
            })
            
        result = {
            "status": "REJECTED",
            "image_id": image_id,
            "message": "Image quality insufficient for AI analysis. Recapture required.",
            "primary_action": actions[0]["instruction"] if actions else "Unknown issue",
            "all_actions": actions
        }
        
        return result

    @classmethod
    def log_rejection(cls, image_id: str, report: Dict[str, Any], attempt_count: int = 1) -> str:
        """
        Create a serialized log entry for a rejected image capture.
        
        Args:
            image_id (str): Identifier for the image.
            report (Dict): The full report dict from QualityGate.
            attempt_count (int): How many times this patient has been recaptured this session.
            
        Returns:
            str: JSON formatted log string.
        """
        feedback = cls.generate_feedback(report.get("fail_codes", []), image_id)
        
        log_entry = {
            "event": "QUALITY_GATE_REJECTION",
            "image_id": image_id,
            "attempt_count": attempt_count,
            "fail_codes": report.get("fail_codes", []),
            "feedback_provided": feedback["all_actions"],
            "metrics": report.get("metrics", {})
        }
        
        return json.dumps(log_entry)

# Example Usage
if __name__ == "__main__":
    test_codes = ["FAIL_UNDEREXPOSED", "FAIL_FOV", "FAIL_BLUR"]
    feedback = RecaptureAlert.generate_feedback(test_codes, "IMG_1024")
    print(json.dumps(feedback, indent=2))
