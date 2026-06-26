import type { NextConfig } from "next";
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

function readEnvValue(filePath: string, key: string) {
  if (!existsSync(filePath)) return undefined;

  const lines = readFileSync(filePath, "utf8").split(/\r?\n/);
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;

    const match = trimmed.match(/^([A-Z0-9_]+)\s*=\s*(.*)$/);
    if (match?.[1] !== key) continue;

    return match[2].replace(/^["']|["']$/g, "").trim();
  }

  return undefined;
}

function readGoogleMapsKey() {
  if (process.env.NEXT_PUBLIC_GOOGLE_MAPS_API_KEY) {
    return process.env.NEXT_PUBLIC_GOOGLE_MAPS_API_KEY;
  }
  if (process.env.GOOGLE_MAPS_API_KEY) {
    return process.env.GOOGLE_MAPS_API_KEY;
  }

  const candidates = [
    resolve(process.cwd(), "../../.env"),
    resolve(process.cwd(), ".env.local"),
    resolve(process.cwd(), ".env"),
    resolve(process.cwd(), "ios/Flutter/Secrets.xcconfig"),
    resolve(process.cwd(), "../driver/ios/Flutter/Secrets.xcconfig"),
    resolve(process.cwd(), "../mobile/ios/Flutter/Secrets.xcconfig"),
  ];

  for (const filePath of candidates) {
    const key =
      readEnvValue(filePath, "NEXT_PUBLIC_GOOGLE_MAPS_API_KEY") ??
      readEnvValue(filePath, "GOOGLE_MAPS_API_KEY");
    if (key) return key;
  }

  return "";
}

const nextConfig: NextConfig = {
  reactStrictMode: true,
  env: {
    NEXT_PUBLIC_GOOGLE_MAPS_API_KEY: readGoogleMapsKey(),
  },
};

export default nextConfig;
