import { startAuthentication, startRegistration } from '@simplewebauthn/browser'
import { postJson } from './api'

type Ceremony = { ceremonyId: string; options: unknown }

// The service holds each ceremony's options under `ceremonyId` for five minutes;
// the browser only relays the authenticator's answer.
export async function register(label: string, bootstrapToken?: string): Promise<string> {
  const ceremony = await postJson<Ceremony>('/auth/register/options', { label, bootstrapToken })
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const response = await startRegistration({ optionsJSON: ceremony.options as any })
  const done = await postJson<{ label: string }>('/auth/register/verify', { ceremonyId: ceremony.ceremonyId, response })
  return done.label
}

export async function signIn(): Promise<string> {
  const ceremony = await postJson<Ceremony>('/auth/login/options', {})
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const response = await startAuthentication({ optionsJSON: ceremony.options as any })
  const done = await postJson<{ label: string }>('/auth/login/verify', { ceremonyId: ceremony.ceremonyId, response })
  return done.label
}

export async function signOut(): Promise<void> {
  await postJson('/auth/logout', {})
}
