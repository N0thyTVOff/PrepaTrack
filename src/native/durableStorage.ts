import { Capacitor, registerPlugin } from '@capacitor/core'

interface DurableStoragePlugin {
  save(options: { data: string }): Promise<void>
  load(): Promise<{ data?: string | null }>
}

const plugin = registerPlugin<DurableStoragePlugin>('DurableStorage')
const supported = () => Capacitor.isNativePlatform() && Capacitor.getPlatform() === 'ios'

export async function recoverDurableBackup(): Promise<void> {
  if (!supported()) return
  try {
    const { data } = await plugin.load()
    if (!data) return
    const { restoreBackup } = await import('../db/backup')
    await restoreBackup(data)
  } catch {
    // IndexedDB reste la source principale. Une copie native illisible ne doit
    // jamais empêcher l'application de démarrer.
  }
}

let timer: ReturnType<typeof setTimeout> | undefined
let pending = false

/** Regroupe les écritures rapprochées et persiste une copie atomique hors WebView. */
export function scheduleDurableBackup(): void {
  if (!supported()) return
  pending = true
  if (timer) return
  timer = setTimeout(async () => {
    timer = undefined
    if (!pending) return
    pending = false
    try {
      const { buildBackup } = await import('../db/backup')
      await plugin.save({ data: JSON.stringify(await buildBackup()) })
    } catch {
      // La copie principale IndexedDB reste utilisable ; une prochaine écriture
      // retentera automatiquement le miroir natif.
    } finally {
      if (pending) scheduleDurableBackup()
    }
  }, 250)
}
