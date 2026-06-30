"use client";

import {
  BarChart3,
  FileText,
  LayoutDashboard,
  LogOut,
  Map,
  Route,
  Shield,
  Users,
} from "lucide-react";
import clsx from "clsx";
import type { OperatorProfile } from "@/lib/api";

export type AdminView =
  | "overview"
  | "map"
  | "routes"
  | "reports"
  | "drivers"
  | "roles"
  | "analytics";

interface AdminShellProps {
  profile: OperatorProfile;
  children: React.ReactNode;
  activeView: AdminView;
  onViewChange: (view: AdminView) => void;
  onLogout: () => void;
}

const navItems = [
  { id: "overview", label: "الرئيسية", icon: LayoutDashboard, enabled: true },
  { id: "map", label: "الخريطة", icon: Map, enabled: true },
  { id: "routes", label: "الخطوط", icon: Route, enabled: true },
  { id: "reports", label: "البلاغات", icon: FileText, enabled: false },
  { id: "drivers", label: "السواق", icon: Users, enabled: false },
  { id: "roles", label: "الصلاحيات", icon: Shield, enabled: false },
  { id: "analytics", label: "التحليلات", icon: BarChart3, enabled: false },
] as const;

export function AdminShell({
  profile,
  children,
  activeView,
  onViewChange,
  onLogout,
}: AdminShellProps) {
  const activeItem =
    navItems.find((item) => item.id === activeView) ?? navItems[0];

  return (
    <div className="admin-frame">
      <aside className="sidebar">
        <div className="sidebar-brand">
          <img className="brand-mark" src="/kiyat-mark.svg" alt="" />
          <div>
            <p className="eyebrow">KIYAT</p>
            <strong>إدارة التشغيل</strong>
          </div>
        </div>

        <nav className="nav-list" aria-label="لوحة التحكم">
          {navItems.map((item) => {
            const Icon = item.icon;
            return (
              <button
                key={item.label}
                className={clsx("nav-item", item.id === activeView && "active")}
                disabled={!item.enabled}
                onClick={() => onViewChange(item.id)}
                type="button"
                title={item.label}
              >
                <Icon aria-hidden="true" size={18} />
                <span>{item.label}</span>
              </button>
            );
          })}
        </nav>
      </aside>

      <div className="admin-main">
        <header className="topbar">
          <div>
            <p className="eyebrow">Super Owner</p>
            <h1>{activeItem.label}</h1>
          </div>

          <div className="topbar-actions">
            <div className="profile-pill">
              <span>{profile.nameAr ?? profile.phone}</span>
              <small>{profile.role}</small>
            </div>
            <button
              className="icon-button"
              type="button"
              title="تسجيل خروج"
              onClick={onLogout}
            >
              <LogOut aria-hidden="true" size={18} />
            </button>
          </div>
        </header>

        <div className="content-area">{children}</div>
      </div>
    </div>
  );
}
