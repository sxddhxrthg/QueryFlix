import { NavLink, Outlet } from "react-router-dom";

const navItems = [
  { to: "/", label: "Dashboard", end: true },
  { to: "/queries", label: "36 Business Questions" },
  { to: "/mapping", label: "Title Mapping" },
  { to: "/personalization", label: "Personalization" },
  { to: "/sql", label: "Query Execution" },
  { to: "/database", label: "Database" },
  { to: "/search", label: "Search Titles" },
];

export default function Layout() {
  return (
    <div className="app-shell">
      <aside className="sidebar">
        <div className="brand">
          Query<span>Flix</span>
        </div>
        <div className="brand-sub">Netflix catalog + MovieLens behaviour, unified in MySQL</div>
        <nav>
          {navItems.map((item) => (
            <NavLink
              key={item.to}
              to={item.to}
              end={item.end}
              className={({ isActive }) => `nav-link${isActive ? " active" : ""}`}
            >
              {item.label}
            </NavLink>
          ))}
        </nav>
      </aside>
      <main className="main-content">
        <Outlet />
      </main>
    </div>
  );
}
