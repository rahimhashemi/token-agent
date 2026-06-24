// useTokenAgent.ts
// React hook — communicates with the local ePass agent over HTTPS localhost

import { useState, useEffect, useCallback } from 'react';

const AGENT_BASE = 'https://localhost:7070/api/token';

export type TokenStatus = 'checking' | 'not_detected' | 'detected' | 'agent_offline';

export interface Certificate {
  alias: string;
  subject: string;
  issuer: string;
  serialNumber: string;
  notBefore: string;
  notAfter: string;
}

export interface PinResult {
  success: boolean;
  certCount?: number;
  error?: string;
}

export function useTokenAgent() {
  const [status, setStatus]           = useState<TokenStatus>('checking');
  const [certificates, setCertificates] = useState<Certificate[]>([]);
  const [polling, setPolling]         = useState(true);

  // ── Token detection — polls every 2 seconds ──────────────────────────
  useEffect(() => {
    if (!polling) return;

    const check = async () => {
      try {
        const res = await fetch(`${AGENT_BASE}/detect`, {
          method: 'GET',
          // Note: browser will trust our CA since it's in the OS store
        });

        if (!res.ok) {
          setStatus('agent_offline');
          return;
        }

        const data = await res.json();
        setStatus(data.present ? 'detected' : 'not_detected');

      } catch {
        // fetch throws if agent is not running or cert is not trusted
        setStatus('agent_offline');
      }
    };

    check(); // immediate first check
    const interval = setInterval(check, 2000);
    return () => clearInterval(interval);
  }, [polling]);

  // ── Read certificates from token (no PIN) ────────────────────────────
  const loadCertificates = useCallback(async (): Promise<Certificate[]> => {
    const res = await fetch(`${AGENT_BASE}/certificates`);
    if (!res.ok) throw new Error('Failed to load certificates');
    const data = await res.json();
    setCertificates(data.certificates ?? []);
    return data.certificates ?? [];
  }, []);

  // ── Verify PIN ────────────────────────────────────────────────────────
  const verifyPin = useCallback(async (pin: string): Promise<PinResult> => {
    try {
      const res = await fetch(`${AGENT_BASE}/verify-pin`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ pin }),
      });

      const data = await res.json();

      if (res.ok) {
        return { success: true, certCount: data.certCount };
      } else {
        return { success: false, error: data.error ?? 'PIN verification failed' };
      }

    } catch {
      return { success: false, error: 'Could not reach token agent' };
    }
  }, []);

  // ── Stop polling (e.g. after signing is done) ─────────────────────────
  const stopPolling = useCallback(() => setPolling(false), []);
  const startPolling = useCallback(() => setPolling(true), []);

  return {
    status,
    certificates,
    loadCertificates,
    verifyPin,
    stopPolling,
    startPolling,
  };
}
