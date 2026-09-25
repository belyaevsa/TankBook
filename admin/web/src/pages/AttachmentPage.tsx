import { Link, useParams } from 'react-router'
import type { Attachment } from '../api'
import { useContent } from '../useContent'

export default function AttachmentPage({ onUnauthorized }: { onUnauthorized: () => void }) {
  const { id = '', attachmentId = '' } = useParams()
  const path = `/api/accounts/${encodeURIComponent(id)}/attachments/${encodeURIComponent(attachmentId)}`
  const { data: a, error } = useContent<Attachment>(path, onUnauthorized, 'No such attachment on this account.')

  if (error) return <p className="error">{error}</p>
  if (!a) return <p className="muted">Loading…</p>

  return (
    <section>
      <h2>Attachment</h2>
      <dl className="facts">
        <dt>Id</dt>
        <dd className="mono">{a.id}</dd>
        <dt>Account</dt>
        <dd className="mono">
          <Link to={`/accounts/${id}`}>{id}</Link>
        </dd>
        <dt>Kind</dt>
        <dd>{a.kind}</dd>
        <dt>Created</dt>
        <dd>{a.createdAt ? new Date(a.createdAt).toLocaleString() : '-'}</dd>
        <dt>Size</dt>
        <dd>{a.sizeBytes != null ? `${(a.sizeBytes / 1024).toFixed(0)} KB` : '-'}</dd>
        <dt>sha256</dt>
        <dd className="mono">{a.sha256 ?? '-'}</dd>
        <dt>Printed time</dt>
        <dd>{a.extractedTimestamp ?? '-'}</dd>
      </dl>
      <h3>File</h3>
      {!a.fileStored ? (
        <p className="muted">Not uploaded - the device has not synced this file, or it was purged.</p>
      ) : a.kind === 'pdf' ? (
        <a href={`${path}/file`} target="_blank" rel="noreferrer">
          Open the PDF
        </a>
      ) : (
        <a href={`${path}/file`} target="_blank" rel="noreferrer">
          <img className="photo" alt="attachment" src={`${path}/file`} />
        </a>
      )}
      <h3>OCR text</h3>
      {a.ocrText ? <pre>{a.ocrText}</pre> : <p className="muted">None.</p>}
      <h3>What the scan assigned</h3>
      {a.extractionMeta ? <pre>{JSON.stringify(a.extractionMeta, null, 2)}</pre> : <p className="muted">None.</p>}
    </section>
  )
}
