/* ============================================================
   ElevationProfile — SVG area chart of elevation vs distance.
   - Fills left-to-right on load (pen-stroke feel).
   - Scrub with mouse/touch -> reports the nearest point index.
   - Highlights the externally-hovered index (map -> chart link).
   No chart library: pure SVG so it stays tiny and works offline.
   ============================================================ */
import { useMemo, useRef } from "react";
import type { Track } from "../lib/gpx";
import { fmtDistance, fmtElevation } from "../lib/format";

const VW = 1000; // viewBox width (scales to container)
const VH = 168; // viewBox height
const PAD_T = 14;
const PAD_B = 22;
const PAD_L = 4;
const PAD_R = 4;

interface Props {
  track: Track;
  hoverIdx: number | null;
  onHover: (idx: number | null) => void;
}

interface Sample {
  x: number; // svg x
  y: number; // svg y
  idx: number; // index into track.points
  dist: number;
  ele: number;
}

export default function ElevationProfile({ track, hoverIdx, onHover }: Props) {
  const svgRef = useRef<SVGSVGElement>(null);

  const model = useMemo(() => buildModel(track), [track]);

  if (!model) {
    return (
      <div className="elev elev--empty">
        <span className="elev__note">No elevation data in this file.</span>
      </div>
    );
  }

  const { samples, areaPath, linePath, minEle, maxEle, totalDist } = model;

  function idxFromClientX(clientX: number): number | null {
    const svg = svgRef.current;
    if (!svg) return null;
    const rect = svg.getBoundingClientRect();
    const ratio = (clientX - rect.left) / rect.width;
    const x = PAD_L + ratio * (VW - PAD_L - PAD_R);
    // binary-ish nearest by x over samples
    let best = samples[0];
    let bestD = Infinity;
    for (const s of samples) {
      const d = Math.abs(s.x - x);
      if (d < bestD) {
        bestD = d;
        best = s;
      }
    }
    return best.idx;
  }

  const onMove = (e: React.PointerEvent) => {
    const idx = idxFromClientX(e.clientX);
    if (idx != null) onHover(idx);
  };

  const hoverSample =
    hoverIdx != null ? sampleForIdx(samples, hoverIdx) : null;

  return (
    <div className="elev">
      <svg
        ref={svgRef}
        className="elev__svg"
        viewBox={`0 0 ${VW} ${VH}`}
        preserveAspectRatio="none"
        onPointerDown={onMove}
        onPointerMove={onMove}
        onPointerLeave={() => onHover(null)}
      >
        <defs>
          <linearGradient id="elevFill" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor="var(--track)" stopOpacity="0.28" />
            <stop offset="100%" stopColor="var(--track)" stopOpacity="0.02" />
          </linearGradient>
          <clipPath id="elevReveal">
            {/* animated width: fills left-to-right */}
            <rect className="elev__reveal" x="0" y="0" width={VW} height={VH} />
          </clipPath>
        </defs>

        {/* subtle baseline */}
        <line
          x1={PAD_L}
          y1={VH - PAD_B}
          x2={VW - PAD_R}
          y2={VH - PAD_B}
          stroke="var(--line)"
          strokeWidth="1"
        />

        <g clipPath="url(#elevReveal)">
          <path d={areaPath} fill="url(#elevFill)" />
          <path
            d={linePath}
            fill="none"
            stroke="var(--track)"
            strokeWidth="2"
            strokeLinejoin="round"
            strokeLinecap="round"
            vectorEffect="non-scaling-stroke"
          />
        </g>

        {/* hover indicator */}
        {hoverSample && (
          <g>
            <line
              x1={hoverSample.x}
              y1={PAD_T - 6}
              x2={hoverSample.x}
              y2={VH - PAD_B}
              stroke="var(--accent)"
              strokeWidth="1"
              strokeDasharray="3 3"
              vectorEffect="non-scaling-stroke"
            />
            <circle
              cx={hoverSample.x}
              cy={hoverSample.y}
              r="4.5"
              fill="var(--accent)"
              stroke="var(--paper-raised)"
              strokeWidth="2"
              vectorEffect="non-scaling-stroke"
            />
          </g>
        )}
      </svg>

      {/* readout */}
      <div className="elev__readout num">
        {hoverSample ? (
          <>
            <span className="elev__reBig">{fmtElevation(hoverSample.ele)}</span>
            <span className="elev__reDim">at {fmtDistance(hoverSample.dist)}</span>
          </>
        ) : (
          <>
            <span className="elev__reDim">min {fmtElevation(minEle)}</span>
            <span className="elev__reDim">max {fmtElevation(maxEle)}</span>
            <span className="elev__reDim">{fmtDistance(totalDist)}</span>
          </>
        )}
      </div>
    </div>
  );
}

/* --- model building --- */

interface Model {
  samples: Sample[];
  areaPath: string;
  linePath: string;
  minEle: number;
  maxEle: number;
  totalDist: number;
}

function buildModel(track: Track): Model | null {
  const pts = track.points;
  const withEle = pts.filter((p) => p.ele != null);
  if (withEle.length < 2) return null;

  const totalDist = pts[pts.length - 1].dist || 1;
  let minEle = Infinity;
  let maxEle = -Infinity;
  for (const p of pts) {
    if (p.ele == null) continue;
    if (p.ele < minEle) minEle = p.ele;
    if (p.ele > maxEle) maxEle = p.ele;
  }
  const eleRange = Math.max(1, maxEle - minEle);

  // Downsample to at most ~600 columns for a crisp, cheap path.
  const maxCols = 600;
  const step = Math.max(1, Math.floor(pts.length / maxCols));

  const innerW = VW - PAD_L - PAD_R;
  const innerH = VH - PAD_T - PAD_B;

  const samples: Sample[] = [];
  let lastEle = withEle[0].ele as number;
  for (let i = 0; i < pts.length; i += step) {
    const p = pts[i];
    const ele = p.ele != null ? p.ele : lastEle;
    lastEle = ele;
    const x = PAD_L + (p.dist / totalDist) * innerW;
    const y = PAD_T + (1 - (ele - minEle) / eleRange) * innerH;
    samples.push({ x, y, idx: i, dist: p.dist, ele });
  }
  // ensure last point included
  const last = pts[pts.length - 1];
  const lastY =
    PAD_T + (1 - ((last.ele ?? lastEle) - minEle) / eleRange) * innerH;
  samples.push({
    x: PAD_L + innerW,
    y: lastY,
    idx: pts.length - 1,
    dist: last.dist,
    ele: last.ele ?? lastEle,
  });

  const linePath = samples
    .map((s, i) => `${i === 0 ? "M" : "L"}${s.x.toFixed(1)},${s.y.toFixed(1)}`)
    .join(" ");
  const areaPath =
    `M${samples[0].x.toFixed(1)},${(VH - PAD_B).toFixed(1)} ` +
    samples.map((s) => `L${s.x.toFixed(1)},${s.y.toFixed(1)}`).join(" ") +
    ` L${samples[samples.length - 1].x.toFixed(1)},${(VH - PAD_B).toFixed(1)} Z`;

  return { samples, areaPath, linePath, minEle, maxEle, totalDist };
}

function sampleForIdx(samples: Sample[], idx: number): Sample {
  // nearest sample by original index
  let best = samples[0];
  let bestD = Infinity;
  for (const s of samples) {
    const d = Math.abs(s.idx - idx);
    if (d < bestD) {
      bestD = d;
      best = s;
    }
  }
  return best;
}
