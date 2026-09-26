import { useCallback, useEffect, useState } from 'react';

// 127.0.0.1 rather than localhost: on macOS, localhost:5000-style ports can be
// answered by the AirPlay Receiver over IPv6 instead of our bridge.
export const API = 'http://127.0.0.1:5050';

/**
 * Polls the bridge's /api/health. The analysis itself runs in a MATLAB worker,
 * which takes ~30 s to load its models, so "loading" is a normal state.
 *
 * Returns [{ status, info }, recheck] where status is one of
 * checking | loading | online | busy | offline | bridge.
 */
export function useBackendHealth(pollMs = 5000) {
  const [state, setState] = useState({ status: 'checking', info: null });

  const check = useCallback(async () => {
    if (window.htmlComponent) {
      setState({ status: 'bridge', info: null });
      return;
    }
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), 2500);
    try {
      const res = await fetch(`${API}/api/health`, { signal: ctrl.signal });
      const info = await res.json();
      const worker = info.worker?.status;
      const status =
        worker === 'ready' ? 'online'
          : worker === 'busy' ? 'busy'
            : worker === 'loading' || worker === 'starting' ? 'loading'
              : 'offline';
      setState({ status, info });
    } catch {
      setState({ status: 'offline', info: null });
    } finally {
      clearTimeout(timer);
    }
  }, []);

  useEffect(() => {
    check();
    const id = setInterval(check, pollMs);
    return () => clearInterval(id);
  }, [check, pollMs]);

  return [state, check];
}
