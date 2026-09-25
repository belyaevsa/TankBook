import { useState } from 'react'
import { NavLink, Outlet, useNavigate } from 'react-router'
import { getJson, NotFound, routeForHit, type LookupHit } from '../api'
import { signOut } from '../passkey'

// One lookup box, exact ids only: there is no list of users and no search over content
// (docs/SECURITY.md -> "The admin viewer"). Every lookup is written to the access log.
export default function Shell({ label, onSignedOut }: { label: string; onSignedOut: () => void }) {
  const navigate = useNavigate()
  const [query, setQuery] = useState('')
  const [message, setMessage] = useState<string | null>(null)

  async function lookup(e: React.FormEvent) {
    e.preventDefault()
    setMessage(null)
    const q = query.trim()
    if (!q) return
    try {
      const hit = await getJson<LookupHit>(`/api/lookup?q=${encodeURIComponent(q)}`)
      navigate(routeForHit(hit))
    } catch (err) {
      setMessage(err instanceof NotFound ? 'Nothing with that exact id.' : String(err))
    }
  }

  return (
    <div className="shell">
      <header>
        <strong>Tankbook admin</strong>
        <form className="lookup" onSubmit={lookup} role="search">
          <input
            aria-label="Lookup"
            placeholder="case id, traceId or account id"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
          />
          <button type="submit">Open</button>
        </form>
        <nav>
          <NavLink to="/access-log">Access log</NavLink>
        </nav>
        <span className="muted">{label}</span>
        <button
          className="link"
          onClick={async () => {
            await signOut()
            onSignedOut()
          }}
        >
          Sign out
        </button>
      </header>
      {message && <p className="error pad">{message}</p>}
      <main className="pad">
        <Outlet />
      </main>
    </div>
  )
}
