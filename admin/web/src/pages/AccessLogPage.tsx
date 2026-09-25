import { useCallback, useEffect, useState } from 'react'
import { getJson, Unauthorized, type AccessEntry } from '../api'

const PAGE = 50

export default function AccessLogPage({ onUnauthorized }: { onUnauthorized: () => void }) {
  const [entries, setEntries] = useState<AccessEntry[]>([])
  const [more, setMore] = useState(false)

  const load = useCallback(
    (before?: number) => {
      const q = new URLSearchParams({ limit: String(PAGE) })
      if (before) q.set('before', String(before))
      getJson<AccessEntry[]>(`/api/access-log?${q}`)
        .then((page) => {
          setEntries((prev) => (before ? [...prev, ...page] : page))
          setMore(page.length === PAGE)
        })
        .catch((e) => {
          if (e instanceof Unauthorized) onUnauthorized()
        })
    },
    [onUnauthorized],
  )

  useEffect(() => load(), [load])

  return (
    <section>
      <h2>Access log</h2>
      <table>
        <thead>
          <tr>
            <th>When</th>
            <th>Who</th>
            <th>What</th>
            <th>Id</th>
            <th>Status</th>
          </tr>
        </thead>
        <tbody>
          {entries.map((e) => (
            <tr key={e.id}>
              <td>{new Date(e.at).toLocaleString()}</td>
              <td>{e.actor}</td>
              <td>{e.kind}</td>
              <td className="mono">{e.targetId}</td>
              <td>{e.status}</td>
            </tr>
          ))}
        </tbody>
      </table>
      {more && (
        <button className="link" onClick={() => load(entries[entries.length - 1]?.id)}>
          Older
        </button>
      )}
    </section>
  )
}
