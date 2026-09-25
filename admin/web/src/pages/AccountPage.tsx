import { Link, useParams } from 'react-router'
import type { Account, AttachmentSummary, LlmCallSummary } from '../api'
import { useContent } from '../useContent'

type Props = { onUnauthorized: () => void }

export default function AccountPage({ onUnauthorized }: Props) {
  const { id = '' } = useParams()
  const base = `/api/accounts/${encodeURIComponent(id)}`
  const { data: account, error } = useContent<Account>(base, onUnauthorized, 'No account with this id.')

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
      <LlmCalls path={`${base}/llm-calls`} onUnauthorized={onUnauthorized} />
      <Attachments accountId={account.id} path={`${base}/attachments`} onUnauthorized={onUnauthorized} />
    </section>
  )
}

function LlmCalls({ path, onUnauthorized }: { path: string } & Props) {
  const { data: calls, error } = useContent<LlmCallSummary[]>(path, onUnauthorized)
  return (
    <>
      <h3>LLM calls</h3>
      {error && <p className="error">{error}</p>}
      {calls && calls.length === 0 && <p className="muted">None.</p>}
      {calls && calls.length > 0 && (
        <table>
          <thead>
            <tr>
              <th>When</th>
              <th>Kind</th>
              <th>Model</th>
              <th>Outcome</th>
              <th>Tokens in / out</th>
              <th>Cost</th>
              <th>Pages</th>
            </tr>
          </thead>
          <tbody>
            {calls.map((c) => (
              <tr key={c.id}>
                <td>
                  <Link to={`/llm-calls/${c.id}`}>{new Date(c.createdAt).toLocaleString()}</Link>
                </td>
                <td>{c.kind}</td>
                <td>{c.modelId}</td>
                <td>
                  {c.outcome} <span className="muted">{c.category}</span>
                </td>
                <td>
                  {c.promptTokens} / {c.completionTokens}
                </td>
                <td>
                  {c.cost.toFixed(4)} {c.currency}
                </td>
                <td>{c.pages}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </>
  )
}

function Attachments({ accountId, path, onUnauthorized }: { accountId: string; path: string } & Props) {
  const { data: items, error } = useContent<AttachmentSummary[]>(path, onUnauthorized)
  return (
    <>
      <h3>Attachments</h3>
      {error && <p className="error">{error}</p>}
      {items && items.length === 0 && <p className="muted">None.</p>}
      <div className="grid">
        {items?.map((a) => (
          <Link key={a.id} className="tile" to={`/accounts/${accountId}/attachments/${a.id}`}>
            {a.thumbnailBase64 ? (
              <img alt="" src={`data:image/jpeg;base64,${a.thumbnailBase64}`} />
            ) : (
              <span className="muted">{a.kind}</span>
            )}
            <span className="muted">{a.createdAt ? new Date(a.createdAt).toLocaleDateString() : ''}</span>
          </Link>
        ))}
      </div>
    </>
  )
}
