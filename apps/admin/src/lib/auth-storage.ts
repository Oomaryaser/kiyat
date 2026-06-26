import type { AuthTokens } from "./api";

const AUTH_STORAGE_KEY = "kiyat.admin.auth";
const DEMO_STORAGE_KEY = "kiyat.admin.demo";

export function readStoredTokens(): AuthTokens | null {
  if (typeof window === "undefined") return null;
  const rawValue = window.localStorage.getItem(AUTH_STORAGE_KEY);
  if (!rawValue) return null;

  try {
    const parsed = JSON.parse(rawValue) as Partial<AuthTokens>;
    if (!parsed.accessToken || !parsed.refreshToken) return null;
    return {
      accessToken: parsed.accessToken,
      refreshToken: parsed.refreshToken,
    };
  } catch {
    return null;
  }
}

export function storeTokens(tokens: AuthTokens) {
  window.localStorage.setItem(AUTH_STORAGE_KEY, JSON.stringify(tokens));
  window.localStorage.removeItem(DEMO_STORAGE_KEY);
}

export function clearStoredTokens() {
  window.localStorage.removeItem(AUTH_STORAGE_KEY);
}

export function readDemoSession() {
  if (typeof window === "undefined") return false;
  return window.localStorage.getItem(DEMO_STORAGE_KEY) === "true";
}

export function storeDemoSession() {
  window.localStorage.removeItem(AUTH_STORAGE_KEY);
  window.localStorage.setItem(DEMO_STORAGE_KEY, "true");
}

export function clearDemoSession() {
  window.localStorage.removeItem(DEMO_STORAGE_KEY);
}
