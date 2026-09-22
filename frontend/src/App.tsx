import { BrowserRouter, Routes, Route } from "react-router-dom";
import Layout from "./components/Layout";
import Dashboard from "./pages/Dashboard";
import Queries from "./pages/Queries";
import SqlExplorer from "./pages/SqlExplorer";
import DatabasePage from "./pages/DatabasePage";
import Search from "./pages/Search";
import TitleDetail from "./pages/TitleDetail";
import "./styles/global.css";

export default function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route element={<Layout />}>
          <Route path="/" element={<Dashboard />} />
          <Route path="/queries" element={<Queries />} />
          <Route path="/sql" element={<SqlExplorer />} />
          <Route path="/database" element={<DatabasePage />} />
          <Route path="/search" element={<Search />} />
          <Route path="/title/:id" element={<TitleDetail />} />
        </Route>
      </Routes>
    </BrowserRouter>
  );
}
