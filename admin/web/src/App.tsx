import { useEffect, useState } from 'react'
import { Route, Routes } from 'react-router'
import { getJson } from './api'
import SignIn from './pages/SignIn'
import Shell from './pages/Shell'
import AccountPage from './pages/AccountPage'
import AccessLogPage from './pages/AccessLogPage'
import Home from './pages/Home'

// Signed out, the whole app is the sign-in page; nothing else is reachable without a
// session (the service enforces it too - this only avoids rendering empty pages).
export default function App() {
  const [label, setLabel] = useState<string | null | undefined>(undefined)

  useEffect(() => {
    getJson<{ label: string }>('/api/me')
      .then((me) => setLabel(me.label))
      .catch(() => setLabel(null))
  }, [])

  if (label === undefined) return <p className="muted pad">Loading…</p>
  if (label === null) return <SignIn onSignedIn={setLabel} />

  return (
    <Routes>
      <Route element={<Shell label={label} onSignedOut={() => setLabel(null)} />}>
        <Route index element={<Home />} />
        <Route path="accounts/:id" element={<AccountPage onUnauthorized={() => setLabel(null)} />} />
        <Route path="access-log" element={<AccessLogPage onUnauthorized={() => setLabel(null)} />} />
      </Route>
    </Routes>
  )
}
