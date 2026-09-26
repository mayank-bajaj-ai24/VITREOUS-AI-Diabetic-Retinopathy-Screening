import os
import sys
import json
import time
import traceback
import subprocess
import tempfile
import base64
from flask import Flask, request, jsonify
from flask_cors import CORS
import vitreous_pipeline

app = Flask(__name__)
CORS(app)

PROJECT_ROOT = os.path.dirname(os.path.abspath(__file__))
MATLAB_DIR = os.path.join(PROJECT_ROOT, 'matlab')

@app.route('/api/analyze', methods=['POST'])
def analyze():
    data = request.json
    if not data or 'image' not in data:
        return jsonify({"status": "Error", "message": "No image payload provided."}), 400

    base64_payload = data['image']

    try:
        print("[API] Received analysis request. Processing fundus image...")
        t_start = time.time()

        # 1. Strip data URI prefix and decode base64 bytes
        raw_b64 = base64_payload.split(',', 1)[-1] if ',' in base64_payload else base64_payload
        img_bytes = base64.b64decode(raw_b64)

        # 2. Run the high-performance VITREOUS pipeline (Quality Gate + Enhancement + DR Grading + Grad-CAM)
        result = vitreous_pipeline.process_fundus_analysis(img_bytes)
        
        elapsed = time.time() - t_start
        print(f"[API] Pipeline finished in {elapsed:.2f}s with status: {result.get('status')}")

        if result.get('status') == 'Error':
            return jsonify(result), 400

        print(f"[API] Success! Grade: {result.get('grade')} ({result.get('grade_name')}), Confidence: {result.get('confidence'):.1%}, Quality: {result.get('quality_score'):.1f}")
        return jsonify(result), 200

    except Exception as e:
        traceback.print_exc()
        return jsonify({"status": "Error", "message": str(e)}), 500


@app.route('/api/health', methods=['GET'])
def health():
    """Quick check to verify server is active."""
    return jsonify({
        "status": "ok",
        "engine": "vitreous-pipeline",
        "model": "v4_resnet18/stub",
        "version": "1.0.0"
    })


if __name__ == '__main__':
    print("=======================================")
    print("  VITREOUS Python Backend API is running! ")
    print("  Pipeline: Quality Gate + CLAHE + DR Grading + Grad-CAM")
    print("  Listening on http://localhost:5000   ")
    print("  React app at  http://localhost:5173  ")
    print("=======================================")
    app.run(host='0.0.0.0', port=5000, debug=False)
