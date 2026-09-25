import { useState } from 'react'
import { register, signIn } from '../passkey'

// The only page without a session: sign in with the passkey, or - the first time only -
// register one with the bootstrap token from the server's secret store.
export default function SignIn({ onSignedIn }: { onSignedIn: (label: string) => void }) {
  const [registering, setRegistering] = useState(false)
  const [token, setToken] = useState('')
  const [label, setLabel] = useState('iPhone')
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  async function run(action: () => Promise<string>) {
    setBusy(true)
    setError(null)
    try {
      onSignedIn(await action())
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  return (
    <main className="signin">
      <h1>Tankbook admin</h1>
      {!registering ? (
        <>
          <button className="primary" disabled={busy} onClick={() => run(signIn)}>
            Sign in with passkey
          </button>
          <button className="link" onClick={() => setRegistering(true)}>
            First time? Register with a bootstrap token
          </button>
        </>
      ) : (
        <form
          onSubmit={(e) => {
            e.preventDefault()
            run(() => register(label, token))
          }}
        >
          <label>
            Bootstrap token
            <input value={token} onChange={(e) => setToken(e.target.value)} autoComplete="off" required />
          </label>
          <label>
            This device's name
            <input value={label} onChange={(e) => setLabel(e.target.value)} maxLength={40} required />
          </label>
          <button className="primary" disabled={busy} type="submit">
            Create passkey
          </button>
          <button className="link" type="button" onClick={() => setRegistering(false)}>
            Back to sign in
          </button>
        </form>
      )}
      {error && <p className="error">{error}</p>}
    </main>
  )
}
