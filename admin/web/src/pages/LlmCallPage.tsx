import { Link, useParams } from 'react-router'
import { pretty, type LlmCall } from '../api'
import { useContent } from '../useContent'

export default function LlmCallPage({ onUnauthorized }: { onUnauthorized: () => void }) {
  const { id = '' } = useParams()
  const path = `/api/llm-calls/${encodeURIComponent(id)}`
  const { data: call, error } = useContent<LlmCall>(path, onUnauthorized, 'No LLM call with this id.')

  if (error) return <p className="error">{error}</p>
  if (!call) return <p className="muted">Loading…</p>

  return (
    <section>
      <h2>LLM call</h2>
      <dl className="facts">
        <dt>Id</dt>
        <dd className="mono">{call.id}</dd>
        <dt>Account</dt>
        <dd className="mono">
          <Link to={`/accounts/${call.accountId}`}>{call.accountId}</Link>
        </dd>
        <dt>Device</dt>
        <dd className="mono">{call.deviceId ?? '-'}</dd>
        <dt>When</dt>
        <dd>{new Date(call.createdAt).toLocaleString()}</dd>
        <dt>Kind</dt>
        <dd>{call.kind}</dd>
        <dt>Model</dt>
        <dd>
          {call.modelId} <span className="muted">{call.vendor}</span>
        </dd>
        <dt>Outcome</dt>
        <dd>
          {call.outcome} <span className="muted">{call.category}</span>
        </dd>
        <dt>Tokens</dt>
        <dd>
          {call.promptTokens} in / {call.completionTokens} out{call.thinkingEnabled ? ', thinking' : ''}
        </dd>
        <dt>Cost</dt>
        <dd>
          {call.cost.toFixed(6)} {call.currency}
        </dd>
        <dt>Duration</dt>
        <dd>{call.durationMs} ms</dd>
      </dl>
      <h3>Prompt image</h3>
      {call.promptPurged ? (
        <p className="muted">Not kept - purged after 30 days, with the account, or never written.</p>
      ) : (
        <div className="pages">
          {Array.from({ length: call.pages }, (_, n) => (
            <a key={n} href={`${path}/pages/${n}`} target="_blank" rel="noreferrer">
              <img alt={`page ${n + 1}`} src={`${path}/pages/${n}`} />
            </a>
          ))}
        </div>
      )}
      <h3>Response</h3>
      {call.responseBody ? <pre>{pretty(call.responseBody)}</pre> : <p className="muted">No body kept.</p>}
      {call.thinkingBody && (
        <details>
          <summary>Thinking</summary>
          <pre>{call.thinkingBody}</pre>
        </details>
      )}
      {call.promptBody && (
        <details>
          <summary>Prompt text</summary>
          <pre>{call.promptBody}</pre>
        </details>
      )}
    </section>
  )
}
