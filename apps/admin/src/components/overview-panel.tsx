"use client";

import type { UseQueryResult } from "@tanstack/react-query";
import {
  Activity,
  AlertCircle,
  Bus,
  Clock3,
  type LucideIcon,
  MapPinned,
  Star,
  Users,
} from "lucide-react";
import {
  Bar,
  BarChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import type { OverviewMetrics } from "@/lib/api";
import { mockOverview } from "@/lib/mock-overview";

interface OverviewPanelProps {
  query: UseQueryResult<OverviewMetrics, Error>;
}

export function OverviewPanel({ query }: OverviewPanelProps) {
  const metrics = query.data ?? mockOverview;
  const sourceLabel = query.data ? "مباشر" : "تجريبي";
  const avgWait = metrics.averageWaitMinutes
    ? `${metrics.averageWaitMinutes.toFixed(1)} د`
    : "غير متاح";
  const avgRating = metrics.averageRating
    ? metrics.averageRating.toFixed(1)
    : "غير متاح";

  return (
    <section className="overview-grid" aria-label="ملخص التشغيل">
      <div className="section-head">
        <div>
          <p className="eyebrow">Overview</p>
          <h2>ملخص اليوم</h2>
        </div>
        <span className="status-chip">{sourceLabel}</span>
      </div>

      {query.isError ? (
        <div className="inline-alert">
          <AlertCircle aria-hidden="true" size={18} />
          <span>تعذر جلب البيانات الحية، تظهر أرقام تجريبية مؤقتاً.</span>
        </div>
      ) : null}

      <div className="metric-grid">
        <MetricCard
          icon={Bus}
          label="الكيات النشطة"
          value={metrics.activeVehicles}
          tone="blue"
        />
        <MetricCard
          icon={Users}
          label="الركاب المنتظرين"
          value={metrics.activeWaits}
          tone="green"
        />
        <MetricCard
          icon={MapPinned}
          label="الخطوط"
          value={metrics.routeCount}
          tone="amber"
        />
        <MetricCard
          icon={Clock3}
          label="متوسط الانتظار"
          value={avgWait}
          tone="rose"
        />
        <MetricCard
          icon={Activity}
          label="عمليات الصعود"
          value={metrics.boardedCount}
          tone="slate"
        />
        <MetricCard
          icon={Star}
          label="متوسط التقييم"
          value={avgRating}
          tone="violet"
        />
      </div>

      <div className="overview-panels">
        <section className="panel chart-panel" aria-labelledby="busy-routes-title">
          <div className="panel-head">
            <h3 id="busy-routes-title">أكثر الخطوط ازدحاماً</h3>
            <span>{metrics.busiestRoutes.length} خطوط</span>
          </div>

          <div className="chart-wrap">
            <ResponsiveContainer width="100%" height={260}>
              <BarChart
                data={metrics.busiestRoutes}
                layout="vertical"
                margin={{ left: 8, right: 8, top: 8, bottom: 8 }}
              >
                <CartesianGrid strokeDasharray="3 3" horizontal={false} />
                <XAxis type="number" allowDecimals={false} />
                <YAxis
                  dataKey="routeNameAr"
                  type="category"
                  width={120}
                  tick={{ fontSize: 12 }}
                />
                <Tooltip
                  cursor={{ fill: "rgba(46, 204, 113, 0.1)" }}
                  contentStyle={{
                    borderRadius: 8,
                    border: "1px solid #d6dde4",
                    direction: "rtl",
                  }}
                />
                <Bar dataKey="waitCount" fill="#2ecc71" radius={[0, 5, 5, 0]} />
              </BarChart>
            </ResponsiveContainer>
          </div>
        </section>

        <section className="panel route-list-panel" aria-labelledby="route-list-title">
          <div className="panel-head">
            <h3 id="route-list-title">ترتيب الخطوط</h3>
            <span>آخر 24 ساعة</span>
          </div>

          <div className="route-rank-list">
            {metrics.busiestRoutes.map((route, index) => (
              <div className="route-rank-row" key={route.routeId}>
                <span className="rank-number">{index + 1}</span>
                <span className="rank-name">{route.routeNameAr}</span>
                <strong>{route.waitCount}</strong>
              </div>
            ))}
          </div>
        </section>
      </div>
    </section>
  );
}

function MetricCard({
  icon: Icon,
  label,
  value,
  tone,
}: {
  icon: LucideIcon;
  label: string;
  value: string | number;
  tone: "blue" | "green" | "amber" | "rose" | "slate" | "violet";
}) {
  return (
    <article className={`metric-card tone-${tone}`}>
      <div className="metric-icon">
        <Icon aria-hidden="true" size={20} />
      </div>
      <div>
        <span>{label}</span>
        <strong>{value}</strong>
      </div>
    </article>
  );
}
