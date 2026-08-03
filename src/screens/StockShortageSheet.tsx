import { useEffect, useRef, useState } from 'react'
import { BigButton } from '../components/BigButton'
import { Sheet } from '../components/Sheet'
import type { StockShortage } from '../core/types'
import type { StockShortageInput } from '../db/repo'

interface Props {
  open: boolean
  shortage?: StockShortage
  onClose: () => void
  onSave: (input: StockShortageInput) => Promise<void>
  onDelete?: () => Promise<void>
  onSetResolved?: (resolved: boolean) => Promise<void>
}

export function StockShortageSheet({
  open,
  shortage,
  onClose,
  onSave,
  onDelete,
  onSetResolved,
}: Props) {
  const [quantity, setQuantity] = useState('')
  const [reference, setReference] = useState('')
  const [location, setLocation] = useState('')
  const [label, setLabel] = useState('')
  const [note, setNote] = useState('')
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string>()
  const submitLocked = useRef(false)

  useEffect(() => {
    if (!open) return
    setQuantity(shortage ? String(shortage.quantity) : '')
    setReference(shortage?.reference ?? '')
    setLocation(shortage?.location ?? '')
    setLabel(shortage?.label ?? '')
    setNote(shortage?.note ?? '')
    setSaving(false)
    submitLocked.current = false
    setError(undefined)
  }, [open, shortage])

  async function submit() {
    if (submitLocked.current) return
    const parsed = Number(quantity)
    if (!Number.isInteger(parsed) || parsed <= 0) {
      setError('Indique une quantité entière strictement positive.')
      return
    }
    submitLocked.current = true
    setSaving(true)
    setError(undefined)
    try {
      await onSave({ quantity: parsed, reference, location, label, note })
      onClose()
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : 'Enregistrement impossible.')
      submitLocked.current = false
      setSaving(false)
    }
  }

  return (
    <Sheet
      open={open}
      title={shortage ? 'Corriger la rupture' : 'Rupture de stock'}
      onClose={saving ? undefined : onClose}
    >
      <div className="mx-auto flex max-w-md flex-col gap-4">
        <label className="flex flex-col gap-1 text-sm font-semibold text-slate-300">
          Quantité manquante <span className="text-bad">*</span>
          <input
            inputMode="numeric"
            pattern="[0-9]*"
            value={quantity}
            onChange={(event) => setQuantity(event.target.value.replace(/\D/g, ''))}
            className="min-h-touch rounded-xl border border-ink-600 bg-ink-800 px-4 text-2xl font-bold"
            placeholder="0"
            autoFocus
          />
        </label>

        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <TextField label="Référence" value={reference} onChange={setReference} />
          <TextField label="Emplacement" value={location} onChange={setLocation} />
        </div>
        <TextField label="Libellé" value={label} onChange={setLabel} />
        <label className="flex flex-col gap-1 text-sm font-semibold text-slate-300">
          Note
          <textarea
            value={note}
            onChange={(event) => setNote(event.target.value)}
            className="min-h-24 rounded-xl border border-ink-600 bg-ink-800 p-3 font-normal"
            placeholder="Précision facultative"
          />
        </label>

        {error && <p role="alert" className="text-sm font-semibold text-bad">{error}</p>}
        <BigButton
          label={saving ? 'Enregistrement…' : shortage ? 'Enregistrer' : 'Signaler la rupture'}
          onClick={submit}
          disabled={saving}
        />

        {shortage && onSetResolved && (
          <button
            type="button"
            disabled={saving}
            onClick={async () => {
              setSaving(true)
              await onSetResolved(!shortage.resolved)
              onClose()
            }}
            className="pressable rounded-xl bg-ink-700 py-3 font-semibold text-slate-300"
          >
            {shortage.resolved ? 'Marquer comme non résolue' : 'Marquer comme résolue'}
          </button>
        )}

        {shortage && onDelete && (
          <button
            type="button"
            disabled={saving}
            onClick={async () => {
              setSaving(true)
              await onDelete()
              onClose()
            }}
            className="pressable rounded-xl border border-bad/50 py-3 font-semibold text-bad"
          >
            Supprimer ce signalement
          </button>
        )}
      </div>
    </Sheet>
  )
}

function TextField({
  label,
  value,
  onChange,
}: {
  label: string
  value: string
  onChange: (value: string) => void
}) {
  return (
    <label className="flex flex-col gap-1 text-sm font-semibold text-slate-300">
      {label}
      <input
        value={value}
        onChange={(event) => onChange(event.target.value)}
        className="min-h-touch rounded-xl border border-ink-600 bg-ink-800 px-3 font-normal"
      />
    </label>
  )
}
