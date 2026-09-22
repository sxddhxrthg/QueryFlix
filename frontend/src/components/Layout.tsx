import { NavLink, Outlet } from "react-router-dom";

const navItems = [
  { to: "/", label: "Dashboard", end: true },
  { to: "/queries", label: "15 Business Questions" },
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
        <div className="brand-sub">Netflix Content Analytics using Advanced SQL</div>
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
