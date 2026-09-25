// The admin service's JSON routes. Same-origin cookies carry the session; a 401 means
// the session is gone and the app returns to sign-in.
export class Unauthorized extends Error {}
export class NotFound extends Error {}

export async function getJson<T>(path: string): Promise<T> {
  const res = await fetch(path, { credentials: 'same-origin' })
  if (res.status === 401) throw new Unauthorized()
  if (res.status === 404) throw new NotFound()
  if (!res.ok) throw new Error(`${path}: ${res.status}`)
  return (await res.json()) as T
}

export async function postJson<T>(path: string, body: unknown): Promise<T> {
  const res = await fetch(path, {
    method: 'POST',
    credentials: 'same-origin',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body ?? {}),
  })
  if (res.status === 401) throw new Unauthorized()
  if (res.status === 403) throw new Error('Refused: the token is not valid, or a passkey already exists.')
  if (res.status === 429) throw new Error('Too many attempts - wait a minute.')
  if (!res.ok) throw new Error(`${path}: ${res.status}`)
  const text = await res.text()
  return (text ? JSON.parse(text) : {}) as T
}

export type Device = { id: string; name: string; platform: string; lastSeenAt: string }
export type Account = {
  id: string
  createdAt: string
  deletedAt: string | null
  provider: 'apple' | 'google'
  email: string
  devices: Device[]
}
export type LookupHit = { kind: 'account' | 'llm-call'; id: string }
export type AccessEntry = {
  id: number
  at: string
  actor: string
  kind: string
  targetId: string | null
  route: string
  status: number
}

/** Where a lookup hit is shown. */
export function routeForHit(hit: LookupHit): string {
  switch (hit.kind) {
    case 'account':
      return `/accounts/${hit.id}`
    case 'llm-call':
      return `/llm-calls/${hit.id}`
  }
}

export type LlmCallSummary = {
  id: string
  createdAt: string
  kind: string
  modelId: string
  vendor: string
  outcome: string
  category: string
  promptTokens: number
  completionTokens: number
  cost: number
  currency: string
  durationMs: number
  pages: number
}
export type LlmCall = LlmCallSummary & {
  accountId: string
  deviceId: string | null
  thinkingEnabled: boolean
  promptPurged: boolean
  promptBody: string | null
  responseBody: string | null
  thinkingBody: string | null
}
export type AttachmentSummary = {
  id: string
  kind: 'photo' | 'pdf'
  createdAt: string | null
  sha256: string | null
  sizeBytes: number | null
  thumbnailBase64: string | null
  hasOcrText: boolean
}
export type Attachment = {
  id: string
  kind: 'photo' | 'pdf'
  createdAt: string | null
  sha256: string | null
  sizeBytes: number | null
  fileStored: boolean
  extractedTimestamp: string | null
  ocrText: string | null
  extractionMeta: unknown
}

/** A response body as the model wrote it: pretty JSON when it parses, the text otherwise. */
export function pretty(body: string | null): string {
  if (!body) return ''
  try {
    return JSON.stringify(JSON.parse(body), null, 2)
  } catch {
    return body
  }
}
