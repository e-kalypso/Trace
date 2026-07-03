/* ============================================================
   Notifications locales — instructions de guidage sans voix.
   Natif : @capacitor/local-notifications (fonctionne écran
   éteint grâce au mode arrière-plan). Web : API Notification.
   ============================================================ */
import { Capacitor } from "@capacitor/core";
import { LocalNotifications } from "@capacitor/local-notifications";
import { Haptics, ImpactStyle } from "@capacitor/haptics";

const isNative = Capacitor.isNativePlatform();
let seq = 1;

export async function requestNotifyPermission(): Promise<boolean> {
  if (isNative) {
    try {
      const st = await LocalNotifications.requestPermissions();
      return st.display === "granted";
    } catch {
      return false;
    }
  }
  if (!("Notification" in window)) return false;
  if (Notification.permission === "granted") return true;
  return (await Notification.requestPermission()) === "granted";
}

/** Notification d'instruction (virage, hors-tracé, arrivée). */
export async function notify(title: string, body: string): Promise<void> {
  try {
    if (isNative) {
      await LocalNotifications.schedule({
        notifications: [
          { id: seq++, title, body, schedule: { at: new Date(Date.now() + 50) } },
        ],
      });
      await Haptics.impact({ style: ImpactStyle.Medium }).catch(() => undefined);
    } else if ("Notification" in window && Notification.permission === "granted") {
      new Notification(title, { body, silent: false });
    }
  } catch {
    /* la bannière in-app reste le canal principal */
  }
}
