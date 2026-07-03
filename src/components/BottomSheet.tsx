/* ============================================================
   BottomSheet — panneau verre inférieur façon Apple Plans.
   3 positions : réduit / demi / plein. Glisser via la poignée.
   ============================================================ */
import { useCallback, useEffect, useRef, useState } from "react";

export type SheetPos = "peek" | "half" | "full";

const POS_VH: Record<SheetPos, number> = { peek: 0.16, half: 0.45, full: 0.88 };

interface Props {
  pos: SheetPos;
  onPos: (p: SheetPos) => void;
  children: React.ReactNode;
}

export default function BottomSheet({ pos, onPos, children }: Props) {
  const [dragY, setDragY] = useState<number | null>(null);
  const startRef = useRef<{ y: number; base: number } | null>(null);

  const heightFor = (p: SheetPos) => POS_VH[p] * window.innerHeight;

  const onPointerDown = useCallback(
    (e: React.PointerEvent) => {
      (e.target as HTMLElement).setPointerCapture(e.pointerId);
      startRef.current = { y: e.clientY, base: heightFor(pos) };
    },
    [pos],
  );

  const onPointerMove = useCallback((e: React.PointerEvent) => {
    if (!startRef.current) return;
    const dy = startRef.current.y - e.clientY;
    const h = Math.min(
      window.innerHeight * 0.92,
      Math.max(70, startRef.current.base + dy),
    );
    setDragY(h);
  }, []);

  const onPointerUp = useCallback(() => {
    if (!startRef.current) return;
    const h = dragY ?? heightFor(pos);
    startRef.current = null;
    setDragY(null);
    // aimante à la position la plus proche
    let best: SheetPos = "peek";
    let bestD = Infinity;
    (Object.keys(POS_VH) as SheetPos[]).forEach((p) => {
      const d = Math.abs(heightFor(p) - h);
      if (d < bestD) {
        bestD = d;
        best = p;
      }
    });
    onPos(best);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [dragY, pos, onPos]);

  // recalcule à la rotation de l'écran
  const [, force] = useState(0);
  useEffect(() => {
    const f = () => force((n) => n + 1);
    window.addEventListener("resize", f);
    return () => window.removeEventListener("resize", f);
  }, []);

  const height = dragY ?? heightFor(pos);

  return (
    <div
      className="sheet glass"
      style={{ height, transition: dragY ? "none" : "height 0.32s cubic-bezier(0.32,0.72,0,1)" }}
    >
      <div
        className="sheet__grab"
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={onPointerUp}
        onPointerCancel={onPointerUp}
      >
        <div className="sheet__handle" />
      </div>
      <div className="sheet__content">{children}</div>
    </div>
  );
}
