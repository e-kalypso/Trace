/* ============================================================
   Local library storage — IndexedDB.
   Everything lives on-device so the library works fully offline.
   We store the portable GPX text plus lightweight metadata and a
   pre-rendered SVG thumbnail for a fast, network-free list.
   ============================================================ */

const DB_NAME = "trace";
const STORE = "tracks";
const REGION_STORE = "regions";
const VERSION = 2;

export interface SavedTrack {
  id: string;
  name: string;
  createdAt: number;
  updatedAt: number;
  // summary for the list (so we don't parse every file to render)
  distance: number;
  ascent: number;
  hasEle: boolean;
  hasTime: boolean;
  pointCount: number;
  bbox: [number, number, number, number]; // w,s,e,n
  gpx: string; // portable source of truth
  thumbnail: string; // inline SVG markup
}

let dbPromise: Promise<IDBDatabase> | null = null;

function openDb(): Promise<IDBDatabase> {
  if (dbPromise) return dbPromise;
  dbPromise = new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, VERSION);
    req.onupgradeneeded = () => {
      const db = req.result;
      if (!db.objectStoreNames.contains(STORE)) {
        db.createObjectStore(STORE, { keyPath: "id" });
      }
      if (!db.objectStoreNames.contains(REGION_STORE)) {
        db.createObjectStore(REGION_STORE, { keyPath: "id" });
      }
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
  return dbPromise;
}

function tx<T>(
  store: string,
  mode: IDBTransactionMode,
  fn: (store: IDBObjectStore) => IDBRequest<T>,
): Promise<T> {
  return openDb().then(
    (db) =>
      new Promise<T>((resolve, reject) => {
        const t = db.transaction(store, mode);
        const req = fn(t.objectStore(store));
        req.onsuccess = () => resolve(req.result);
        req.onerror = () => reject(req.error);
      }),
  );
}

export function saveTrack(rec: SavedTrack): Promise<IDBValidKey> {
  return tx(STORE, "readwrite", (s) => s.put(rec));
}

export function getAllTracks(): Promise<SavedTrack[]> {
  return tx<SavedTrack[]>(STORE, "readonly", (s) => s.getAll());
}

export function getTrack(id: string): Promise<SavedTrack | undefined> {
  return tx<SavedTrack | undefined>(STORE, "readonly", (s) => s.get(id));
}

export function deleteTrack(id: string): Promise<undefined> {
  return tx<undefined>(STORE, "readwrite", (s) => s.delete(id));
}

/* --- offline map regions --- */

export interface SavedRegion {
  id: string;
  name: string;
  bbox: [number, number, number, number]; // w,s,e,n
  zMin: number;
  zMax: number;
  tileUrls: string[]; // so we can evict them on delete
  bytes: number;
  createdAt: number;
}

export function saveRegion(rec: SavedRegion): Promise<IDBValidKey> {
  return tx(REGION_STORE, "readwrite", (s) => s.put(rec));
}

export function getAllRegions(): Promise<SavedRegion[]> {
  return tx<SavedRegion[]>(REGION_STORE, "readonly", (s) => s.getAll());
}

export function deleteRegion(id: string): Promise<undefined> {
  return tx<undefined>(REGION_STORE, "readwrite", (s) => s.delete(id));
}
