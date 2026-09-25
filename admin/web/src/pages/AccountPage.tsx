import { useEffect, useState } from 'react'
import { useParams } from 'react-router'
import { getJson, NotFound, Unauthorized, type Account } from '../api'

export default function AccountPage({ onUnauthorized }: { onUnauthorized: () => void }) {
  const { id = '' } = useParams()
  const [account, setAccount] = useState<Account | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    setAccount(null)
    setError(null)
    getJson<Account>(`/api/accounts/${encodeURIComponent(id)}`)
      .then(setAccount)
      .catch((e) => {
        if (e instanceof Unauthorized) onUnauthorized()
        else setError(e instanceof NotFound ? 'No account with this id.' : String(e))
      })
  }, [id, onUnauthorized])

  if (error) return <p className="error">{error}</p>
  if (!account) return <p className="muted">Loading…</p>

  return (
    <section>
      <h2>Account</h2>
      <dl className="facts">
        <dt>Id</dt>
        <dd className="mono">{account.id}</dd>
        <dt>Email</dt>
        <dd>{account.email}</dd>
        <dt>Signed in with</dt>
        <dd>{account.provider === 'apple' ? 'Apple' : 'Google'}</dd>
        <dt>Created</dt>
        <dd>{new Date(account.createdAt).toLocaleString()}</dd>
        {account.deletedAt && (
          <>
            <dt>Deleted</dt>
            <dd>{new Date(account.deletedAt).toLocaleString()}</dd>
          </>
        )}
      </dl>
      <h3>Devices</h3>
      <table>
        <thead>
          <tr>
            <th>Name</th>
            <th>Platform</th>
            <th>Last seen</th>
            <th>Id</th>
          </tr>
        </thead>
        <tbody>
          {account.devices.map((d) => (
            <tr key={d.id}>
              <td>{d.name}</td>
              <td>{d.platform}</td>
              <td>{new Date(d.lastSeenAt).toLocaleString()}</td>
              <td className="mono">{d.id}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </section>
  )
}
