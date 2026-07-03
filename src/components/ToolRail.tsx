/* ============================================================
   ToolRail — the "verbs" of the editor.
   Left rail on wide screens, top strip on mobile.
   ============================================================ */
import type { RouteProfile } from "../lib/routing";
import type { EditMode } from "../edit/useEditor";
import type { EditRoute } from "../edit/route";

interface Props {
  mode: EditMode;
  setMode: (m: EditMode) => void;
  profile: RouteProfile;
  setProfile: (p: RouteProfile) => void;
  online: boolean;
  isRouting: boolean;
  lastFellBack: boolean;
  route: EditRoute;
  canUndo: boolean;
  canRedo: boolean;
  onUndo: () => void;
  onRedo: () => void;
  onReverse: () => void;
  onClear: () => void;
}

export default function ToolRail(p: Props) {
  const drawing = p.mode === "draw" || p.mode === "waypoint";
  const hasRoute = p.route.anchors.length > 0;

  return (
    <div className="rail">
      <div className="rail__group">
        <Tool
          active={p.mode === "view"}
          label="Select"
          hint="View & scrub (V)"
          onClick={() => p.setMode("view")}
          icon={<IconCursor />}
        />
        <Tool
          active={p.mode === "draw"}
          label="Draw"
          hint="Click to add points (D)"
          onClick={() => p.setMode("draw")}
          icon={<IconPen />}
        />
        <Tool
          active={p.mode === "waypoint"}
          label="Waypoint"
          hint="Click to drop a named marker (W)"
          onClick={() => p.setMode("waypoint")}
          icon={<IconPin />}
        />
      </div>

      {drawing && (
        <div className="rail__group">
          <div className="rail__label">Snap to</div>
          <Seg
            options={[
              { id: "hike", label: "Hike" },
              { id: "bike", label: "Bike" },
              { id: "straight", label: "Line" },
            ]}
            value={p.profile}
            onChange={(v) => p.setProfile(v as RouteProfile)}
          />
          {p.profile !== "straight" && !p.online && (
            <div className="badge badge--warn">
              Offline — drawing straight lines. Snapping resumes when back online.
            </div>
          )}
          {p.profile !== "straight" && p.online && p.lastFellBack && (
            <div className="badge badge--warn">
              Couldn't reach the routing service — used a straight line.
            </div>
          )}
          {p.isRouting && <div className="badge">Snapping…</div>}
        </div>
      )}

      <div className="rail__group rail__group--actions">
        <IconBtn label="Undo" hint="Undo (Ctrl+Z)" disabled={!p.canUndo} onClick={p.onUndo}>
          <IconUndo />
        </IconBtn>
        <IconBtn label="Redo" hint="Redo (Ctrl+Y)" disabled={!p.canRedo} onClick={p.onRedo}>
          <IconRedo />
        </IconBtn>
        <IconBtn label="Reverse" hint="Reverse direction" disabled={!hasRoute} onClick={p.onReverse}>
          <IconReverse />
        </IconBtn>
        <IconBtn label="Clear" hint="Delete the route" disabled={!hasRoute} onClick={p.onClear} danger>
          <IconTrash />
        </IconBtn>
      </div>
    </div>
  );
}

function Tool({
  active,
  label,
  hint,
  onClick,
  icon,
}: {
  active: boolean;
  label: string;
  hint: string;
  onClick: () => void;
  icon: React.ReactNode;
}) {
  return (
    <button
      className={`tool${active ? " tool--active" : ""}`}
      onClick={onClick}
      title={hint}
      aria-pressed={active}
    >
      <span className="tool__icon">{icon}</span>
      <span className="tool__label">{label}</span>
    </button>
  );
}

function IconBtn({
  label,
  hint,
  disabled,
  onClick,
  danger,
  children,
}: {
  label: string;
  hint: string;
  disabled?: boolean;
  onClick: () => void;
  danger?: boolean;
  children: React.ReactNode;
}) {
  return (
    <button
      className={`iconbtn${danger ? " iconbtn--danger" : ""}`}
      onClick={onClick}
      disabled={disabled}
      title={hint}
      aria-label={label}
    >
      {children}
    </button>
  );
}

function Seg({
  options,
  value,
  onChange,
}: {
  options: { id: string; label: string }[];
  value: string;
  onChange: (v: string) => void;
}) {
  return (
    <div className="seg" role="tablist">
      {options.map((o) => (
        <button
          key={o.id}
          role="tab"
          aria-selected={value === o.id}
          className={`seg__opt${value === o.id ? " seg__opt--on" : ""}`}
          onClick={() => onChange(o.id)}
        >
          {o.label}
        </button>
      ))}
    </div>
  );
}

/* --- tiny inline icons (stroke = currentColor) --- */
const S = {
  fill: "none",
  stroke: "currentColor",
  strokeWidth: 1.7,
  strokeLinecap: "round" as const,
  strokeLinejoin: "round" as const,
};
function IconCursor() {
  return (
    <svg viewBox="0 0 24 24" width="18" height="18" {...S}>
      <path d="M6 4l12 6-5 2-2 5z" />
    </svg>
  );
}
function IconPen() {
  return (
    <svg viewBox="0 0 24 24" width="18" height="18" {...S}>
      <path d="M4 20l4-1 10-10-3-3L5 16z" />
      <path d="M13.5 6.5l3 3" />
    </svg>
  );
}
function IconPin() {
  return (
    <svg viewBox="0 0 24 24" width="18" height="18" {...S}>
      <path d="M12 21s6-5.3 6-10a6 6 0 10-12 0c0 4.7 6 10 6 10z" />
      <circle cx="12" cy="11" r="2.2" />
    </svg>
  );
}
function IconUndo() {
  return (
    <svg viewBox="0 0 24 24" width="18" height="18" {...S}>
      <path d="M9 7L4 12l5 5" />
      <path d="M4 12h11a5 5 0 010 10h-1" />
    </svg>
  );
}
function IconRedo() {
  return (
    <svg viewBox="0 0 24 24" width="18" height="18" {...S}>
      <path d="M15 7l5 5-5 5" />
      <path d="M20 12H9a5 5 0 000 10h1" />
    </svg>
  );
}
function IconReverse() {
  return (
    <svg viewBox="0 0 24 24" width="18" height="18" {...S}>
      <path d="M4 8h13l-3-3M20 16H7l3 3" />
    </svg>
  );
}
function IconTrash() {
  return (
    <svg viewBox="0 0 24 24" width="18" height="18" {...S}>
      <path d="M5 7h14M10 7V5h4v2M6 7l1 13h10l1-13" />
    </svg>
  );
}
