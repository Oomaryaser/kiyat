"use client";

import { FormEvent, useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import {
  flexRender,
  getCoreRowModel,
  useReactTable,
  type ColumnDef,
} from "@tanstack/react-table";
import { AlertCircle, RotateCcw, Search } from "lucide-react";
import {
  getRoutes,
  type ListRoutesParams,
  type PaginatedResponse,
  type RouteStatus,
  type RouteType,
  type TransitRoute,
} from "@/lib/api";
import { mockRoutes } from "@/lib/mock-sprint-two";

interface RoutesPanelProps {
  token?: string;
  isDemo: boolean;
}

const statusLabels: Record<RouteStatus, string> = {
  active: "نشط",
  inactive: "متوقف",
  unverified: "غير موثق",
};

const typeLabels: Record<RouteType, string> = {
  kia: "كية",
  coaster: "كوستر",
  bus: "باص",
  minibus: "ميني باص",
};

export function RoutesPanel({ token, isDemo }: RoutesPanelProps) {
  const [draftSearch, setDraftSearch] = useState("");
  const [filters, setFilters] = useState<ListRoutesParams>({
    page: 1,
    limit: 50,
  });

  const routesQuery = useQuery({
    queryKey: ["routes", token, filters],
    queryFn: () => getRoutes(token ?? "", filters),
    enabled: Boolean(token) && !isDemo,
  });

  const routesResponse = useMemo(() => {
    if (routesQuery.data) return routesQuery.data;
    return filterMockRoutes(mockRoutes, filters);
  }, [filters, routesQuery.data]);

  const columns = useMemo<ColumnDef<TransitRoute>[]>(
    () => [
      {
        accessorKey: "nameAr",
        header: "الخط",
        cell: ({ row }) => (
          <div className="route-name-cell">
            <strong>{row.original.nameAr}</strong>
            <span>{row.original.nameEn}</span>
          </div>
        ),
      },
      {
        accessorKey: "routeType",
        header: "النوع",
        cell: ({ row }) => typeLabels[row.original.routeType],
      },
      {
        accessorKey: "status",
        header: "الحالة",
        cell: ({ row }) => (
          <span className={`status-badge status-${row.original.status}`}>
            {statusLabels[row.original.status]}
          </span>
        ),
      },
      {
        id: "fare",
        header: "الأجرة",
        cell: ({ row }) =>
          `${row.original.fareMin.toLocaleString("ar-IQ")} - ${row.original.fareMax.toLocaleString("ar-IQ")} د.ع`,
      },
      {
        id: "hours",
        header: "الدوام",
        cell: ({ row }) =>
          `${formatTimeText(row.original.operatingHoursStart)} - ${formatTimeText(row.original.operatingHoursEnd)}`,
      },
      {
        accessorKey: "confidenceScore",
        header: "الثقة",
        cell: ({ row }) => (
          <div className="confidence-cell">
            <span>{row.original.confidenceScore}%</span>
            <div className="confidence-track">
              <span style={{ width: `${row.original.confidenceScore}%` }} />
            </div>
          </div>
        ),
      },
      {
        accessorKey: "updatedAt",
        header: "آخر تعديل",
        cell: ({ row }) => formatDate(row.original.updatedAt),
      },
    ],
    [],
  );

  const table = useReactTable({
    data: routesResponse.data,
    columns,
    getCoreRowModel: getCoreRowModel(),
  });

  function handleApplyFilters(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setFilters((current) => ({
      ...current,
      page: 1,
      search: draftSearch.trim() || undefined,
    }));
  }

  function handleResetFilters() {
    setDraftSearch("");
    setFilters({ page: 1, limit: 50 });
  }

  return (
    <section className="page-stack" aria-label="الخطوط">
      <div className="section-head">
        <div>
          <p className="eyebrow">Routes</p>
          <h2>الخطوط</h2>
        </div>
        <span className="status-chip">{routesQuery.data ? "مباشر" : "تجريبي"}</span>
      </div>

      {routesQuery.isError ? (
        <div className="inline-alert">
          <AlertCircle aria-hidden="true" size={18} />
          <span>تعذر جلب الخطوط من الخادم، تظهر بيانات تجريبية مؤقتاً.</span>
        </div>
      ) : null}

      <section className="panel routes-toolbar" aria-label="فلاتر الخطوط">
        <form className="routes-filter-form" onSubmit={handleApplyFilters}>
          <label className="field compact-field">
            <span>بحث</span>
            <span className="input-wrap">
              <Search aria-hidden="true" size={18} />
              <input
                value={draftSearch}
                onChange={(event) => setDraftSearch(event.target.value)}
                placeholder="اسم الخط"
              />
            </span>
          </label>

          <label className="field compact-field">
            <span>الحالة</span>
            <select
              value={filters.status ?? ""}
              onChange={(event) =>
                setFilters((current) => ({
                  ...current,
                  page: 1,
                  status: (event.target.value || undefined) as
                    | RouteStatus
                    | undefined,
                }))
              }
            >
              <option value="">الكل</option>
              <option value="active">نشط</option>
              <option value="inactive">متوقف</option>
              <option value="unverified">غير موثق</option>
            </select>
          </label>

          <label className="field compact-field">
            <span>النوع</span>
            <select
              value={filters.type ?? ""}
              onChange={(event) =>
                setFilters((current) => ({
                  ...current,
                  page: 1,
                  type: (event.target.value || undefined) as
                    | RouteType
                    | undefined,
                }))
              }
            >
              <option value="">الكل</option>
              <option value="kia">كية</option>
              <option value="coaster">كوستر</option>
              <option value="bus">باص</option>
              <option value="minibus">ميني باص</option>
            </select>
          </label>

          <div className="toolbar-actions">
            <button className="primary-button compact-button" type="submit">
              <Search aria-hidden="true" size={16} />
              <span>بحث</span>
            </button>
            <button
              className="ghost-button compact-button"
              type="button"
              onClick={handleResetFilters}
            >
              <RotateCcw aria-hidden="true" size={16} />
              <span>إعادة</span>
            </button>
          </div>
        </form>
      </section>

      <section className="panel routes-table-panel" aria-labelledby="routes-table-title">
        <div className="panel-head">
          <h3 id="routes-table-title">قائمة الخطوط</h3>
          <span>
            {routesResponse.total.toLocaleString("ar-IQ")} خط
          </span>
        </div>

        <div className="table-scroll">
          <table className="admin-table">
            <thead>
              {table.getHeaderGroups().map((headerGroup) => (
                <tr key={headerGroup.id}>
                  {headerGroup.headers.map((header) => (
                    <th key={header.id}>
                      {header.isPlaceholder
                        ? null
                        : flexRender(
                            header.column.columnDef.header,
                            header.getContext(),
                          )}
                    </th>
                  ))}
                </tr>
              ))}
            </thead>
            <tbody>
              {table.getRowModel().rows.map((row) => (
                <tr key={row.id}>
                  {row.getVisibleCells().map((cell) => (
                    <td key={cell.id}>
                      {flexRender(
                        cell.column.columnDef.cell,
                        cell.getContext(),
                      )}
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>
    </section>
  );
}

function filterMockRoutes(
  response: PaginatedResponse<TransitRoute>,
  filters: ListRoutesParams,
) {
  const search = filters.search?.trim().toLowerCase();
  const data = response.data.filter((route) => {
    const matchesSearch = search
      ? route.nameAr.toLowerCase().includes(search) ||
        route.nameEn.toLowerCase().includes(search)
      : true;
    const matchesStatus = filters.status ? route.status === filters.status : true;
    const matchesType = filters.type ? route.routeType === filters.type : true;
    return matchesSearch && matchesStatus && matchesType;
  });

  return {
    ...response,
    total: data.length,
    data,
  };
}

function formatDate(value: string) {
  return new Intl.DateTimeFormat("ar-IQ", {
    year: "numeric",
    month: "short",
    day: "numeric",
  }).format(new Date(value));
}

function formatTimeText(value: string) {
  return value.slice(0, 5);
}
