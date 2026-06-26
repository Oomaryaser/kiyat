"use client";

import { useEffect, useMemo, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { AlertTriangle } from "lucide-react";
import { AdminShell, type AdminView } from "@/components/admin-shell";
import { LiveMapPanel } from "@/components/live-map-panel";
import { LoginCard } from "@/components/login-card";
import { OverviewPanel } from "@/components/overview-panel";
import { RoutesPanel } from "@/components/routes-panel";
import {
  getOperatorProfile,
  getOverview,
  type AuthTokens,
  type OperatorProfile,
} from "@/lib/api";
import {
  clearDemoSession,
  clearStoredTokens,
  readDemoSession,
  readStoredTokens,
  storeDemoSession,
  storeTokens,
} from "@/lib/auth-storage";

const allowedAdminRoles = new Set(["owner", "admin"]);
const demoProfile: OperatorProfile = {
  id: "demo-owner",
  phone: "07701234567",
  role: "owner",
  nameAr: "مالك كيات التجريبي",
};

export function AdminDashboard() {
  const queryClient = useQueryClient();
  const [tokens, setTokens] = useState<AuthTokens | null>(null);
  const [isDemoSession, setIsDemoSession] = useState(false);
  const [activeView, setActiveView] = useState<AdminView>("overview");
  const [storageReady, setStorageReady] = useState(false);

  useEffect(() => {
    const hasDemoSession = readDemoSession();
    setIsDemoSession(hasDemoSession);
    setTokens(hasDemoSession ? null : readStoredTokens());
    setStorageReady(true);
  }, []);

  const accessToken = tokens?.accessToken;

  const profileQuery = useQuery({
    queryKey: ["operator-profile", accessToken],
    queryFn: () => getOperatorProfile(accessToken ?? ""),
    enabled: Boolean(accessToken) && !isDemoSession,
  });

  const overviewQuery = useQuery({
    queryKey: ["overview", accessToken],
    queryFn: () => getOverview(accessToken ?? ""),
    enabled: Boolean(accessToken) && !isDemoSession,
    refetchInterval: 30_000,
  });

  const profile = isDemoSession ? demoProfile : profileQuery.data;
  const isAllowed = useMemo(
    () => Boolean(profile && allowedAdminRoles.has(profile.role)),
    [profile],
  );

  function handleAuthenticated(nextTokens: AuthTokens) {
    clearDemoSession();
    storeTokens(nextTokens);
    setTokens(nextTokens);
    setIsDemoSession(false);
  }

  function handleDemoLogin() {
    queryClient.clear();
    storeDemoSession();
    setTokens(null);
    setIsDemoSession(true);
  }

  function handleLogout() {
    clearStoredTokens();
    clearDemoSession();
    setTokens(null);
    setIsDemoSession(false);
    setActiveView("overview");
    queryClient.clear();
  }

  if (!storageReady) {
    return <div className="boot-screen" />;
  }

  if (!tokens && !isDemoSession) {
    return (
      <LoginCard
        onAuthenticated={handleAuthenticated}
        onDemoLogin={handleDemoLogin}
      />
    );
  }

  if (!isDemoSession && profileQuery.isLoading) {
    return (
      <div className="boot-screen">
        <div className="pulse-dot" />
      </div>
    );
  }

  if (!isDemoSession && (profileQuery.isError || !profile)) {
    return (
      <SessionMessage
        title="انتهت الجلسة"
        message="سجل دخولك من جديد."
        onLogout={handleLogout}
      />
    );
  }

  if (!profile) {
    return (
      <SessionMessage
        title="تعذر فتح الداشبورد"
        message="سجل دخولك من جديد."
        onLogout={handleLogout}
      />
    );
  }

  if (!isAllowed) {
    return (
      <SessionMessage
        title="صلاحية غير كافية"
        message="هذا الحساب غير مخصص للوحة السوبر أونر."
        profile={profile}
        onLogout={handleLogout}
      />
    );
  }

  return (
    <AdminShell
      profile={profile}
      activeView={activeView}
      onViewChange={setActiveView}
      onLogout={handleLogout}
    >
      {activeView === "overview" ? <OverviewPanel query={overviewQuery} /> : null}
      {activeView === "map" ? (
        <LiveMapPanel token={accessToken} isDemo={isDemoSession} />
      ) : null}
      {activeView === "routes" ? (
        <RoutesPanel token={accessToken} isDemo={isDemoSession} />
      ) : null}
    </AdminShell>
  );
}

function SessionMessage({
  title,
  message,
  profile,
  onLogout,
}: {
  title: string;
  message: string;
  profile?: OperatorProfile;
  onLogout: () => void;
}) {
  return (
    <main className="login-page">
      <section className="session-panel">
        <AlertTriangle aria-hidden="true" size={28} />
        <h1>{title}</h1>
        <p>{message}</p>
        {profile ? (
          <p className="muted">
            {profile.nameAr ?? profile.phone} - {profile.role}
          </p>
        ) : null}
        <button className="primary-button" type="button" onClick={onLogout}>
          تسجيل خروج
        </button>
      </section>
    </main>
  );
}
