"""
VITREOUS API bridge.

All analysis runs in MATLAB on the trained models (matlab/api/vitreous_worker.m).
This Flask app only:
  * starts one long-running MATLAB worker, so models load once, not per request
  * hands images to it through a job folder
  * reports job progress and results to the React dashboard

Endpoints
  GET  /api/health          worker state: starting | loading | ready | busy | offline
  POST /api/analyze         {image: <data URI or base64>}  ->  202 {job_id}
  GET  /api/jobs/<job_id>   {status: Queued | Running (+stage) | Complete | Rejected | Error, ...}
  GET  /api/jobs/<job_id>/report          the Phase 5 clinical PDF report (?download=1 to save)
  GET  /api/jobs/<job_id>/report/status   {ready, pending, note}; the PDF renders after the results

Environment
  MATLAB_BIN        path to the matlab executable (default: MATLAB R2026a on macOS)
  VITREOUS_JOB_DIR  job folder (default: <tmp>/vitreous_jobs)
  VITREOUS_PORT     port (default 5050; macOS AirPlay Receiver already owns 5000)
"""
import atexit
import base64
import io
import json
import os
import re
import signal
import subprocess
import tempfile
import threading
import time
import uuid

from flask import Flask, jsonify, request, send_file
from flask_cors import CORS
from PIL import Image

app = Flask(__name__)
CORS(app)

PROJECT_ROOT = os.path.dirname(os.path.abspath(__file__))
API_DIR = os.path.join(PROJECT_ROOT, 'matlab', 'api')
MATLAB_BIN = os.environ.get('MATLAB_BIN', '/Applications/MATLAB_R2026a.app/bin/matlab')
JOB_DIR = os.environ.get('VITREOUS_JOB_DIR', os.path.join(tempfile.gettempdir(), 'vitreous_jobs'))
INBOX = os.path.join(JOB_DIR, 'inbox')
OUTBOX = os.path.join(JOB_DIR, 'outbox')
HEARTBEAT = os.path.join(JOB_DIR, 'worker.json')
WORKER_LOG = os.path.join(JOB_DIR, 'worker.log')

PORT = int(os.environ.get('VITREOUS_PORT', '5050'))
JOB_ID = re.compile(r'^[a-f0-9]{32}$')

_worker = None
_worker_lock = threading.Lock()


def start_worker():
    """Launch the MATLAB worker if it is not already running."""
    global _worker
    with _worker_lock:
        if _worker is not None and _worker.poll() is None:
            return
        os.makedirs(INBOX, exist_ok=True)
        os.makedirs(OUTBOX, exist_ok=True)
        if os.path.exists(HEARTBEAT):
            os.remove(HEARTBEAT)
        cmd = f"addpath('{API_DIR}'); vitreous_worker('{JOB_DIR}')"
        log = open(WORKER_LOG, 'a')
        _worker = subprocess.Popen(
            [MATLAB_BIN, '-batch', cmd],
            cwd=PROJECT_ROOT, stdout=log, stderr=subprocess.STDOUT,
        )
        print(f'[API] MATLAB worker started (pid {_worker.pid}); log: {WORKER_LOG}')


def stop_worker(*_):
    """Stop the MATLAB worker with the bridge, so no orphan keeps polling the inbox."""
    if _worker is not None and _worker.poll() is None:
        _worker.terminate()
        try:
            _worker.wait(timeout=10)
        except subprocess.TimeoutExpired:
            _worker.kill()


def worker_state():
    if _worker is None or _worker.poll() is not None:
        return {'status': 'offline'}
    try:
        with open(HEARTBEAT) as f:
            return json.load(f)
    except (OSError, json.JSONDecodeError):
        return {'status': 'starting'}


@app.route('/api/health', methods=['GET'])
def health():
    state = worker_state()
    return jsonify({
        'status': 'ok' if state.get('status') in ('ready', 'busy') else state.get('status'),
        'worker': state,
        'engine': 'matlab',
        'model': os.path.basename(state.get('grading_model', '')) or None,
        'version': state.get('matlab'),
    })


@app.route('/api/analyze', methods=['POST'])
def analyze():
    data = request.get_json(silent=True) or {}
    payload = data.get('image')
    if not payload:
        return jsonify({'status': 'Error', 'message': 'No image payload provided.'}), 400

    state = worker_state()
    if state.get('status') == 'offline':
        start_worker()
        return jsonify({'status': 'Error', 'message': 'The MATLAB worker was offline and is restarting. Try again in about 30 seconds.'}), 503

    filename = os.path.basename(str(data.get('filename') or ''))[:120]

    try:
        raw_b64 = payload.split(',', 1)[-1]
        img = Image.open(io.BytesIO(base64.b64decode(raw_b64)))
        img = img.convert('RGB')
    except Exception:
        return jsonify({'status': 'Error', 'message': 'Could not read the uploaded image. Use a JPG, PNG or TIFF fundus photo.'}), 400

    job_id = uuid.uuid4().hex
    img.save(os.path.join(INBOX, f'{job_id}.png'))
    with open(os.path.join(INBOX, f'{job_id}.meta.json'), 'w') as f:
        json.dump({'filename': filename}, f)
    # The marker is written last so the worker never reads a half-written image
    open(os.path.join(INBOX, f'{job_id}.ready'), 'w').close()
    print(f'[API] queued job {job_id} ({img.width}x{img.height})')
    return jsonify({'job_id': job_id, 'status': 'Queued'}), 202


@app.route('/api/jobs/<job_id>', methods=['GET'])
def job(job_id):
    if not JOB_ID.match(job_id):
        return jsonify({'status': 'Error', 'message': 'Unknown job.'}), 404

    result_path = os.path.join(OUTBOX, f'{job_id}.json')
    if os.path.exists(result_path):
        with open(result_path) as f:
            result = json.load(f)
        return jsonify(result)

    progress_path = os.path.join(OUTBOX, f'{job_id}.progress.json')
    if os.path.exists(progress_path):
        try:
            with open(progress_path) as f:
                progress = json.load(f)
            return jsonify({'status': 'Running', **progress})
        except (OSError, json.JSONDecodeError):
            return jsonify({'status': 'Running'})

    if os.path.exists(os.path.join(INBOX, f'{job_id}.ready')) or os.path.exists(os.path.join(INBOX, f'{job_id}.png')):
        if worker_state().get('status') == 'offline':
            return jsonify({'status': 'Error', 'message': 'The MATLAB worker stopped. Check ' + WORKER_LOG}), 503
        return jsonify({'status': 'Queued', 'worker': worker_state().get('status')})

    return jsonify({'status': 'Error', 'message': 'Unknown job.'}), 404


@app.route('/api/jobs/<job_id>/report/status', methods=['GET'])
def job_report_status(job_id):
    if not JOB_ID.match(job_id):
        return jsonify({'ready': False, 'pending': False, 'note': 'Unknown job.'}), 404
    status_path = os.path.join(OUTBOX, f'{job_id}.report.json')
    if os.path.exists(status_path):
        with open(status_path) as f:
            st = json.load(f)
        return jsonify({'ready': bool(st.get('ready')), 'pending': False, 'note': st.get('note', '')})
    return jsonify({'ready': False, 'pending': True, 'note': ''})


@app.route('/api/jobs/<job_id>/report', methods=['GET'])
def job_report(job_id):
    if not JOB_ID.match(job_id):
        return jsonify({'status': 'Error', 'message': 'Unknown job.'}), 404
    path = os.path.join(OUTBOX, f'{job_id}.pdf')
    if not os.path.exists(path):
        return jsonify({'status': 'Error', 'message': 'No report for this job.'}), 404
    inline = request.args.get('download') != '1'
    return send_file(path, mimetype='application/pdf', as_attachment=not inline,
                     download_name=f'VITREOUS_report_{job_id[:8]}.pdf')


def cleanup_old_results(max_age_s=3600):
    """Drop results older than an hour so the job folder does not grow forever."""
    now = time.time()
    for name in os.listdir(OUTBOX):
        path = os.path.join(OUTBOX, name)
        if now - os.path.getmtime(path) > max_age_s:
            os.remove(path)


if __name__ == '__main__':
    atexit.register(stop_worker)
    signal.signal(signal.SIGTERM, lambda *a: (stop_worker(), os._exit(0)))
    start_worker()
    cleanup_old_results()
    print('=======================================')
    print('  VITREOUS API bridge')
    print('  Analysis engine: MATLAB (trained models)')
    print(f'  Listening on http://127.0.0.1:{PORT}')
    print('  The MATLAB worker takes ~30 s to load models')
    print('=======================================')
    app.run(host='127.0.0.1', port=PORT, debug=False)
