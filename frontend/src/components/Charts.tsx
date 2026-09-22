import {
  BarChart,
  Bar,
  XAxis,
  YAxis,
  Tooltip,
  ResponsiveContainer,
  PieChart,
  Pie,
  Cell,
  LineChart,
  Line,
  CartesianGrid,
} from "recharts";

const ACCENT = "#e0263f";
const DIM = "#9b9ba3";
const PIE_COLORS = ["#e0263f", "#3d3d45"];

export function HorizontalBarChart({
  data,
  dataKey,
  labelKey,
}: {
  data: Record<string, any>[];
  dataKey: string;
  labelKey: string;
}) {
  return (
    <ResponsiveContainer width="100%" height={280}>
      <BarChart data={data} layout="vertical" margin={{ left: 20, right: 20 }}>
        <XAxis type="number" stroke={DIM} fontSize={11} />
        <YAxis type="category" dataKey={labelKey} stroke={DIM} fontSize={11.5} width={110} />
        <Tooltip contentStyle={{ background: "#16161a", border: "1px solid #2a2a30", fontSize: 12 }} />
        <Bar dataKey={dataKey} fill={ACCENT} radius={[0, 4, 4, 0]} />
      </BarChart>
    </ResponsiveContainer>
  );
}

export function VerticalBarChart({
  data,
  dataKey,
  labelKey,
}: {
  data: Record<string, any>[];
  dataKey: string;
  labelKey: string;
}) {
  return (
    <ResponsiveContainer width="100%" height={260}>
      <BarChart data={data}>
        <XAxis dataKey={labelKey} stroke={DIM} fontSize={11} />
        <YAxis stroke={DIM} fontSize={11} />
        <Tooltip contentStyle={{ background: "#16161a", border: "1px solid #2a2a30", fontSize: 12 }} />
        <Bar dataKey={dataKey} fill={ACCENT} radius={[4, 4, 0, 0]} />
      </BarChart>
    </ResponsiveContainer>
  );
}

export function TrendLineChart({
  data,
  dataKey,
  labelKey,
}: {
  data: Record<string, any>[];
  dataKey: string;
  labelKey: string;
}) {
  return (
    <ResponsiveContainer width="100%" height={260}>
      <LineChart data={data}>
        <CartesianGrid stroke="#2a2a30" strokeDasharray="3 3" />
        <XAxis dataKey={labelKey} stroke={DIM} fontSize={11} />
        <YAxis stroke={DIM} fontSize={11} />
        <Tooltip contentStyle={{ background: "#16161a", border: "1px solid #2a2a30", fontSize: 12 }} />
        <Line type="monotone" dataKey={dataKey} stroke={ACCENT} strokeWidth={2} dot={false} />
      </LineChart>
    </ResponsiveContainer>
  );
}

export function SplitDonut({ movies, tvShows }: { movies: number; tvShows: number }) {
  const data = [
    { name: "Movies", value: movies },
    { name: "TV Shows", value: tvShows },
  ];
  return (
    <ResponsiveContainer width="100%" height={220}>
      <PieChart>
        <Pie data={data} dataKey="value" nameKey="name" innerRadius={55} outerRadius={85} paddingAngle={2}>
          {data.map((_, i) => (
            <Cell key={i} fill={PIE_COLORS[i % PIE_COLORS.length]} />
          ))}
        </Pie>
        <Tooltip contentStyle={{ background: "#16161a", border: "1px solid #2a2a30", fontSize: 12 }} />
      </PieChart>
    </ResponsiveContainer>
  );
}
